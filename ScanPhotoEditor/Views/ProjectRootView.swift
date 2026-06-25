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
                set: { if !$0 { store.cancelRerunDetectionConfirmation() } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.cancelRerunDetectionConfirmation()
            }
            Button("Replace Regions", role: .destructive) {
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
        ToolbarItem(placement: .navigation) {
            Menu {
                Button {
                    store.rerunDetection(undoManager: undoManager)
                } label: {
                    Label("Rerun Detection", systemImage: "viewfinder")
                }
                .disabled(store.selectedSource == nil)

                Button {
                    store.sortImagesByFileName(undoManager: undoManager)
                } label: {
                    Label("Sort by File Name", systemImage: "textformat.abc")
                }
                .disabled(document.manifest.sources.count < 2)

                Divider()

                Button(role: .destructive) {
                    store.removeSelectedSource(undoManager: undoManager)
                } label: {
                    Label("Remove Source", systemImage: "trash")
                }
                .disabled(store.selectedSource == nil)
            } label: {
                Label("Source Actions", systemImage: "photo.stack")
            }
            .help("Source actions")
            .disabled(document.manifest.sources.isEmpty)
            .accessibilityIdentifier("source-actions")
        }

        ToolbarItem {
            ControlGroup {
                Button {
                    store.addRegion(undoManager: undoManager)
                } label: {
                    Label("Add Region", systemImage: "plus.rectangle.on.rectangle")
                }
                .help("Add a region to the selected source")
                .disabled(store.selectedSource == nil)
                .accessibilityIdentifier("add-region")

                Button(role: .destructive) {
                    store.deleteSelectedRegion(undoManager: undoManager)
                } label: {
                    Label("Delete Region", systemImage: "trash")
                }
                .help("Delete the selected region")
                .disabled(store.selectedRegion == nil)
                .accessibilityIdentifier("delete-region")
            }
        }

        ToolbarItem {
            ControlGroup {
                Button {
                    store.rotateClockwise(undoManager: undoManager)
                } label: {
                    Label("Rotate Clockwise", systemImage: "rotate.right")
                }
                .help("Rotate the selected region clockwise")
                .disabled(store.selectedRegion == nil)
                .accessibilityIdentifier("rotate-region")

                Menu {
                    Button {
                        store.flipHorizontal(undoManager: undoManager)
                    } label: {
                        Label("Flip Horizontal", systemImage: "arrow.left.and.right")
                    }

                    Button {
                        store.flipVertical(undoManager: undoManager)
                    } label: {
                        Label("Flip Vertical", systemImage: "arrow.up.and.down")
                    }

                    Divider()

                    Button {
                        store.resetSelectedRegion(undoManager: undoManager)
                    } label: {
                        Label("Reset to Full Frame", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Label("More Geometry Actions", systemImage: "ellipsis")
                }
                .help("Flip or reset the selected region")
                .disabled(store.selectedRegion == nil)
                .accessibilityIdentifier("geometry-actions")

                Button {
                    store.showGrid.toggle()
                } label: {
                    Label(store.showGrid ? "Hide Grid" : "Show Grid", systemImage: "grid")
                }
                .help("Toggle 8×8 grid")
                .disabled(store.selectedRegion == nil)
                .accessibilityIdentifier("toggle-grid")
            }
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
            .accessibilityIdentifier("toggle-inspector")
        }
    }

    private var projectActions: ProjectActions {
        ProjectActions(
            export: { store.isExportPresented = true },
            canExport: !store.orderedRegions.isEmpty,
            sortImagesByFileName: {
                store.sortImagesByFileName(undoManager: undoManager)
            },
            canSortImages: document.manifest.sources.count > 1,
            canEditSource: store.selectedSource != nil,
            canEditRegion: store.selectedRegion != nil,
            rotateClockwise: { store.rotateClockwise(undoManager: undoManager) },
            flipHorizontal: { store.flipHorizontal(undoManager: undoManager) },
            flipVertical: { store.flipVertical(undoManager: undoManager) },
            resetRegion: { store.resetSelectedRegion(undoManager: undoManager) },
            addRegion: { store.addRegion(undoManager: undoManager) },
            deleteRegion: { store.deleteSelectedRegion(undoManager: undoManager) },
            removeSource: { store.removeSelectedSource(undoManager: undoManager) },
            rerunDetection: { store.rerunDetection(undoManager: undoManager) },
            toggleGrid: { store.showGrid.toggle() }
        )
    }
}

private struct EditorWorkspaceView: View {
    let store: ProjectEditingStore
    let undoManager: UndoManager?

    var body: some View {
        VStack(spacing: 0) {
            sourceEditor
                .frame(minHeight: 300)
            Divider()
            correctedPreview
                .frame(minHeight: 220)
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
