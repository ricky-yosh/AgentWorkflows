import Testing
import Foundation
@testable import AgentWorkflows

@Suite("PlaceholderNameGenerator")
struct PlaceholderNameGeneratorTests {

    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    private func name(for date: Date) -> String {
        placeholderName(for: date, locale: locale, timeZone: utc)
    }

    @Test func hasUntitledEmDashPrefix() {
        let result = name(for: Date(timeIntervalSince1970: 0))
        #expect(result.hasPrefix("Untitled \u{2014} "))
    }

    @Test func formatsDeterministicAMTime() {
        // Jan 1, 1970 09:05 UTC
        let date = Date(timeIntervalSince1970: 9 * 3600 + 5 * 60)
        #expect(name(for: date) == "Untitled \u{2014} Jan 1, 9:05 AM")
    }

    @Test func formatsDeterministicPMTime() {
        // Jan 1, 1970 15:30 UTC
        let date = Date(timeIntervalSince1970: 15 * 3600 + 30 * 60)
        #expect(name(for: date) == "Untitled \u{2014} Jan 1, 3:30 PM")
    }

    @Test func formatsNoonAs12PM() {
        // Jan 1, 1970 12:00 UTC
        let date = Date(timeIntervalSince1970: 12 * 3600)
        #expect(name(for: date) == "Untitled \u{2014} Jan 1, 12:00 PM")
    }

    @Test func formatsMidnightAs12AM() {
        // Jan 1, 1970 00:00 UTC
        let date = Date(timeIntervalSince1970: 0)
        #expect(name(for: date) == "Untitled \u{2014} Jan 1, 12:00 AM")
    }

    @Test func formatsMonthAndDayCorrectly() {
        // Apr 21, 2026 14:00 UTC
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 21
        comps.hour = 14
        comps.minute = 0
        comps.second = 0
        comps.timeZone = utc
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        #expect(name(for: date) == "Untitled \u{2014} Apr 21, 2:00 PM")
    }
}
