//
//  ContentView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI

struct ContentView: View {
    @Environment(CaskManager.self) var caskManager

    /// Currently selected sidebar item. Optional so the selection can be cleared
    /// while a search is active, so a sidebar tap can interrupt the search instead
    /// of being swallowed by the SearchView in the detail pane.
    @State var selection: SidebarItem? = .home

    /// Remembers the last non-nil selection so that clearing the search field
    /// (e.g. via Esc) can restore the user to the screen they were on.
    @State var lastSelection: SidebarItem = .home

    /// If true the sidebar is disabled
    @State var modifyingBrew = false

    /// App search query
    @State var searchInput = ""

    var body: some View {
        // `body` reads only `phase` (to gate the overlay), not `statusLine`. The card observes
        // `bootstrap` directly for the streamed status line — safe because it's composited in the
        // ZStack below rather than layered over the split view's representable (see that comment).

        // The setup card is a sibling layer in this top-level ZStack — NOT an `.overlay` modifier
        // on the NavigationSplitView. On macOS the split view is backed by an AppKit NSSplitView
        // (a representable); content layered over it via `.overlay`/`.sheet` only repainted on a
        // forced layout pass (window drag), so the status line stalled. As a plain SwiftUI sibling
        // here it lives in SwiftUI's own layout tree and repaints on every change, while still
        // covering the whole window (sidebar + detail).
        ZStack {
            mainNavigation

            // `bootstrap.phase` is the single owned "is brew usable" state, so this overlay — up for
            // the annex install *and* every broken outcome — is the only place a broken brew changes
            // the UI. Nothing else branches on it (E1).
            if caskManager.bootstrap.needsSetupOverlay {
                setupOverlay
            }
        }
        // The window's one alert surface, presented once at its root: brew failures, load failures
        // and errors raised by any view in this window queue here (F5/P3-5). Never bind this inside
        // a repeated view — that was the bug it replaces.
        .alertManager(caskManager.alert)
    }

    private var mainNavigation: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .disabled(modifyingBrew)
                .navigationSplitViewColumnWidth(min: 200, ideal: 216)
        } detail: {
            if !searchInput.isEmpty {
                SearchView(query: $searchInput)
            } else if selection != nil {
                DetailView(
                    selection: $selection,
                    modifyingBrew: $modifyingBrew
                )
            }
        }
        // Re-runs on launch and whenever the install sheet's Retry / "use my own brew" escape
        // hatch bumps `attempt` — bumping cancels any in-flight annex install.
        .task(id: caskManager.bootstrap.attempt) {
            await caskManager.bootstrapAndLoad()
        }
        .searchable(text: $searchInput, placement: .sidebar)
        .onChange(of: searchInput) { _, newValue in handleSearchInputChange(newValue) }
        .onChange(of: selection) { _, newValue in handleSelectionChange(newValue) }
        // A deep view (e.g. "See Active Tasks" on a batched card) requested a tab — apply it.
        .onChange(of: caskManager.requestedTab) { _, requested in
            if let requested {
                searchInput = ""
                selection = requested
                caskManager.requestedTab = nil
            }
        }
    }

    /// Non-dismissable "Setting up components…" modal. Passes the `bootstrap` object so the card
    /// observes it directly (see `ComponentsInstallView`).
    private var setupOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.2))
                .ignoresSafeArea()

            ComponentsInstallView(bootstrap: caskManager.bootstrap)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        }
    }

    // MARK: - Search

    private func handleSearchInputChange(_ newValue: String) {
        // Limit search characters
        if newValue.count > 30 {
            searchInput = String(newValue.prefix(30))
            return
        }

        if !newValue.isEmpty {
            // Typing starts a search — remember where we were and clear the selection.
            if let current = selection {
                lastSelection = current
                selection = nil
            }
        } else if selection == nil {
            // Search cleared without a sidebar tap (Esc / clear button) — restore.
            selection = lastSelection
        }
    }

    private func handleSelectionChange(_ newValue: SidebarItem?) {
        // Sidebar tap during a search wins: clear the query so the detail
        // switches from SearchView to the tapped destination.
        if newValue != nil, !searchInput.isEmpty {
            searchInput = ""
        }
    }
}

#Preview {
    ContentView()
}
