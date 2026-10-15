/// Something the agent needed and did not have: a file, a type, a log, a schema.
public struct MissingReference: Hashable, Sendable {
    public let name: String
    /// `true` when the agent could have fetched it itself: it is in the
    /// workspace and the agent is allowed to read it. More effort can find a
    /// discoverable reference. It can never find one that isn't there.
    public let discoverable: Bool

    public init(_ name: String, discoverable: Bool) {
        self.name = name
        self.discoverable = discoverable
    }
}

/// What a lead can actually observe after an agent attempt failed review.
///
/// Every field is read from the attempt itself: the transcript, the tool log,
/// the task description. None of it needs a guess about what the model "meant".
public struct AttemptEvidence: Equatable, Sendable {
    /// Tool calls the harness denied, e.g. `Read(Tests/Fixtures/**)`.
    public var permissionDenials: [String]
    /// Whether a test, a check or a fixture defines "done" for this task.
    public var hasAcceptanceCheck: Bool
    /// Inputs the agent referenced, guessed at or asked for.
    public var missingReferences: [MissingReference]
    /// Points where the task allowed more than one valid reading.
    public var openQuestions: [String]

    public init(
        permissionDenials: [String] = [],
        hasAcceptanceCheck: Bool = true,
        missingReferences: [MissingReference] = [],
        openQuestions: [String] = []
    ) {
        self.permissionDenials = permissionDenials
        self.hasAcceptanceCheck = hasAcceptanceCheck
        self.missingReferences = missingReferences
        self.openQuestions = openQuestions
    }

    /// `true` when nothing on the input side is missing.
    public var inputsComplete: Bool {
        permissionDenials.isEmpty
            && hasAcceptanceCheck
            && missingReferences.isEmpty
            && openQuestions.isEmpty
    }
}
