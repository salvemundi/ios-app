import XCTest

/// Runs Apple's automated accessibility audit on each main screen, using the app's demo mode (no login, no network).
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = true // report every finding in one run
        app.launchArguments = ["--demo"]
        app.launch()
    }

    private func audit(_ screen: String) throws {
        try app.performAccessibilityAudit { issue in
            // Accepted findings go here, one by one. Never silence a whole audit type.
            print("AUDIT[\(screen)] \(issue.compactDescription) | element: \(issue.element?.label ?? "-") [\(issue.element?.elementType.rawValue ?? 0)] | \(issue.detailedDescription)")
            return false
        }
    }

    func testHome() throws { try audit("Home") }

    func testActivities() throws {
        app.tabBars.buttons["Activiteiten"].tap()
        try audit("Activiteiten")
    }

    func testTickets() throws {
        app.tabBars.buttons["Tickets"].tap()
        try audit("Tickets")
    }

    func testProfile() throws {
        app.tabBars.buttons["Profiel"].tap()
        try audit("Profiel")
    }
}
