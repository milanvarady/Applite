//
//  AppView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI

/// App view role
enum AppRole {
    case installAndManage   // Used in the download section, or when searching
    case update             // Used in the update section
    case installed          // Used in the installed section
}

/// Shows an application's icon and provides controls for installing, updating, uninstalling and opening the app. Used all across the app.
struct AppView: View {
    /// A ``CaskViewModel`` object to display
    var cask: CaskViewModel
    /// Role of the app, e.g. install, updated or uninstall
    var role: AppRole

    @Environment(\.openWindow) var openWindow

    @Environment(CaskManager.self) var caskManager

    // Alerts
    @State var failureAlertMessage = ""
    @State var showingFailureAlert = false

    // Success animation
    @State var keepSuccessIndicator = false
    /// Clears `keepSuccessIndicator` a beat after a success ends, so a card that stays put
    /// (e.g. reinstall) never gets stuck on the badge. Cancelled if a new success starts.
    @State private var successResetTask: Task<Void, Never>? = nil

    /// Shown when the stop button is pressed on a cask that's part of a running bulk operation.
    @State var showingBatchStopInfo = false

    /// App view dimensions, and spacing
    public static let dimensions: (width: CGFloat, height: CGFloat, spacing: CGFloat) = (width: 320, height: 80, spacing: 20)

    var body: some View {
        HStack {
            IconAndDescriptionView(cask: cask)
            IconsAndWarnings(cask: cask)
            actionsView
        }
        .buttonStyle(.plain)
        .frame(width: Self.dimensions.width, height: Self.dimensions.height)
        .modify { view in
            // Right-click access to the same actions as the ellipsis menu
            if showsOptionsMenu {
                view.contextMenu { optionsMenuContent }
            } else {
                view
            }
        }
        .alertManager(caskManager.alert)
        .alert(
            "\(cask.name) is part of a bulk operation",
            isPresented: $showingBatchStopInfo
        ) {
            Button("See Active Tasks") {
                caskManager.requestedTab = .activeTasks
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To stop it, use the Stop button in Active Tasks — it cancels the whole bulk operation.", comment: "Batch stop redirect message")
        }
        .onChange(of: cask.progressState) { oldState, newState in
            manageSuccessIndicator(from: oldState, to: newState)
        }
    }

    /// Keeps the success badge on screen through the brief async gap between `progressState`
    /// hitting `.idle` and the row leaving its list (update/uninstall), then *always* clears the
    /// flag via `defer` so a card that stays put (reinstall) returns to its buttons instead of
    /// sticking on the checkmark. Discover cards persist and swap to Open on their own, so they
    /// don't need the flag at all.
    private func manageSuccessIndicator(from oldState: CaskProgressState, to newState: CaskProgressState) {
        guard role != .installAndManage else { return }

        if newState == .success {
            successResetTask?.cancel()
            successResetTask = nil
            keepSuccessIndicator = true
        } else if oldState == .success {
            successResetTask?.cancel()
            successResetTask = Task { @MainActor in
                defer { keepSuccessIndicator = false }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    /// The ellipsis and right-click menu are shown for installable/installed apps,
    /// but not in the update list.
    private var showsOptionsMenu: Bool {
        role != .update
    }

    /// "More options" menu shared by the ellipsis button and the card's
    /// right-click context menu. Items depend on whether the app is installed.
    @ViewBuilder
    private var optionsMenuContent: some View {
        if cask.isInstalled {
            getInfoButton

            Button {
                caskManager.reinstall(cask)
            } label: {
                Label("Reinstall", systemImage: "arrow.2.squarepath")
            }

            Divider()

            Button(role: .destructive) {
                caskManager.uninstall(cask)
            } label: {
                Label("Uninstall", systemImage: "trash")
            }

            Button(role: .destructive) {
                caskManager.uninstall(cask, zap: true)
            } label: {
                Label("Uninstall & delete app data", systemImage: "trash.fill")
            }
        } else {
            if let homepage = cask.homepage {
                Link(destination: homepage) {
                    Label("Homepage", systemImage: "house")
                }
            }

            getInfoButton
        }
    }

    private var getInfoButton: some View {
        Button {
            Task { await getInfo() }
        } label: {
            Label("Get Info", systemImage: "info")
        }
    }

    /// Ellipsis button that opens the "more options" menu (native dropdown).
    private var optionsMenuButton: some View {
        Menu {
            optionsMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .padding(.vertical)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More options")
    }

    private func getInfo() async {
        do {
            let info = try await caskManager.getAdditionalInfoForCask(cask)
            openWindow(value: info)
        } catch {
            caskManager.alert.show(error: error, title: "Failed to gather cask info")
        }
    }

    @ViewBuilder
    var actionsView: some View {
        Group {
            if showsSuccessIndicator {
                successCheckmark
                    // Grow in via the badge's own onAppear; shrink away on exit
                    // (role change → Open, or the card leaving its list).
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 0.3).combined(with: .opacity)
                    ))
            } else if self.cask.progressState == .idle {
                mainButtons
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                progressView
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: cask.progressState)
        .animation(.smooth(duration: 0.3), value: keepSuccessIndicator)
    }

    /// The success badge owns a single branch across the `.success` → `.idle` boundary so the
    /// drawn checkmark isn't re-mounted (and re-animated) when `progressState` settles.
    private var showsSuccessIndicator: Bool {
        cask.progressState == .success || keepSuccessIndicator
    }

    @ViewBuilder
    private var mainButtons: some View {
        switch role {
        case .installAndManage:
            if cask.isInstalled {
                OpenButton(cask: cask)
            } else {
                DownloadButton(cask: cask)
            }

            optionsMenuButton

        case .update:
            UpdateButton(cask: cask)

        case .installed:
            OpenButton(cask: cask)

            optionsMenuButton
        }
    }

    private var successCheckmark: some View {
        SuccessCheckmark()
    }

    @ViewBuilder
    private var progressView: some View {
        switch cask.progressState {
        case .busy(let task):
            ProgressView() {
                if !task.isEmpty {
                    Text(task)
                        .font(.system(size: 12))
                }
            }
            .scaleEffect(0.8)

        case .downloading(let percent):
            Button {
                // A batch is one brew process, so a per-card stop can't cancel just this cask —
                // redirect to Active Tasks (its header has a "Stop" for the whole bulk op) instead
                // of silently aborting all of them.
                if caskManager.batchProgress != nil {
                    showingBatchStopInfo = true
                } else {
                    caskManager.cancel(cask)
                }
            } label: {
                ZStack {
                    CircularProgressRing(progress: percent)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .help(caskManager.batchProgress != nil ? "Part of a bulk operation" : "Stop download")
            .accessibilityLabel("Stop download")

        case .success:
            // Handled upstream by `showsSuccessIndicator` in `actionsView`; unreachable here.
            EmptyView()

        case .failed(let output):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)

                Text("Error", comment: "Cask action failed (e.g. installation failed)")
                    .foregroundStyle(.red)

                Button {
                    // Open new window with terminal output
                    openWindow(value: output)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.bordered)
                .help("View terminal output")
                .accessibilityLabel("View terminal output")

                Button {
                    caskManager.dismissFailure(cask)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .help("Dismiss")
                .accessibilityLabel("Dismiss error")
            }

        case .idle:
            EmptyView()
        }
    }
}

#Preview {
    AppView(cask: .dummy, role: .installAndManage)
}
