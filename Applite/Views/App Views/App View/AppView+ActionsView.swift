//
//  AppView+ActionsView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
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
            .foregroundColor(.green)
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
            CircularProgressView(progress: percent, lineWidth: 4)
                .frame(width: 36, height: 36)

        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.green)
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
