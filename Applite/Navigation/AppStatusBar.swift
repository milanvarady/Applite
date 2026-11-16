import SwiftUI

struct AppStatusBar: View {
    @Environment(CaskManager.self) private var caskManager

    var body: some View {
        let summary = AppStatusSummary(
            isRefreshingCatalog: caskManager.isRefreshingCatalog,
            isResolvingInstalledState: caskManager.isResolvingInstalledState,
            isRefreshingOutdated: caskManager.isRefreshingOutdated,
            outdatedRefreshFailed: caskManager.outdatedRefreshFailed,
            operations: caskManager.activeTasks.map { ($0.viewModel.name, $0.viewModel.progressState) }
        )

        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                currentStatus(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    caskManager.requestedTab = .activeTasks
                } label: {
                    Label {
                        if summary.failedTaskCount > 0 {
                            Text("Tasks: \(summary.activeTaskCount) active, \(summary.failedTaskCount) failed")
                        } else {
                            Text("Tasks (\(summary.activeTaskCount))")
                        }
                    } icon: {
                        Image(systemName: summary.failedTaskCount > 0 ? "exclamationmark.triangle" : "list.bullet")
                    }
                }
                .disabled(summary.taskCount == 0 || caskManager.bootstrap.needsSetupOverlay)
                .help("View running, queued, and failed tasks")

                Divider()
                    .frame(height: 14)

                Button {
                    Task { await caskManager.loadData(forceSync: true) }
                } label: {
                    Label("Refresh App Catalog", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .disabled(
                    summary.blocksCatalogRefresh ||
                    !caskManager.bootstrap.isBrewReady ||
                    caskManager.bootstrap.needsSetupOverlay
                )
                .help("Refresh App Catalog")
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func currentStatus(_ summary: AppStatusSummary) -> some View {
        switch caskManager.bootstrap.phase {
        case .checking:
            statusLabel(Text("Starting Applite..."), busy: true)
        case .installing:
            statusLabel(Text("Setting up Homebrew..."), busy: true)
        case .installed:
            statusLabel(Text("Homebrew setup complete"))
        case .failed, .brewMissing:
            statusLabel(Text("Homebrew needs attention"), warning: true)
        case .ready:
            if let batch = caskManager.batchProgress, !caskManager.isRefreshingCatalog {
                if batch.isUpdate {
                    statusLabel(Text("Updating \(batch.completed) of \(batch.total)…", comment: "Bulk update progress header"), busy: true)
                } else {
                    statusLabel(Text("Installing \(batch.completed) of \(batch.total)…", comment: "Bulk install progress header"), busy: true)
                }
            } else {
                activityStatus(summary.activity)
            }
        }
    }

    @ViewBuilder
    private func activityStatus(_ activity: AppStatusSummary.Activity) -> some View {
        let busy = activity.isBusy
        switch activity {
        case .refreshingCatalog:
            statusLabel(Text("Refreshing app catalog..."), busy: busy)
        case .checkingApps:
            statusLabel(Text("Checking installed apps and updates..."), busy: busy)
        case .checkingUpdates:
            statusLabel(Text("Checking app updates..."), busy: busy)
        case .working(let name, let detail):
            if detail.isEmpty {
                statusLabel(Text("Working on \(name)..."), busy: busy)
            } else {
                statusLabel(Text("\(detail): \(name)"), busy: busy)
            }
        case .downloading(let name, let fraction):
            statusLabel(Text("Downloading \(name): \(fraction, format: .percent.precision(.fractionLength(0)))"), busy: busy)
        case .failedTasks(let count):
            statusLabel(Text("Failed tasks: \(count)"), warning: true)
        case .updateCheckFailed:
            statusLabel(Text("Couldn't check app updates"), warning: true)
        case .ready:
            statusLabel(Text("Ready"))
        }
    }

    private func statusLabel(_ text: Text, busy: Bool = false, warning: Bool = false) -> some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            } else if warning {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            text
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
        .help(text)
        .accessibilityElement(children: .combine)
    }
}
