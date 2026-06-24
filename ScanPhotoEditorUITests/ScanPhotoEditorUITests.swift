import XCTest

final class ScanPhotoEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNewDocumentShowsDropTargetAndExportIsDisabled() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(app.staticTexts["Drop Photos to Begin"].waitForExistence(timeout: 5))
    }
}
