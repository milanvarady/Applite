//
//  AsyncButton.swift
//  Applite
//
//  Created by Milán Várady on 2025.
//

import SwiftUI

enum AsyncButtonStyle {
    /// Shows a ProgressView overlay while running
    case `default`
    /// Shows a ProgressView after the label
    case trailing
    /// No visual indicator, just disables the button
    case none
}

struct AsyncButton<Label: View>: View {
    var action: () async throws -> Void
    var errorHandler: ((Error) -> Void)?
    var style: AsyncButtonStyle = .default
    @ViewBuilder var label: () -> Label

    @State private var isRunning = false

    var body: some View {
        Button {
            isRunning = true
            Task {
                do {
                    try await action()
                } catch {
                    errorHandler?(error)
                }
                isRunning = false
            }
        } label: {
            switch style {
            case .default:
                label()
                    .opacity(isRunning ? 0 : 1)
                    .overlay {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            case .trailing:
                HStack(spacing: 6) {
                    label()
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            case .none:
                label()
            }
        }
        .disabled(isRunning)
    }
}

// MARK: - Convenience Initializers

extension AsyncButton where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, systemImage: String, action: @escaping () async throws -> Void) {
        self.action = action
        self.label = { SwiftUI.Label(title, systemImage: systemImage) }
    }
}

extension AsyncButton where Label == Text {
    init(_ title: String, action: @escaping () async throws -> Void) {
        self.action = action
        self.label = { Text(title) }
    }
}

// MARK: - Modifiers

extension AsyncButton {
    func onButtonError(_ handler: @escaping (Error) -> Void) -> AsyncButton {
        var copy = self
        copy.errorHandler = handler
        return copy
    }

    func asyncButtonStyle(_ style: AsyncButtonStyle) -> AsyncButton {
        var copy = self
        copy.style = style
        return copy
    }
}
