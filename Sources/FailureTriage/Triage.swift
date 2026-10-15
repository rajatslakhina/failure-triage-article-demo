/// The five reasons an agent attempt fails. Only the last one is about the model.
public enum FailureBucket: Int, CaseIterable, Comparable, Sendable, CustomStringConvertible {
    case missingPermission = 0
    case missingOracle
    case missingContext
    case ambiguousSpec
    case genuinelyHard

    /// `true` for the four buckets you fix by changing the input.
    public var isInputProblem: Bool { self != .genuinelyHard }

    public var description: String {
        switch self {
        case .missingPermission: return "Missing permission"
        case .missingOracle: return "Missing oracle"
        case .missingContext: return "Missing context"
        case .ambiguousSpec: return "Ambiguous spec"
        case .genuinelyHard: return "Genuinely hard"
        }
    }

    public static func < (lhs: FailureBucket, rhs: FailureBucket) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What to change before the next attempt.
public enum Remedy: Equatable, Sendable {
    case grant([String])
    case addAcceptanceCheck
    case attach([MissingReference])
    case clarify([String])
    case escalate(from: Effort, to: Effort)
    /// Hard, and already at `.max`. A person takes it from here.
    case handToHuman

    public var summary: String {
        switch self {
        case .grant(let scopes): return "Grant " + scopes.joined(separator: ", ")
        case .addAcceptanceCheck: return "Write the failing test first"
        case .attach(let refs): return "Attach " + refs.map(\.name).joined(separator: ", ")
        case .clarify(let questions): return "Answer: " + questions.joined(separator: " / ")
        case .escalate(let from, let to): return "Raise effort \(from) → \(to)"
        case .handToHuman: return "Hand to a human"
        }
    }
}

public struct TriageResult: Equatable, Sendable {
    /// The bucket to fix first.
    public let primary: FailureBucket
    /// Every bucket the evidence points at, in fix order.
    public let all: [FailureBucket]
    public let remedy: Remedy

    /// Effort is only ever the answer when every input is already present.
    public var mayEscalate: Bool { primary == .genuinelyHard }
}

/// Sorts a failed attempt into a bucket, in a fixed order.
///
/// The order is the load-bearing decision. Permission goes first: a denied
/// read hides whatever context the agent could have found. The oracle goes
/// second, because without a check you can't tell a wrong answer from a
/// right one. "Genuinely hard" is what's left when all four inputs are there.
public enum Triage {
    public static func classify(_ evidence: AttemptEvidence, at effort: Effort) -> TriageResult {
        var buckets: [FailureBucket] = []
        if !evidence.permissionDenials.isEmpty { buckets.append(.missingPermission) }
        if !evidence.hasAcceptanceCheck { buckets.append(.missingOracle) }
        if !evidence.missingReferences.isEmpty { buckets.append(.missingContext) }
        if !evidence.openQuestions.isEmpty { buckets.append(.ambiguousSpec) }
        if buckets.isEmpty { buckets.append(.genuinelyHard) }

        // `buckets` is never empty here, but don't force-unwrap.
        let primary = buckets.first ?? .genuinelyHard
        return TriageResult(primary: primary, all: buckets, remedy: remedy(for: primary, evidence, effort))
    }

    static func remedy(for bucket: FailureBucket, _ evidence: AttemptEvidence, _ effort: Effort) -> Remedy {
        switch bucket {
        case .missingPermission: return .grant(evidence.permissionDenials)
        case .missingOracle: return .addAcceptanceCheck
        case .missingContext: return .attach(evidence.missingReferences)
        case .ambiguousSpec: return .clarify(evidence.openQuestions)
        case .genuinelyHard:
            guard let next = effort.next else { return .handToHuman }
            return .escalate(from: effort, to: next)
        }
    }
}
