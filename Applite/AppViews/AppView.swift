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
    @State var successCheckmarkScale = 0.0001
    @State var keepSuccessIndicator = false

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
            // Right-click access to the same actions as the chevron menu
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
    }

    /// The chevron and right-click menu are shown for installable/installed apps,
    /// but not in the update list.
    private var showsOptionsMenu: Bool {
        role != .update
    }

    /// "More options" menu shared by the chevron button and the card's
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

            Divider()

            Button {
                caskManager.install(cask, force: true)
            } label: {
                Label("Force Install", systemImage: "bolt.trianglebadge.exclamationmark.fill")
            }
        }
    }

    private var getInfoButton: some View {
        Button {
            Task { await getInfo() }
        } label: {
            Label("Get Info", systemImage: "info")
        }
    }

    /// Chevron button that opens the options menu (native dropdown).
    private var optionsMenuButton: some View {
        Menu {
            optionsMenuContent
        } label: {
            Image(systemName: "chevron.down")
                .padding(.vertical)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
        if self.cask.progressState == .idle {
            if !keepSuccessIndicator {
                mainButtons
            } else {
                successCheckmark
            }
        } else {
            progressView
        }
    }

    @ViewBuilder
    private var mainButtons: some View {
        switch role {
        case .installAndManage:
            if cask.isInstalled {
                OpenAndManageView(cask: cask, deleteButton: false)
            } else {
                DownloadButton(cask: cask)
                    .padding(.trailing, 5)
            }

            optionsMenuButton

        case .update:
            UpdateButton(cask: cask)

        case .installed:
            OpenAndManageView(cask: cask, deleteButton: true)
                .padding(.trailing, 5)

            optionsMenuButton
        }
    }

    private var successCheckmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.green)
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

        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.green)
                .scaleEffect(successCheckmarkScale)
                .onAppear {
                    withAnimation(.spring(blendDuration: 0.5)) {
                        successCheckmarkScale = 1
                    }

                    if self.role == .installAndManage {
                        Task { @MainActor in
                            try await Task.sleep(for: .seconds(1.5))
                            withAnimation(.spring(blendDuration: 1)) {
                                successCheckmarkScale = 0.0001
                            }
                        }
                    } else {
                        keepSuccessIndicator = true
                    }
                }

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

                Button {
                    cask.progressState = .idle
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .help("Dismiss")
            }

        case .idle:
            EmptyView()
        }
    }
}

#Preview {
    AppView(cask: .dummy, role: .installAndManage)
}
