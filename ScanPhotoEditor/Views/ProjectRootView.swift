import AppKit
import SwiftUI

struct ProjectRootView: View {
    @Environment(\.undoManager) private var undoManager
    @ObservedObject private var document: PhotoProjectDocument
    @State private var store: ProjectEditingStore
    @State private var inspectorPresented = true

    init(document: PhotoProjectDocument) {
        _document = ObservedObject(wrappedValue: document)
        _store = State(initialValue: ProjectEditingStore(document: document))
    }

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            ProjectSidebarView(store: store, undoManager: undoManager)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            editorContent
                .inspector(isPresented: $inspectorPresented) {
                    GeometryInspectorView(store: store, undoManager: undoManager)
                        .inspectorColumnWidth(min: 230, ideal: 270, max: 340)
                }
        }
        .toolbar {
            projectToolbar
        }
        .overlay {
            if store.isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 4, dash: [12, 8]))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.importDroppedURLs(urls)
            return true
        } isTargeted: {
            store.isDropTargeted = $0
        }
        .focusedValue(\.projectActions, projectActions)
        .sheet(isPresented: $store.isExportPresented) {
            ExportSheetView(store: store)
        }
        .alert(
            "Rerun Detection?",
            isPresented: Binding(
                get: { store.confirmationMessage != nil },
                set: { if !$0 { store.confirmationMessage = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.confirmationMessage = nil
            }
            Button("Replace Regions", role: .destructive) {
                store.confirmationMessage = nil
                store.rerunDetection(force: true, undoManager: undoManager)
            }
        } message: {
            Text(store.confirmationMessage ?? "")
        }
        .alert(
            "Project Error",
            isPresented: Binding(
                get: { store.document.projectError != nil },
                set: { if !$0 { store.document.projectError = nil } }
            )
        ) {
            Button("OK") {
                store.document.projectError = nil
            }
        } message: {
            Text(store.document.projectError ?? "")
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if store.selectedRegion == nil {
            ContentUnavailableView {
                Label("Drop Photos to Begin", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Drop HEIC, JPEG, PNG, TIFF files, or folders anywhere in this window.")
            }
        } else {
            EditorWorkspaceView(store: store, undoManager: undoManager)
        }
    }

    @ToolbarContentBuilder
    private var projectToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                store.addRegion(undoManager: undoManager)
            } label: {
                Label("Add Region", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(store.selectedSource == nil)

            Button {
                store.deleteSelectedRegion(undoManager: undoManager)
            } label: {
                Label("Delete Region", systemImage: "trash")
            }
            .disabled(store.selectedRegion == nil)

            Button {
                store.rerunDetection(undoManager: undoManager)
            } label: {
                Label("Rerun Detection", systemImage: "viewfinder")
            }
            .disabled(store.selectedSource == nil)
        }

        ToolbarItemGroup {
            Button {
                store.rotateClockwise(undoManager: undoManager)
            } label: {
                Label("Rotate", systemImage: "rotate.right")
            }
            .disabled(store.selectedRegion == nil)

            Button {
                store.showGrid.toggle()
            } label: {
                Label("Grid", systemImage: "grid")
            }
            .help("Toggle 8×8 grid")
            .disabled(store.selectedRegion == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                store.isExportPresented = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(store.orderedRegions.isEmpty)
        }

        ToolbarItem {
            Button {
                inspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }

    private var projectActions: ProjectActions {
        ProjectActions(
            export: { store.isExportPresented = true },
            sortImagesByFileName: {
                store.sortImagesByFileName(undoManager: undoManager)
            },
            canSortImages: document.manifest.sources.count > 1,
            rotateClockwise: { store.rotateClockwise(undoManager: undoManager) },
            flipHorizontal: { store.flipHorizontal(undoManager: undoManager) },
            flipVertical: { store.flipVertical(undoManager: undoManager) },
            addRegion: { store.addRegion(undoManager: undoManager) },
            deleteRegion: { store.deleteSelectedRegion(undoManager: undoManager) },
            rerunDetection: { store.rerunDetection(undoManager: undoManager) },
            toggleGrid: { store.showGrid.toggle() }
        )
    }
}

private struct EditorWorkspaceView: View {
    let store: ProjectEditingStore
    let undoManager: UndoManager?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                sourceEditor
                    .frame(minWidth: 400)
                Divider()
                correctedPreview
                    .frame(minWidth: 300)
            }

            VStack(spacing: 0) {
                sourceEditor
                    .frame(minHeight: 300)
                Divider()
                correctedPreview
                    .frame(minHeight: 220)
            }
        }
    }

    private var sourceEditor: some View {
        GeometryCanvasView(store: store, undoManager: undoManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var correctedPreview: some View {
        CorrectedPreviewView(image: store.correctedPreview)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
