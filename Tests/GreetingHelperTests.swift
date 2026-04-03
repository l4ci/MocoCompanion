import XCTest

final class GreetingHelperTests: XCTestCase {

    func testMorningGreeting() {
        let result = GreetingHelper.greeting(hour: 8, name: "Volker")
        XCTAssertEqual(result, "Guten Morgen, Volker")
    }

    func testEarlyMorning() {
        let result = GreetingHelper.greeting(hour: 6, name: "Test")
        XCTAssertTrue(result.contains("Frühaufsteher"))
    }

    func testLunchGreeting() {
        let result = GreetingHelper.greeting(hour: 12, name: "Volker")
        XCTAssertEqual(result, "Mahlzeit, Volker")
    }

    func testAfternoonGreeting() {
        let result = GreetingHelper.greeting(hour: 15, name: "Volker")
        XCTAssertEqual(result, "Hallo, Volker")
    }

    func testEveningGreeting() {
        let result = GreetingHelper.greeting(hour: 19, name: "Volker")
        XCTAssertEqual(result, "Guten Abend, Volker")
    }

    func testLateNightGreeting() {
        let result = GreetingHelper.greeting(hour: 23, name: "Test")
        XCTAssertTrue(result.contains("Nachtschicht"))
    }

    func testMidnightGreeting() {
        let result = GreetingHelper.greeting(hour: 0, name: "Test")
        XCTAssertTrue(result.contains("Nachtschicht"))
    }

    func testBoundary11() {
        // 11 is lunch time
        XCTAssertTrue(GreetingHelper.greeting(hour: 11, name: "X").contains("Mahlzeit"))
    }

    func testBoundary14() {
        // 14 is afternoon
        XCTAssertTrue(GreetingHelper.greeting(hour: 14, name: "X").contains("Hallo"))
    }

    func testBoundary18() {
        // 18 is evening
        XCTAssertTrue(GreetingHelper.greeting(hour: 18, name: "X").contains("Guten Abend"))
    }

    func testCurrentGreetingWithName() {
        let result = GreetingHelper.currentGreeting(name: "Volker")
        XCTAssertTrue(result.contains("Volker"))
    }

    func testCurrentGreetingWithoutName() {
        let result = GreetingHelper.currentGreeting(name: nil)
        XCTAssertTrue(result.contains("Moco"))
    }

    func testFridayAfternoon() {
        // weekday 6 = Friday
        let result = GreetingHelper.greeting(hour: 16, weekday: 6, name: "Volker")
        XCTAssertEqual(result, "Schönen Freitag, Volker")
    }

    func testFridayMorningIsNormal() {
        let result = GreetingHelper.greeting(hour: 9, weekday: 6, name: "Volker")
        XCTAssertEqual(result, "Guten Morgen, Volker")
    }
}
