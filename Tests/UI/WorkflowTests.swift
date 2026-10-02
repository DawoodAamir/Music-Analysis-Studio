import XCTest

@MainActor final class WorkflowTests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  func testAnalyzeAndReopen() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Fixtures/StudioPulse.wav")
    let app = XCUIApplication()
    app.launchEnvironment["MUSIC_TEST_STORE"] = UUID().uuidString
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["Import audio"].waitForExistence(timeout: 15), app.debugDescription)
    app.buttons["Import audio"].click()
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"]
    XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
    path.click()
    path.typeText(fixture.path)
    app.typeKey(.return, modifierFlags: [])
    let open = app.sheets["open-panel"].buttons["OKButton"]
    XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
    open.click()
    XCTAssertTrue(app.buttons["Export report"].waitForExistence(timeout: 240), app.debugDescription)
    XCTAssertTrue(app.staticTexts["Tempo"].exists)
    XCTAssertTrue(app.staticTexts["Integrated loudness"].exists)
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = "Music analysis"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.terminate()
    app.launch()
    app.activate()
    let row = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "music-report-")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
    row.click()
    XCTAssertTrue(app.buttons["Export report"].waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(app.sliders["Playback position"].exists)
  }
}
