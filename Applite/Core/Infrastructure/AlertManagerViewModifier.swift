//
//  AlertManagerViewModifier.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.27.
//

import SwiftUI

/// Presents an `AlertManager`'s queue. Attach it **once per window**, at that window's root — one
/// binding per manager. Attaching it to a view that's mounted many times (a grid cell, say) gives
/// every copy the same `isPresented`, and SwiftUI then picks an arbitrary one to present from.
struct AlertModifier: ViewModifier {
    @Bindable var manager: AlertManager

    func body(content: Content) -> some View {
        content
            .alert(
                manager.current?.title ?? "",
                isPresented: $manager.isPresented,
                // `presenting:` snapshots the content, so the dialog keeps its text while it
                // animates away and the next queued alert can take `current` cleanly.
                presenting: manager.current
            ) { alert in
                ForEach(alert.actions) { action in
                    Button(action.title, role: action.role) {
                        action.handler?()
                    }
                }
            } message: { alert in
                Text(alert.message)
            }
            // Any dismissal — button, Esc, or SwiftUI's own — flips this, so the queue drains from
            // one place instead of from each button's action.
            .onChange(of: manager.isPresented) { _, isPresented in
                if !isPresented { manager.alertDismissed() }
            }
    }
}

extension View {
    func alertManager(_ manager: AlertManager) -> some View {
        modifier(AlertModifier(manager: manager))
    }
}
