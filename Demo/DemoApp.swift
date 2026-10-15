import SwiftUI
import FailureTriage

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(initialTab: LaunchArgs.tab)
        }
    }
}

enum LaunchArgs {
    /// `-tab cases|compare|checklist`, used by CI to screenshot each screen.
    static var tab: String {
        UserDefaults.standard.string(forKey: "tab") ?? "cases"
    }
}

struct RootView: View {
    @State private var tab: String

    init(initialTab: String) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { CasesView() }
                .tabItem { Label("Triage", systemImage: "stethoscope") }
                .tag("cases")
            NavigationStack { CompareView() }
                .tabItem { Label("Dial vs triage", systemImage: "dial.medium") }
                .tag("compare")
            NavigationStack { ChecklistView() }
                .tabItem { Label("Checklist", systemImage: "checklist") }
                .tag("checklist")
        }
    }
}

// MARK: - Shared

let simulator = Simulator()
let dialReport = simulator.report(SampleScenario.tasks, policy: .turnTheDial)
let triageReport = simulator.report(SampleScenario.tasks, policy: .triage)

func bucketColor(_ bucket: FailureBucket) -> Color {
    switch bucket {
    case .missingPermission: return .orange
    case .missingOracle: return .purple
    case .missingContext: return .blue
    case .ambiguousSpec: return .teal
    case .genuinelyHard: return .red
    }
}

func units(_ value: Double) -> String {
    String(format: "%.1f", value)
}

// MARK: - Cases

struct CasesView: View {
    var body: some View {
        List {
            Section {
                Text("Twelve failed agent tasks. Each is triaged from its evidence before anyone touches the effort dial.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(triageReport.runs, id: \.task.id) { run in
                CaseRow(run: run)
            }
        }
        .navigationTitle("Failure triage")
    }
}

struct CaseRow: View {
    let run: TaskRun

    var firstTriage: TriageResult? {
        run.attempts.first { $0.triage != nil }?.triage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.task.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(run.task.language.rawValue).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15), in: Capsule())
                Spacer()
                if let triage = firstTriage {
                    Text(triage.primary.description)
                        .font(.caption.bold())
                        .foregroundStyle(bucketColor(triage.primary))
                }
            }
            Text(run.task.title).font(.subheadline.weight(.semibold))
            if let triage = firstTriage {
                Text(triage.remedy.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(run.attempts.map { "\($0.effort)\($0.succeeded ? " ✓" : " ✗")" }.joined(separator: "  →  "))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Compare

struct CompareView: View {
    var maxSpend: Double {
        max(dialReport.runs.map(\.spend).max() ?? 1, 1)
    }

    var body: some View {
        List {
            Section("Totals (medium-attempt units)") {
                TotalsRow(report: dialReport, tint: .red)
                TotalsRow(report: triageReport, tint: .green)
            }
            Section("Spend per task: dial (top) vs triage (bottom)") {
                ForEach(0..<min(dialReport.runs.count, triageReport.runs.count), id: \.self) { i in
                    let dial = dialReport.runs[i]
                    let triage = triageReport.runs[i]
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(dial.task.id)  \(dial.task.title)")
                            .font(.caption)
                            .lineLimit(1)
                        SpendBar(value: dial.spend, maxValue: maxSpend, tint: .red)
                        SpendBar(value: triage.spend, maxValue: maxSpend, tint: .green)
                    }
                }
            }
        }
        .navigationTitle("Dial vs triage")
    }
}

struct TotalsRow: View {
    let report: PolicyReport
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.policy.rawValue).font(.headline).foregroundStyle(tint)
            HStack {
                Stat(label: "accepted", value: "\(report.accepted)/\(report.runs.count)")
                Stat(label: "attempts", value: "\(report.attempts)")
                Stat(label: "spend", value: units(report.spend))
                Stat(label: "per accepted", value: report.costPerAcceptedTask.map(units) ?? "–")
            }
        }
    }
}

struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.title3.monospacedDigit().bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpendBar: View {
    let value: Double
    let maxValue: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint.opacity(0.8))
                    .frame(width: max(4, (geo.size.width - 44) * value / maxValue))
                Text(units(value)).font(.caption2.monospacedDigit())
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Checklist

struct ChecklistView: View {
    let steps: [(FailureBucket, String, String)] = [
        (.missingPermission, "Did the harness deny anything?", "Grant the narrowest scope, retry at the same effort."),
        (.missingOracle, "Is \"done\" undefined, with no test or check?", "Write the failing test first, then retry."),
        (.missingContext, "Did it guess at a file, schema or log?", "Attach it. Don't make the model hunt."),
        (.ambiguousSpec, "Were there two valid readings?", "Answer the question in the task, not in review."),
        (.genuinelyHard, "All four inputs present and it still failed?", "Only now: raise effort one notch."),
    ]

    var body: some View {
        List {
            Section {
                Text("Run these in order. The first yes is the fix.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 28, height: 28)
                        .background(bucketColor(step.0).opacity(0.2), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.0.description).font(.caption.bold()).foregroundStyle(bucketColor(step.0))
                        Text(step.1).font(.subheadline.weight(.semibold))
                        Text(step.2).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Triage checklist")
    }
}
