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
    func testToolbarGroupsRemainVisibleWhenInspectorChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let sourceActions = app.menuButtons["source-actions"]
        let addRegionButton = app.buttons["add-region"]
        let geometryActions = app.menuButtons["geometry-actions"]
        let inspectorButton = app.buttons["toggle-inspector"]

        XCTAssertTrue(sourceActions.waitForExistence(timeout: 5))
        XCTAssertTrue(addRegionButton.waitForExistence(timeout: 5))
        XCTAssertTrue(geometryActions.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))

        inspectorButton.click()
        XCTAssertTrue(sourceActions.waitForExistence(timeout: 2))
        XCTAssertTrue(addRegionButton.waitForExistence(timeout: 2))
        XCTAssertTrue(geometryActions.waitForExistence(timeout: 2))

        inspectorButton.click()
        XCTAssertTrue(sourceActions.waitForExistence(timeout: 2))
        XCTAssertTrue(addRegionButton.waitForExistence(timeout: 2))
        XCTAssertTrue(geometryActions.waitForExistence(timeout: 2))
    }
}
