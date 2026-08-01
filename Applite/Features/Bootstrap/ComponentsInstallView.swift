//
//  ComponentsInstallView.swift
//  Applite
//
//  Created by Milán Várady on 2025.07.06.
//

import SwiftUI

/// Non-dismissable modal card shown (as an in-window overlay from `ContentView`) while Applite
/// installs its own ("annex") Homebrew, or if that install fails. There is no onboarding — this
/// only gates install actions until brew is ready.
///
/// The card is laid out as four fixed slots — icon, title, description, action — that are always
/// present and only *morph* their content between phases. Nothing is inserted or removed, so the
/// layout never reflows and elements don't jump when the install finishes.
struct ComponentsInstallView: View {
    /// Observes `bootstrap` directly (reading `phase`/`statusLine`). Safe because the card is
    /// composited in a plain SwiftUI `ZStack` in `ContentView` — not `.overlay` over the split
    /// view's NSSplitView representable, where child-driven updates failed to repaint.
    let bootstrap: HomebrewBootstrap

    private var phase: HomebrewBootstrap.Phase { bootstrap.phase }
    private var statusLine: String { bootstrap.statusLine }

    @Environment(\.openURL) private var openURL

    private let troubleshootingURL = URL(string: "https://aerolite.dev/applite/troubleshooting.html")!

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                // 1. Icon — isolated view (only re-renders on phase change) so its pulse survives
                //    the streamed status-line updates. Outside the animation scope below so that
                //    scope can't interfere with its symbol effects.
                SetupStatusIcon(phase: phase)
                    .frame(height: 46)

                // 2–4. Title / description / action. These morph with `phase`, so the animation
                //    scope lives here (not around the icon).
                VStack(spacing: 12) {
                    title
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)
                        .frame(height: 28)

                    description
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        // `minHeight` keeps installing/installed (both short) at a stable height so
                        // they don't jump, while a long failure message can still grow downward.
                        .frame(minHeight: 56, alignment: .top)

                    actionSlot
                        .frame(height: 44)
                }
                .animation(.smooth, value: phase)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // The "use your own Homebrew" shortcut stays visible the whole time — the annex install
            // is only a couple of seconds, so an inline path picker isn't worth the clutter.
            ownBrewNote
        }
        .padding(28)
        .frame(width: 470)
    }

    // MARK: - Slot content

    private var title: Text {
        switch phase {
        case .installed:
            Text("Applite is ready", comment: "Components install sheet success title")
        case .failed:
            Text("Setup failed", comment: "Components install sheet failure title")
        case .brewMissing:
            Text("Homebrew not found", comment: "Components install sheet title when the user's selected brew is missing")
        default:
            Text("Setting up components", comment: "Components install sheet title")
        }
    }

    private var description: Text {
        switch phase {
        case .installed:
            Text("The components Applite needs are installed. You can start downloading apps right away.", comment: "Components install sheet success description")
        case .failed(let message):
            Text(message)
        case .brewMissing(let path):
            Text("Couldn't locate the Homebrew executable at \(path). The installation is missing or damaged. Try running `brew doctor` in Terminal.", comment: "Components install sheet description when the user's selected brew is missing")
        default:
            Text("Applite is downloading Homebrew, the engine it uses to install apps. This only happens once and takes just a few seconds.", comment: "Components install sheet description")
        }
    }

    @ViewBuilder
    private var actionSlot: some View {
        switch phase {
        case .installed:
            Button {
                bootstrap.acknowledgeInstall()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .transition(.opacity)

        case .failed, .brewMissing:
            HStack {
                Button {
                    bootstrap.requestReload()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut(.defaultAction)

                Button {
                    openURL(troubleshootingURL)
                } label: {
                    Label("Troubleshooting", systemImage: "exclamationmark.magnifyingglass")
                }
            }
            .controlSize(.large)
            .transition(.opacity)

        default:
            Text(statusLine)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Keep the slot occupied before the first line streams so nothing shifts.
                .opacity(statusLine.isEmpty ? 0 : 1)
                .transition(.opacity)
        }
    }

    /// Shown under the main content: a note that the user can switch to their own Homebrew, with a
    /// shortcut into Settings (where the brew-path selector lives).
    private var ownBrewNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text("Already have Homebrew? You can switch to it anytime in Settings.", comment: "Components install sheet own-brew note")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            SettingsLink {
                Text("Open Settings", comment: "Components install sheet open settings button")
            }
        }
    }
}
