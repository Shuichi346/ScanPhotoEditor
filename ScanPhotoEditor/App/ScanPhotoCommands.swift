import SwiftUI

struct ScanPhotoCommands: Commands {
    @FocusedValue(\.projectActions) private var actions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export…") {
                actions?.export()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(actions?.canExport != true)
        }

        CommandMenu("Arrange") {
            Button("Sort Images by File Name") {
                actions?.sortImagesByFileName()
            }
            .disabled(actions?.canSortImages != true)
        }

        CommandMenu("Geometry") {
            Button("Rotate Clockwise") {
                actions?.rotateClockwise()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(actions?.canEditRegion != true)

            Button("Flip Horizontal") {
                actions?.flipHorizontal()
            }
            .disabled(actions?.canEditRegion != true)

            Button("Flip Vertical") {
                actions?.flipVertical()
            }
            .disabled(actions?.canEditRegion != true)

            Divider()

            Button("Add Region") {
                actions?.addRegion()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(actions?.canEditSource != true)

            Button("Delete Region") {
                actions?.deleteRegion()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(actions?.canEditRegion != true)

            Button("Remove Source") {
                actions?.removeSource()
            }
            .disabled(actions?.canEditSource != true)

            Button("Rerun Detection") {
                actions?.rerunDetection()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(actions?.canEditSource != true)

            Button("Toggle Grid") {
                actions?.toggleGrid()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(actions?.canEditRegion != true)
        }
    }
}

struct ProjectActions {
    let export: () -> Void
    let canExport: Bool
    let sortImagesByFileName: () -> Void
    let canSortImages: Bool
    let canEditSource: Bool
    let canEditRegion: Bool
    let rotateClockwise: () -> Void
    let flipHorizontal: () -> Void
    let flipVertical: () -> Void
    let addRegion: () -> Void
    let deleteRegion: () -> Void
    let removeSource: () -> Void
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
