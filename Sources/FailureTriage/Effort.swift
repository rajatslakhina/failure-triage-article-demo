/// The effort levels a coding agent (or a sub-agent) can be run at.
///
/// `relativeCost` is a modelling assumption, not a price list: it is the
/// spend of one attempt relative to an attempt at `.medium`. Higher effort
/// means more thinking and more tool calls, so it costs more per attempt.
public enum Effort: Int, CaseIterable, Comparable, Sendable, CustomStringConvertible {
    case low = 0
    case medium
    case high
    case xhigh
    case max

    public var relativeCost: Double {
        switch self {
        case .low: return 0.5
        case .medium: return 1.0
        case .high: return 2.0
        case .xhigh: return 3.5
        case .max: return 6.0
        }
    }

    /// The next level up, or `nil` when already at `.max`.
    public var next: Effort? {
        Effort(rawValue: rawValue + 1)
    }

    public var description: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        case .xhigh: return "xhigh"
        case .max: return "max"
        }
    }

    public static func < (lhs: Effort, rhs: Effort) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
