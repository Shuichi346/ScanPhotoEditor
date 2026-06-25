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
                    Button("Rotate Clockwise") {
                        store.rotateClockwise(undoManager: undoManager)
                    }
                    Button("Flip Horizontal") {
                        store.flipHorizontal(undoManager: undoManager)
                    }
                    Button("Flip Vertical") {
                        store.flipVertical(undoManager: undoManager)
                    }
                    Button("Reset to Full Frame") {
                        store.resetSelectedRegion(undoManager: undoManager)
                    }
                    Button("Rerun Detection") {
                        store.rerunDetection(undoManager: undoManager)
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
