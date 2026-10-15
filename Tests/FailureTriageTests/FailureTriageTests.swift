import XCTest
@testable import FailureTriage

final class TriageTests: XCTestCase {
    func testCompleteInputsMeansGenuinelyHard() {
        let r = Triage.classify(AttemptEvidence(), at: .medium)
        XCTAssertEqual(r.primary, .genuinelyHard)
        XCTAssertEqual(r.remedy, .escalate(from: .medium, to: .high))
        XCTAssertTrue(r.mayEscalate)
    }

    func testHardAtMaxHandsToHumanInsteadOfOverflowing() {
        let r = Triage.classify(AttemptEvidence(), at: .max)
        XCTAssertEqual(r.remedy, .handToHuman)
        XCTAssertNil(Effort.max.next)
    }

    func testPermissionIsTriagedBeforeContext() {
        let e = AttemptEvidence(permissionDenials: ["Read(logs/**)"],
                                missingReferences: [MissingReference("a.swift", discoverable: true)])
        let r = Triage.classify(e, at: .medium)
        XCTAssertEqual(r.primary, .missingPermission)
        XCTAssertEqual(r.all, [.missingPermission, .missingContext])
        XCTAssertEqual(r.remedy, .grant(["Read(logs/**)"]))
        XCTAssertFalse(r.mayEscalate)
    }

    func testOracleIsTriagedBeforeContextAndSpec() {
        let e = AttemptEvidence(hasAcceptanceCheck: false,
                                missingReferences: [MissingReference("x", discoverable: false)],
                                openQuestions: ["Which edge?"])
        let r = Triage.classify(e, at: .high)
        XCTAssertEqual(r.primary, .missingOracle)
        XCTAssertEqual(r.all, [.missingOracle, .missingContext, .ambiguousSpec])
        XCTAssertEqual(r.remedy, .addAcceptanceCheck)
    }

    func testNoInputProblemEverEscalates() {
        for bucket in FailureBucket.allCases where bucket.isInputProblem {
            var e = AttemptEvidence()
            switch bucket {
            case .missingPermission: e.permissionDenials = ["Bash(psql:*)"]
            case .missingOracle: e.hasAcceptanceCheck = false
            case .missingContext: e.missingReferences = [MissingReference("schema", discoverable: false)]
            case .ambiguousSpec: e.openQuestions = ["Newest or highest paid?"]
            case .genuinelyHard: break
            }
            let r = Triage.classify(e, at: .medium)
            XCTAssertEqual(r.primary, bucket)
            XCTAssertFalse(r.mayEscalate, "\(bucket) must be fixed by changing the input")
            if case .escalate = r.remedy { XCTFail("\(bucket) escalated") }
        }
    }

    func testEffortOrderingAndCosts() {
        XCTAssertEqual(Effort.allCases.map(\.relativeCost), [0.5, 1.0, 2.0, 3.5, 6.0])
        XCTAssertEqual(Effort.medium.next, .high)
        XCTAssertTrue(Effort.low < Effort.max)
    }
}

final class SimulationTests: XCTestCase {
    let sim = Simulator()
    var tasks: [AgentTask] { SampleScenario.tasks }

    func task(_ id: String) throws -> AgentTask {
        try XCTUnwrap(tasks.first { $0.id == id })
    }

    func testScenarioShape() {
        XCTAssertEqual(tasks.count, 12)
        XCTAssertEqual(Set(tasks.map(\.id)).count, 12)
        XCTAssertEqual(tasks.filter { !$0.gaps.isEmpty }.count, 10, "ten of twelve are missing an input")
        XCTAssertEqual(tasks.filter { $0.gaps.isEmpty }.count, 2, "two are genuinely hard")
        XCTAssertEqual(Set(tasks.map(\.language)), Set(Language.allCases))
    }

    func testDialFixesOnlyTheDiscoverableInputOnItsOwn() {
        let report = sim.report(tasks, policy: .turnTheDial)
        // Tasks the dial got accepted without anyone ever triaging them.
        let fixedByDial = report.runs.filter { run in
            run.accepted && run.attempts.allSatisfy { $0.triage == nil }
        }.map(\.task.id)
        XCTAssertEqual(fixedByDial, ["T03", "T06", "T11"])
        // Only one of those had a missing input: the file the agent could read itself.
        let inputFixesByDial = fixedByDial.filter { id in tasks.first { $0.id == id }?.gaps.isEmpty == false }
        XCTAssertEqual(inputFixesByDial, ["T06"])
    }

    func testDeniedPermissionHidesDiscoverableContextFromTheDial() throws {
        let run = sim.run(try task("T02"), policy: .turnTheDial)
        XCTAssertEqual(run.attempts.map(\.effort), [.medium, .high, .xhigh, .max, .max])
        XCTAssertEqual(run.attempts.dropLast().last?.triage?.primary, .missingPermission)
        XCTAssertTrue(run.accepted)
    }

    func testTriageNeverLeavesMediumForInputProblems() {
        let report = sim.report(tasks, policy: .triage)
        for run in report.runs where !run.task.gaps.isEmpty {
            XCTAssertTrue(run.attempts.allSatisfy { $0.effort == .medium }, run.task.id)
        }
    }

    func testHardTasksCostTheSameUnderBothPolicies() throws {
        for id in ["T03", "T11"] {
            let t = try task(id)
            XCTAssertEqual(sim.run(t, policy: .turnTheDial).spend, sim.run(t, policy: .triage).spend, id)
        }
        XCTAssertEqual(sim.run(try task("T11"), policy: .triage).attempts.map(\.effort), [.medium, .high, .xhigh])
    }

    func testHeadlineNumbers() throws {
        let dial = sim.report(tasks, policy: .turnTheDial)
        let triage = sim.report(tasks, policy: .triage)

        XCTAssertEqual(dial.accepted, 12)
        XCTAssertEqual(triage.accepted, 12)
        XCTAssertEqual(dial.attempts, 53)
        XCTAssertEqual(triage.attempts, 27)
        XCTAssertEqual(dial.spend, 231.0, accuracy: 0.0001)
        XCTAssertEqual(triage.spend, 52.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(dial.costPerAcceptedTask), 19.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(triage.costPerAcceptedTask), 4.375, accuracy: 0.0001)
    }

    func testDiscoverableContextIsTheDialsOnlyHonestWin() throws {
        let t = try task("T06")
        XCTAssertEqual(sim.run(t, policy: .turnTheDial).spend, 4.0, accuracy: 0.0001)
        XCTAssertEqual(sim.run(t, policy: .triage).spend, 3.5, accuracy: 0.0001)
    }

    func testCostPerAcceptedIsNilWhenNothingIsAccepted() {
        let impossible = AgentTask(id: "X", language: .swift, title: "x", gaps: [], hardFloor: .max)
        let capped = Simulator(maxAttempts: 2)
        let report = capped.report([impossible], policy: .triage)
        XCTAssertEqual(report.accepted, 0)
        XCTAssertNil(report.costPerAcceptedTask)
        XCTAssertEqual(report.attempts, 2)
    }

    func testMaxAttemptsIsClampedToAtLeastOne() {
        XCTAssertEqual(Simulator(maxAttempts: 0).maxAttempts, 1)
    }
}
