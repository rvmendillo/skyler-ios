import XCTest
final class LaunchTests:XCTestCase {
    func testHeroSelectionAndBattleLaunch() throws {
        let app=XCUIApplication();app.launch();XCUIDevice.shared.orientation = .landscapeLeft
        let start=app.buttons["start-match"];XCTAssertTrue(start.waitForExistence(timeout:20))
        let lobby=XCTAttachment(screenshot:app.screenshot());lobby.name="Hero Selection";lobby.lifetime = .keepAlways;add(lobby)
        start.tap();let shop=app.buttons["shop"];XCTAssertTrue(shop.waitForExistence(timeout:20));shop.tap();XCTAssertTrue(app.navigationBars["Equipment"].waitForExistence(timeout:10));app.buttons["Close"].tap()
        let battle=XCTAttachment(screenshot:app.screenshot());battle.name="Battlefield";battle.lifetime = .keepAlways;add(battle)
    }
    func testActiveBattleRemainsRunning() throws {
        let app=XCUIApplication();app.launchArguments=["--smoke-battle"];app.launch();XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["shop"].waitForExistence(timeout:60))
        let stick=app.otherElements["joystick"].firstMatch
        if stick.exists{stick.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.1,thenDragTo:stick.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.2)))}
        let deadline=Date().addingTimeInterval(12)
        while Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(1))}
        XCTAssertEqual(app.state,.runningForeground)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Active 5v5 Battle";shot.lifetime = .keepAlways;add(shot)
    }
    func testHeroSwitchAndControlSettings() throws {
        let app=XCUIApplication();app.launch();XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["hero-0"].waitForExistence(timeout:20));app.buttons["hero-0"].tap()
        XCTAssertTrue(app.staticTexts["Warden of the Dawn"].exists)
        app.buttons["hero-3"].tap();XCTAssertTrue(app.staticTexts["Astral Arcanist"].exists)
        app.buttons["start-match"].tap();XCTAssertTrue(app.buttons["shop"].waitForExistence(timeout:20))
        app.buttons["settings"].tap();XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:10))
        XCTAssertTrue(app.switches["Approach targets while holding Attack"].exists)
        app.buttons["Resume"].tap();XCTAssertTrue(app.buttons["shop"].exists)
    }
}
