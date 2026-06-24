import AppKit
import SwiftUI

struct ProjectSidebarView: View {
    let store: ProjectEditingStore
    let undoManager: UndoManager?

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedRegionID) {
            ForEach(store.document.manifest.sources.sorted(by: { $0.importOrder < $1.importOrder })) { source in
                Section(source.displayName) {
                    ForEach(source.regions) { region in
                        SidebarRegionRow(
                            source: source,
                            region: region,
                            thumbnailData: store.document.thumbnailData(for: source.id)
                        )
                        .tag(region.id)
                    }
                }
            }
            .onMove { offsets, destination in
                store.moveRegions(from: offsets, to: destination, undoManager: undoManager)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Photographs")
        .onChange(of: store.selectedRegionID) {
            store.select(regionID: store.selectedRegionID)
        }
        .safeAreaInset(edge: .bottom) {
            if store.document.isProcessing || !store.document.activityMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.document.activityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if store.document.isProcessing {
                        ProgressView(value: store.document.processingProgress)
                        Button("Cancel") {
                            store.cancelProcessing()
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
    }
}

private struct SidebarRegionRow: View {
    let source: SourceAsset
    let region: PhotoRegion
    let thumbnailData: Data?

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 42, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text("Region \(region.order + 1)")
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("\(source.displayName), region \(region.order + 1), \(statusText)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailData, let image = NSImage(data: thumbnailData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        if source.processingState == .failed {
            return "Failed"
        }
        return region.reviewState == .needsReview ? "Needs Review" : "Ready"
    }

    private var statusColor: Color {
        region.reviewState == .needsReview ? .orange : .secondary
    }
}

