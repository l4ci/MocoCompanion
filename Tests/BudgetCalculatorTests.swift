import Testing

@Suite("BudgetCalculator")
struct BudgetCalculatorTests {

    // MARK: - Helpers

    private func makeProject(
        billingVariant: String = "project",
        hourlyRate: Double = 100,
        tasks: [MocoFullTask] = []
    ) -> MocoFullProject {
        MocoFullProject(
            id: 1, name: "Test Project", identifier: "TP",
            active: true, billable: true,
            billingVariant: billingVariant, budget: 10000,
            hourlyRate: hourlyRate, tasks: tasks
        )
    }

    private func makeTask(
        id: Int = 10,
        budget: Double? = 5000,
        hourlyRate: Double? = 80
    ) -> MocoFullTask {
        MocoFullTask(id: id, name: "Task", active: true, billable: true, budget: budget, hourlyRate: hourlyRate)
    }

    private func makeReport(
        progress: Int? = 45,
        hoursRemaining: Double? = 50,
        costsByTask: [MocoReportTaskCost]? = nil
    ) -> MocoProjectReport {
        MocoProjectReport(
            budgetTotal: 10000, budgetProgressInPercentage: progress,
            budgetRemaining: 5000, hoursTotal: 50, hoursBillable: 40,
            hoursRemaining: hoursRemaining, costsByTask: costsByTask ?? []
        )
    }

    private func makeContract(userId: Int = 1, hourlyRate: Double = 120) -> MocoProjectContract {
        MocoProjectContract(id: 1, userId: userId, firstname: "Test", lastname: "User", billable: true, active: true, budget: nil, hourlyRate: hourlyRate)
    }

    // MARK: - Project Level

    @Test("Project level: healthy when progress < 50%")
    func projectLevelHealthy() {
        let level = BudgetCalculator.projectLevel(report: makeReport(progress: 30))
        #expect(level == .healthy)
    }

    @Test("Project level: warning when progress 50-89%")
    func projectLevelWarning() {
        #expect(BudgetCalculator.projectLevel(report: makeReport(progress: 50)) == .warning)
        #expect(BudgetCalculator.projectLevel(report: makeReport(progress: 89)) == .warning)
    }

    @Test("Project level: critical when progress >= 90%")
    func projectLevelCritical() {
        #expect(BudgetCalculator.projectLevel(report: makeReport(progress: 90)) == .critical)
        #expect(BudgetCalculator.projectLevel(report: makeReport(progress: 150)) == .critical)
    }

    @Test("Project level: none when progress is nil")
    func projectLevelNone() {
        #expect(BudgetCalculator.projectLevel(report: makeReport(progress: nil)) == .none)
    }

    // MARK: - Rate Resolution

