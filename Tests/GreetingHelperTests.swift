import Testing

@Suite("GreetingHelper")
struct GreetingHelperTests {

    @Test("Morning greeting at hour 8")
    func morningGreeting() {
        #expect(GreetingHelper.greeting(hour: 8, name: "Volker") == "Guten Morgen, Volker")
    }

    @Test("Early morning greeting contains Frühaufsteher")
    func earlyMorning() {
        #expect(GreetingHelper.greeting(hour: 6, name: "Test").contains("Frühaufsteher"))
    }

    @Test("Lunch greeting at hour 12")
    func lunchGreeting() {
        #expect(GreetingHelper.greeting(hour: 12, name: "Volker") == "Mahlzeit, Volker")
    }

    @Test("Afternoon greeting at hour 15")
    func afternoonGreeting() {
        #expect(GreetingHelper.greeting(hour: 15, name: "Volker") == "Hallo, Volker")
    }

    @Test("Evening greeting at hour 19")
    func eveningGreeting() {
        #expect(GreetingHelper.greeting(hour: 19, name: "Volker") == "Guten Abend, Volker")
    }

    @Test("Late night greeting contains Nachtschicht")
    func lateNightGreeting() {
        #expect(GreetingHelper.greeting(hour: 23, name: "Test").contains("Nachtschicht"))
    }

    @Test("Midnight greeting contains Nachtschicht")
    func midnightGreeting() {
        #expect(GreetingHelper.greeting(hour: 0, name: "Test").contains("Nachtschicht"))
    }

    @Test("Hour 11 is lunch time")
    func boundary11() {
        #expect(GreetingHelper.greeting(hour: 11, name: "X").contains("Mahlzeit"))
    }

    @Test("Hour 14 is afternoon")
    func boundary14() {
        #expect(GreetingHelper.greeting(hour: 14, name: "X").contains("Hallo"))
    }

    @Test("Hour 18 is evening")
    func boundary18() {
        #expect(GreetingHelper.greeting(hour: 18, name: "X").contains("Guten Abend"))
    }

    @Test("currentGreeting includes name when provided")
    func currentGreetingWithName() {
        #expect(GreetingHelper.currentGreeting(name: "Volker").contains("Volker"))
    }

    @Test("currentGreeting uses Moco when no name")
    func currentGreetingWithoutName() {
        #expect(GreetingHelper.currentGreeting(name: nil).contains("Moco"))
    }

    @Test("Friday afternoon shows special greeting")
    func fridayAfternoon() {
        #expect(GreetingHelper.greeting(hour: 16, weekday: 6, name: "Volker") == "Schönen Freitag, Volker")
    }

    @Test("Friday morning shows normal greeting")
    func fridayMorningIsNormal() {
        #expect(GreetingHelper.greeting(hour: 9, weekday: 6, name: "Volker") == "Guten Morgen, Volker")
    }
}
