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
        .alertManager(caskManager.alert)
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

        case .update:
            UpdateButton(cask: cask)

        case .installed:
            OpenAndManageView(cask: cask, deleteButton: true)
                .padding(.trailing, 5)
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
            CircularProgressRing(progress: percent)
                .frame(width: 30, height: 30)

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
            HStack {
                Text("Error", comment: "Cask action failed (e.g. installation failed)")
                    .foregroundStyle(.red)

                Button {
                    // Open new window with shell output
                    openWindow(value: output)
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.bordered)

                Button("OK") {
                    cask.progressState = .idle
                }
                .buttonStyle(.bordered)
            }

        case .idle:
            EmptyView()
        }
    }
}

#Preview {
    AppView(cask: .dummy, role: .installAndManage)
}
