//
//  DebouncedTaskModifier.swift
//  Applite
//
//  Created by Milán Várady on 2025.
//

import SwiftUI

extension View {
    /// A debounced version of `.task(id:)` that delays the action execution.
    /// When `id` changes, SwiftUI cancels the previous task (cancelling the sleep),
    /// providing natural debouncing.
    func task<T: Equatable>(id: T, debounceTime: Duration, @_inheritActorContext action: @escaping @Sendable () async -> Void) -> some View {
        self.task(id: id) {
            try? await Task.sleep(for: debounceTime)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    /// A debounced version of `.onChange(of:)` that delays the action execution.
    func onChange<T: Equatable>(of value: T, debounceTime: Duration, action: @escaping (_ newValue: T) -> Void) -> some View {
        self.modifier(DebouncedOnChangeModifier(value: value, debounceTime: debounceTime, action: action))
    }
}

private struct DebouncedOnChangeModifier<T: Equatable>: ViewModifier {
    let value: T
    let debounceTime: Duration
    let action: (T) -> Void

    @State private var debounceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { newValue in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(for: debounceTime)
                    guard !Task.isCancelled else { return }
                    action(newValue)
                }
            }
    }
}
