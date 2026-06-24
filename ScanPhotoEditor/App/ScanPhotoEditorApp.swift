import SwiftUI

@main
struct ScanPhotoEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PhotoProjectDocument() }) { configuration in
            ProjectRootView(document: configuration.document)
                .frame(minWidth: 1_080, minHeight: 680)
        }
        .commands {
            ScanPhotoCommands()
        }
    }
}
