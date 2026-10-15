/// Twelve constructed agent tasks across Swift, TypeScript and SQL.
///
/// The mix is a modelling choice, not a measurement: two or three of each
/// kind of failure, two that are genuinely hard, and two with more than one
/// thing missing. Change it and every number in the demo moves with it.
public enum SampleScenario {
    public static let tasks: [AgentTask] = [
        AgentTask(id: "T01", language: .swift, title: "Paginate the order history list",
                  gaps: [.context(MissingReference("orders API page schema", discoverable: false))]),
        AgentTask(id: "T02", language: .swift, title: "Fix the flaky checkout snapshot test",
                  gaps: [.permission("Read(Tests/__Snapshots__/**)"),
                         .context(MissingReference("SnapshotConfig.swift", discoverable: true))]),
        AgentTask(id: "T03", language: .swift, title: "Move ImageCache to Swift 6 strict concurrency",
                  gaps: [], hardFloor: .high),
        AgentTask(id: "T04", language: .swift, title: "Add retry to the token refresh",
                  gaps: [.oracle]),
        AgentTask(id: "T05", language: .typescript, title: "Debounce the search client",
                  gaps: [.spec("Leading or trailing edge?")]),
        AgentTask(id: "T06", language: .typescript, title: "Fix the off-by-one date on web receipts",
                  gaps: [.context(MissingReference("formatDate.ts", discoverable: true))]),
        AgentTask(id: "T07", language: .typescript, title: "Port the pricing rules to the edge worker",
                  gaps: [.oracle]),
        AgentTask(id: "T08", language: .typescript, title: "Find why the push-token webhook returns 500",
                  gaps: [.permission("Read(logs/webhook-*.log)")]),
        AgentTask(id: "T09", language: .sql, title: "Speed up the daily cohort query",
                  gaps: [.context(MissingReference("EXPLAIN ANALYZE output", discoverable: false))]),
        AgentTask(id: "T10", language: .sql, title: "Dedupe the subscriptions table",
                  gaps: [.spec("Which row wins: newest, or highest paid?")]),
        AgentTask(id: "T11", language: .sql, title: "Make the revenue rollup incremental",
                  gaps: [], hardFloor: .xhigh),
        AgentTask(id: "T12", language: .swift, title: "Make the offline queue survive an app kill",
                  gaps: [.oracle,
                         .context(MissingReference("TestFlight crash log", discoverable: false))]),
    ]
}
