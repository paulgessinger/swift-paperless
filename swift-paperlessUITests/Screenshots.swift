//
//  Screenshots.swift
//  swift-paperlessUITests
//
//  Created by Paul Gessinger on 20.05.2024.
//

import XCTest

final class Screenshots: XCTestCase {
    @MainActor
    func testFlow() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        sleep(1)
        snapshot("01DocumentView")

        app.staticTexts["filterBarTagsFilterButton"].tap()

        snapshot("02TagsFilter")

        app.navigationBars.element(boundBy: 1)
            .buttons["dismissButton"].tap()

        app.collectionViews.children(matching: .cell).element(boundBy: 1).tap()

        sleep(1)

        snapshot("03DocumentDetailView")

        let navBar = XCUIApplication().navigationBars.element(boundBy: 0)
        navBar.buttons["documentEditButton"].tap()

        snapshot("03DocumentEditing")
    }
}