    @Test("Rate resolution: project billing variant uses project rate")
    func rateProject() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "project", projectRate: 100,
            task: makeTask(hourlyRate: 80), contracts: [], userId: nil
        )
        #expect(rate == 100)
    }

    @Test("Rate resolution: task billing variant uses task rate")
    func rateTask() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "task", projectRate: 100,
            task: makeTask(hourlyRate: 80), contracts: [], userId: nil
        )
        #expect(rate == 80)
    }

    @Test("Rate resolution: user billing variant uses contract rate")
    func rateUser() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "user", projectRate: 100,
            task: nil, contracts: [makeContract(userId: 5, hourlyRate: 120)], userId: 5
        )
        #expect(rate == 120)
    }

    @Test("Rate resolution: user billing without matching contract returns nil")
    func rateUserNoMatch() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "user", projectRate: 100,
            task: nil, contracts: [makeContract(userId: 5)], userId: 99
        )
        #expect(rate == nil)
    }

    @Test("Rate resolution: user billing without userId returns nil")
    func rateUserNoId() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "user", projectRate: 100,
            task: nil, contracts: [makeContract()], userId: nil
        )
        #expect(rate == nil)
    }

    @Test("Rate resolution: task billing with nil task rate returns nil")
    func rateTaskNilRate() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "task", projectRate: 100,
            task: makeTask(hourlyRate: nil), contracts: [], userId: nil
        )
        #expect(rate == nil)
    }

    @Test("Rate resolution: zero rate returns nil")
    func rateZero() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "project", projectRate: 0,
            task: nil, contracts: [], userId: nil
        )
        #expect(rate == nil)
    }

    @Test("Rate resolution: unknown billing variant falls back to project rate")
    func rateUnknown() {
        let rate = BudgetCalculator.resolveHourlyRate(
            billingVariant: "something_new", projectRate: 75,
            task: nil, contracts: [], userId: nil
        )
        #expect(rate == 75)
    }

    // MARK: - Task Level

    @Test("Task level: critical when < 1h remaining")
    func taskLevelCritical() {
        let task = makeTask(id: 10, budget: 5000, hourlyRate: 80)
        let costEntry = MocoReportTaskCost(id: 10, name: "Task", hoursTotal: 62, totalCosts: nil)
        let report = makeReport(costsByTask: [costEntry])
        let project = makeProject(billingVariant: "task", tasks: [task])

        let result = BudgetCalculator.taskLevel(
            taskId: 10, project: project, report: report, contracts: [], userId: nil
        )
        // budget 5000 / rate 80 = 62.5h total, consumed 62h → 0.5h remaining
        #expect(result.level == .critical)
        #expect(result.hoursRemaining != nil)
        #expect(result.hoursRemaining! < 1.0)
    }

    @Test("Task level: healthy when > 1h remaining")
    func taskLevelHealthy() {
        let task = makeTask(id: 10, budget: 5000, hourlyRate: 80)
        let costEntry = MocoReportTaskCost(id: 10, name: "Task", hoursTotal: 10, totalCosts: nil)
        let report = makeReport(costsByTask: [costEntry])
        let project = makeProject(billingVariant: "task", tasks: [task])

        let result = BudgetCalculator.taskLevel(
            taskId: 10, project: project, report: report, contracts: [], userId: nil
        )
        // budget 5000 / rate 80 = 62.5h total, consumed 10h → 52.5h remaining
        #expect(result.level == .healthy)
    }

    @Test("Task level: none when task has no budget")
    func taskLevelNoBudget() {
        let task = makeTask(id: 10, budget: nil)
        let project = makeProject(tasks: [task])

        let result = BudgetCalculator.taskLevel(
            taskId: 10, project: project, report: makeReport(), contracts: [], userId: nil
        )
        #expect(result.level == .none)
    }

    @Test("Task level: none when task not found")
    func taskLevelNotFound() {
        let project = makeProject(tasks: [makeTask(id: 99)])

        let result = BudgetCalculator.taskLevel(
            taskId: 10, project: project, report: makeReport(), contracts: [], userId: nil
        )
        #expect(result.level == .none)
    }

    @Test("Task level: none when rate can't be resolved")
    func taskLevelNoRate() {
        let task = makeTask(id: 10, budget: 5000, hourlyRate: nil)
        let project = makeProject(billingVariant: "task", tasks: [task])

        let result = BudgetCalculator.taskLevel(
            taskId: 10, project: project, report: makeReport(), contracts: [], userId: nil
        )
        #expect(result.level == .none)
    }

    // MARK: - Combined Status

    @Test("Combined status: task critical overrides project warning")
    func statusTaskOverridesProject() {
        let task = makeTask(id: 10, budget: 5000, hourlyRate: 80)
        let costEntry = MocoReportTaskCost(id: 10, name: "Task", hoursTotal: 62, totalCosts: nil)
        let report = makeReport(progress: 60, costsByTask: [costEntry])
        let project = makeProject(billingVariant: "task", tasks: [task])

        let status = BudgetCalculator.status(
            report: report, project: project, contracts: [], taskId: 10, userId: nil
        )
        #expect(status.projectLevel == .warning)
        #expect(status.taskLevel == .critical)
        #expect(status.effectiveBadge == .taskCritical)
    }

    @Test("Combined status: no task → only project level matters")
    func statusNoTask() {
        let status = BudgetCalculator.status(
            report: makeReport(progress: 95), project: makeProject(), contracts: [], taskId: nil, userId: nil
        )
        #expect(status.projectLevel == .critical)
        #expect(status.taskLevel == .none)
        #expect(status.effectiveBadge == .projectCritical)
    }

    @Test("Combined status: null costs_by_task handled gracefully")
    func statusNullCosts() {
        let task = makeTask(id: 10, budget: 5000, hourlyRate: 80)
        let report = MocoProjectReport(
            budgetTotal: nil, budgetProgressInPercentage: nil, budgetRemaining: nil,
            hoursTotal: nil, hoursBillable: nil, hoursRemaining: nil, costsByTask: nil
        )
        let project = makeProject(billingVariant: "task", tasks: [task])

        let result = BudgetCalculator.taskLevel(
            taskId: 10, project: project, report: report, contracts: [], userId: nil
        )
        // No consumed hours found → full budget remaining → healthy
        #expect(result.level == .healthy)
    }
}
