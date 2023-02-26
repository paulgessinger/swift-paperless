//
//  swift_paperlessUITests.swift
//  swift-paperlessUITests
//
//  Created by Paul Gessinger on 13.02.23.
//

import XCTest

final class swift_paperlessUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        XCUIApplication().navigationBars["Documents"].searchFields["Search"].tap()

        app/*@START_MENU_TOKEN@*/ .keys["E"]/*[[".keyboards.keys[\"E\"]",".keys[\"E\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/ .tap()
        app.keys["s"].tap()
        app.keys["t"].tap()
        app/*@START_MENU_TOKEN@*/ .keys["a"]/*[[".keyboards.keys[\"a\"]",".keys[\"a\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/ .tap()
        app/*@START_MENU_TOKEN@*/ .buttons["Search"]/*[[".keyboards",".buttons[\"Suchen\"]",".buttons[\"Search\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/ .tap()

        sleep(5)

        
        let elementsQuery = XCUIApplication().scrollViews.otherElements
        elementsQuery.buttons["CERN: Internal Tax Certificate 2022, Statement, 14. February 2023"].tap()
        elementsQuery.buttons["congstar_EVN_2015_Oktober_2200835303_7155459549, Bank Statement, 12. February 2023"].tap()
        elementsQuery.buttons["Jefferson Lab: Registration Confirmation, 24. January 2023"].swipeUp()
        
        app.navigationBars["Documents"].buttons["Cancel"].tap()

        sleep(5)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
