import AppKit
import SwiftUI

struct GeometryInspectorView: View {
    let store: ProjectEditingStore
    let undoManager: UndoManager?

    var body: some View {
        Form {
            if let source = store.selectedSource, let region = store.selectedRegion {
                Section("Source") {
                    LabeledContent("Name", value: source.displayName)
                    LabeledContent(
                        "Pixels",
                        value: "\(source.pixelWidth) × \(source.pixelHeight)"
                    )
                    LabeledContent("Status", value: region.reviewState == .ready ? "Ready" : "Needs Review")
                }

                Section("Geometry") {
                    LabeledContent("Transform") {
                        ControlGroup {
                            Button {
                                store.rotateClockwise(undoManager: undoManager)
                            } label: {
                                Label("Rotate Clockwise", systemImage: "rotate.right")
                            }
                            .help("Rotate clockwise")

                            Button {
                                store.flipHorizontal(undoManager: undoManager)
                            } label: {
                                Label("Flip Horizontal", systemImage: "arrow.left.and.right")
                            }
                            .help("Flip horizontally")

                            Button {
                                store.flipVertical(undoManager: undoManager)
                            } label: {
                                Label("Flip Vertical", systemImage: "arrow.up.and.down")
                            }
                            .help("Flip vertically")
                        }
                    }

                    Button {
                        store.resetSelectedRegion(undoManager: undoManager)
                    } label: {
                        Label("Reset to Full Frame", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("Detection") {
                    Button {
                        store.rerunDetection(undoManager: undoManager)
                    } label: {
                        Label("Rerun Detection", systemImage: "viewfinder")
                    }
                }

                Section("Display") {
                    @Bindable var store = store
                    Toggle("8×8 Grid", isOn: $store.showGrid)
                }

                Section {
                    Text("Only orientation, perspective, rotation, and explicit flips are applied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "No Region Selected",
                    systemImage: "viewfinder"
                )
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
