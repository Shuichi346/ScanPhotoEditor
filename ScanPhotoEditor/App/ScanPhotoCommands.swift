import SwiftUI

struct ScanPhotoCommands: Commands {
    @FocusedValue(\.projectActions) private var actions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export…") {
                actions?.export()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }

        CommandMenu("Geometry") {
            Button("Rotate Clockwise") {
                actions?.rotateClockwise()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(actions == nil)

            Button("Flip Horizontal") {
                actions?.flipHorizontal()
            }
            .disabled(actions == nil)

            Button("Flip Vertical") {
                actions?.flipVertical()
            }
            .disabled(actions == nil)

            Divider()

            Button("Add Region") {
                actions?.addRegion()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(actions == nil)

            Button("Delete Region") {
                actions?.deleteRegion()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(actions == nil)

            Button("Rerun Detection") {
                actions?.rerunDetection()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button("Toggle Grid") {
                actions?.toggleGrid()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(actions == nil)
        }
    }
}

struct ProjectActions {
    let export: () -> Void
    let rotateClockwise: () -> Void
    let flipHorizontal: () -> Void
    let flipVertical: () -> Void
    let addRegion: () -> Void
    let deleteRegion: () -> Void
    let rerunDetection: () -> Void
    let toggleGrid: () -> Void
}

private struct ProjectActionsKey: FocusedValueKey {
    typealias Value = ProjectActions
}

extension FocusedValues {
    var projectActions: ProjectActions? {
        get { self[ProjectActionsKey.self] }
        set { self[ProjectActionsKey.self] = newValue }
    }
}

