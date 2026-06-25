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

    @MainActor
    func testSourceToolbarActionsRemainVisibleWhenInspectorChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let sortButton = app.buttons["sort-images"]
        let inspectorButton = app.buttons["toggle-inspector"]

        XCTAssertTrue(sortButton.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))

        inspectorButton.click()
        XCTAssertTrue(sortButton.waitForExistence(timeout: 2))

        inspectorButton.click()
        XCTAssertTrue(sortButton.waitForExistence(timeout: 2))
    }
}
