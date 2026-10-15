/// One thing standing between an agent and an accepted result.
public enum Gap: Hashable, Sendable {
    case permission(String)
    case oracle
    case context(MissingReference)
    case spec(String)

    var bucket: FailureBucket {
        switch self {
        case .permission: return .missingPermission
        case .oracle: return .missingOracle
        case .context: return .missingContext
        case .spec: return .ambiguousSpec
        }
    }
}

public enum Language: String, Sendable, CaseIterable {
    case swift = "Swift"
    case typescript = "TypeScript"
    case sql = "SQL"
}

/// A constructed agent task with known ground truth.
public struct AgentTask: Identifiable, Sendable {
    public let id: String
    public let language: Language
    public let title: String
    /// What is missing from the task as first handed to the agent.
    public let gaps: [Gap]
    /// The lowest effort that succeeds once every input is present.
    public let hardFloor: Effort

    public init(id: String, language: Language, title: String, gaps: [Gap], hardFloor: Effort = .medium) {
        self.id = id
        self.language = language
        self.title = title
        self.gaps = gaps
        self.hardFloor = hardFloor
    }
}

/// The rules of the model, written down so every number can be checked.
public struct CostModel: Sendable {
    /// A reviewer reading and rejecting one failed attempt, in medium-attempt units.
    public var reviewCostPerRejection: Double = 1.0
    /// A lead fixing one input (granting, writing the test, attaching, answering).
    public var inputFixCost: Double = 0.5
    /// Effort at which the agent goes looking for context on its own.
    public var discoveryEffort: Effort = .high

    public init() {}
}

public enum Policy: String, Sendable, CaseIterable {
    /// On failure, turn the dial up one notch. Only once `.max` has failed
    /// does anyone look at the input, and nobody turns the dial back down.
    case turnTheDial = "Turn the dial"
    /// On failure, triage, fix the input, retry at the same effort.
    case triage = "Triage first"
}

public struct Attempt: Equatable, Sendable {
    public let effort: Effort
    public let succeeded: Bool
    /// `nil` when nobody looked at why the attempt failed.
    public let triage: TriageResult?
}

public struct TaskRun: Sendable {
    public let task: AgentTask
    public let attempts: [Attempt]
    public let accepted: Bool
    public let spend: Double
}

public struct PolicyReport: Sendable {
    public let policy: Policy
    public let runs: [TaskRun]

    public var accepted: Int { runs.filter(\.accepted).count }
    public var attempts: Int { runs.reduce(0) { $0 + $1.attempts.count } }
    public var spend: Double { runs.reduce(0) { $0 + $1.spend } }
    /// Spend across every attempt, accepted or not, divided by accepted tasks.
    public var costPerAcceptedTask: Double? {
        accepted == 0 ? nil : spend / Double(accepted)
    }
}

public struct Simulator: Sendable {
    public var cost: CostModel
    public var maxAttempts: Int

    public init(cost: CostModel = CostModel(), maxAttempts: Int = 8) {
        self.cost = cost
        self.maxAttempts = max(1, maxAttempts)
    }

    /// Gaps that remain after an attempt at `effort`. A discoverable reference is
    /// found at `discoveryEffort` or above, unless a denied permission hides it.
    func remaining(_ gaps: [Gap], at effort: Effort) -> [Gap] {
        let blocked = gaps.contains { if case .permission = $0 { return true } else { return false } }
        guard effort >= cost.discoveryEffort, !blocked else { return gaps }
        return gaps.filter { gap in
            if case .context(let ref) = gap, ref.discoverable { return false }
            return true
        }
    }

    static func evidence(from gaps: [Gap]) -> AttemptEvidence {
        var e = AttemptEvidence()
        for gap in gaps {
            switch gap {
            case .permission(let scope): e.permissionDenials.append(scope)
            case .oracle: e.hasAcceptanceCheck = false
            case .context(let ref): e.missingReferences.append(ref)
            case .spec(let q): e.openQuestions.append(q)
            }
        }
        return e
    }

    public func run(_ task: AgentTask, policy: Policy) -> TaskRun {
        var gaps = task.gaps
        var effort = Effort.medium
        var attempts: [Attempt] = []
        var spend = 0.0

        while attempts.count < maxAttempts {
            spend += effort.relativeCost
            let left = remaining(gaps, at: effort)
            if left.isEmpty && effort >= task.hardFloor {
                attempts.append(Attempt(effort: effort, succeeded: true, triage: nil))
                return TaskRun(task: task, attempts: attempts, accepted: true, spend: spend)
            }
            spend += cost.reviewCostPerRejection

            switch policy {
            case .turnTheDial:
                if let next = effort.next {
                    attempts.append(Attempt(effort: effort, succeeded: false, triage: nil))
                    effort = next
                    continue
                }
                // At `.max` with nothing left to turn: someone finally triages.
                let result = Triage.classify(Self.evidence(from: left), at: effort)
                attempts.append(Attempt(effort: effort, succeeded: false, triage: result))
                guard result.primary.isInputProblem else {
                    return TaskRun(task: task, attempts: attempts, accepted: false, spend: spend)
                }
                spend += cost.inputFixCost
                gaps.removeAll { $0.bucket == result.primary }

            case .triage:
                let result = Triage.classify(Self.evidence(from: left), at: effort)
                attempts.append(Attempt(effort: effort, succeeded: false, triage: result))
                switch result.remedy {
                case .escalate(_, let to):
                    effort = to
                case .handToHuman:
                    return TaskRun(task: task, attempts: attempts, accepted: false, spend: spend)
                default:
                    spend += cost.inputFixCost
                    gaps.removeAll { $0.bucket == result.primary }
                }
            }
        }
        return TaskRun(task: task, attempts: attempts, accepted: false, spend: spend)
    }

    public func report(_ tasks: [AgentTask], policy: Policy) -> PolicyReport {
        PolicyReport(policy: policy, runs: tasks.map { run($0, policy: policy) })
    }
}
