import AppKit
import SwiftUI

struct ProjectSidebarView: View {
    let store: ProjectEditingStore
    let undoManager: UndoManager?
    @ObservedObject private var document: PhotoProjectDocument

    init(store: ProjectEditingStore, undoManager: UndoManager?) {
        self.store = store
        self.undoManager = undoManager
        _document = ObservedObject(wrappedValue: store.document)
    }

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedRegionID) {
            ForEach(document.manifest.sources.sorted(by: { $0.importOrder < $1.importOrder })) { source in
                Section(source.displayName) {
                    ForEach(store.orderedRegions(for: source.id)) { region in
                        SidebarRegionRow(
                            source: source,
                            region: region,
                            thumbnailData: document.thumbnailData(for: source.id)
                        )
                        .tag(region.id)
                    }
                    .onMove { offsets, destination in
                        store.moveRegions(
                            in: source.id,
                            from: offsets,
                            to: destination,
                            undoManager: undoManager
                        )
                    }
                }
            }
            .onMove { offsets, destination in
                store.moveSources(
                    from: offsets,
                    to: destination,
                    undoManager: undoManager
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Photographs")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    store.removeSelectedSource(undoManager: undoManager)
                } label: {
                    Label("Remove Source", systemImage: "trash")
                }
                .help("Remove the selected source image and all its regions")
                .disabled(store.selectedSource == nil)
            }
            ToolbarItem {
                Button {
                    store.sortImagesByFileName(undoManager: undoManager)
                } label: {
                    Label("Sort by File Name", systemImage: "textformat.abc")
                }
                .help("Sort images by file name")
                .disabled(document.manifest.sources.count < 2)
            }
        }
        .onChange(of: store.selectedRegionID) {
            store.select(regionID: store.selectedRegionID)
        }
        .safeAreaInset(edge: .bottom) {
            if document.isProcessing || !document.activityMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.activityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if document.isProcessing {
                        ProgressView(value: document.processingProgress)
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
