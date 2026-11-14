# Applite

A native macOS app store for software that isn't on the App Store, backed by [Homebrew Cask](https://github.com/Homebrew/homebrew-cask).

[![Latest release](https://img.shields.io/github/v/release/milanvarady/Applite?style=flat-square)](https://github.com/milanvarady/Applite/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/milanvarady/Applite/total?style=flat-square)](https://github.com/milanvarady/Applite/releases)
[![License](https://img.shields.io/github/license/milanvarady/Applite?style=flat-square)](LICENSE.txt)

## Table of Contents

1. [What Sets Applite Apart](#what-sets-applite-apart)
2. [Comparison](#comparison)
3. [Key Features](#key-features)
4. [Screenshots](#screenshots)
5. [Download](#download)
6. [Built With](#built-with)
7. [Development and AI](#development-and-ai)
8. [Contact](#contact)
9. [Roadmap](#roadmap)
10. [Contributing](#contributing)
11. [Packages Used](#packages-used)
12. [Credits](#credits)
13. [License](#license)
14. [Alternatives](#alternatives)

## What Sets Applite Apart

**Applite brings its own Homebrew.** Every other Homebrew GUI expects `brew` to already be on the machine, which means the user has opened a Terminal and installed the Xcode Command Line Tools first. Applite downloads a Homebrew tarball into its own Application Support directory on first launch and runs it from there, in API mode behind a git shim.

- **No Terminal, no Command Line Tools.** Applite can be the first app on a fresh Mac.
- **Brewfile import and export**, so restoring your apps on a new machine is a file and a checklist.
- **Casks only, by design.** No formulae, no services, no CLI surface. Apps in categories, with icons and a search field.
- **Uses your existing Homebrew** if you have one. Point it at any prefix in Settings.

## Comparison

Three actively developed alternatives worth knowing about. All of them are good software solving a slightly different problem.

|                          | **Applite**                            | [CaskHub](https://github.com/alielsokary/CaskHub) | [BrewUI](https://github.com/Homebrew/brewui) | [Cork](https://github.com/buresdv/Cork) |
| ------------------------ | -------------------------------------- | ------------------------------------------------- | -------------------------------------------- | --------------------------------------- |
| Installs Homebrew itself | Yes, no CLT or Terminal needed         | No, guided manual setup                            | No                                            | No                                       |
| Scope                    | Casks only                             | Casks only                                         | Formulae and casks                            | Formulae, casks, services, taps          |
| Audience                 | Non-technical                          | Non-technical                                      | All Homebrew users                            | Power users                              |
| Price                    | Free                                   | Free                                               | Free                                          | 25 € prebuilt, free if self-compiled     |
| License                  | MIT                                    | MIT                                                | AGPL-3.0                                      | Commons Clause (source available)        |
| Minimum macOS            | 14                                     | 15.6                                               | 14                                            | 13                                       |
| Brewfile import/export   | Yes, with a per-app selection sheet    | No                                                 | Not yet                                       | Yes                                      |
| Telemetry                | None                                   | Sentry + TelemetryDeck                             | None                                          | None                                     |
| Status                   | Released                               | Released                                           | Early development                             | Released                                 |

Comparison drawn in August 2026; check the projects themselves for current state.

## Key Features

- Install, update, and uninstall apps in one click
- Detect externally installed apps and adopt them into Homebrew management with confirmation
- Self-contained Homebrew installation, no Command Line Tools required
- Works with an existing Homebrew installation if you have one
- Handpicked gallery of apps, plus full-catalog FTS5 search
- Brewfile import and export for migrating to a new Mac
- Casks from custom taps
- System proxy support (HTTP, HTTPS, SOCKS5)
- Localized in 7 languages
- Free and open source, no telemetry

## Screenshots

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/milanvarady/Applite/main/docs/screenshots/discover-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/milanvarady/Applite/main/docs/screenshots/discover-light.png">
  <img alt="Applite Discover page" src="https://raw.githubusercontent.com/milanvarady/Applite/main/docs/screenshots/discover-light.png">
</picture>

## Download

[applite.app](https://applite.app) or a direct
[DMG download](https://github.com/milanvarady/Applite/releases/latest/download/Applite.dmg)

or

`$ brew install --cask applite`

Minimum OS version: **macOS 14+**. Universal binary, Apple Silicon and Intel.

## Single-instance behavior

Only one Applite instance runs per macOS user, including copies launched from
different locations with the same bundle identifier. Launching it again brings
the existing main window forward or reopens it when needed, rather than starting
another Homebrew/database session or showing a routine "already running" warning.
The startup lock is released automatically when the process exits, including
after a crash. Lock or handoff errors are reported instead of starting unprotected.

When upgrading, quit any older copies that are already running once. The new
version does not terminate another copy's in-progress Homebrew work.

All self-uninstall entry points share **Settings > Uninstall**. Choosing Uninstall
from the app menu or optional diagnostic self-card selects that pane and opens or focuses the
existing Settings window instead of creating a separate uninstaller.

The app menu's **Check for Updates...** action selects and opens or focuses
**Settings > Updates** before starting the existing Sparkle update check.
It remains disabled while a check is in progress.

The main window has a persistent bottom status bar with a **Refresh App Catalog**
button and a shortcut to **Active Tasks**. It shows startup/setup, catalog refresh,
installed-app checks, queued/running installs, updates, uninstalls, and failed tasks.
Failed tasks remain available for inspection but do not leave a spinner running.
Downloads show Homebrew's real percentage; bulk installs/updates show completed
app counts. Catalog refresh uses an indeterminate spinner, not an estimated
percentage, and the catalog remains available to browse. Refresh is disabled while
a refresh, installed-state check, standalone app-update check, startup/setup, or
Homebrew maintenance is running. Standalone update checks and retries show their
own busy status instead of Ready or an old failure.

App names stay in their human-readable form. Clicking a name opens **Get Info**,
with loading feedback while Homebrew retrieves details; it no longer toggles all
cards to cask tokens. The info window shows the app name, description, available
version, installation details, source, links, download size when available, and
deprecation/disablement information. Homebrew tokens remain selectable there.
Cmd-click continues to open the app's website.

**Include Self-Updating Apps** is configured in Settings, not duplicated in the
Updates toolbar. Updates retains its refresh button and search.

Applite does not show itself in the app lists by default. Its update and uninstall
actions remain in the app menu and Settings. A default-off, internal developer
preference can restore the Installed self-card for diagnostics; see the
[diagnostic instructions](Testing/README.md#optional-applite-self-card).

## Built With


Swift and SwiftUI, targeting macOS 14 so `@Observable` and `NavigationSplitView` are available without back-deployment shims. No Combine. The cask catalog is a local SQLite database (GRDB.swift, WAL mode) synced from the Homebrew JSON API, with FTS5 and BM25 ranking for full-catalog search. Loading is two-stage: SQLite paints the UI immediately, then `brew list --cask` and `brew outdated --cask` fill in installed and outdated state reactively, so nothing blocks on the brew CLI.

Architecture notes are in [CLAUDE.md](CLAUDE.md).

### Externally installed apps

Bulk imports skip apps already present outside the selected Homebrew; use the
confirmed single-app action to manage an external app. Ordinary installs and bulk
imports do not use `--force`, so missing or stale catalog artifact names cannot
silently replace an existing app; Homebrew may instead report a conflict.
Disabling either management prerequisite
permanently invalidates open/queued confirmations until a new confirmation is made.
Receipt refreshes are bound to their selected Homebrew configuration and cannot
publish after it changes. Path edits debounce detection; superseded scans are canceled.

Install rechecks the expected app bundle before running, so an unfinished detection
scan cannot silently turn Install into Homebrew adoption. Adoption confirmation is
bound to the selected Homebrew and installation directory; changing either requires
a fresh confirmation, including for queued work. Detection drops superseded scans,
and a failed post-install refresh retains the command's output alongside its error.

**Settings > Brew > App Sources > Detect externally installed apps** is enabled by
default. Turn it off to stop external-app scans, clear external status/counts, and
hide the external-app sidebar/search filters and adoption actions. Managed apps are
unaffected, and no apps are changed or removed. Turning it back on rescans locally;
no catalog download is required.

**Offer Manage with Homebrew**, indented beneath detection, defaults to off when
no preference has been saved. Enable it to offer Homebrew management on external
app cards; otherwise, they show **Open** while detection, status, filters, and
counts remain available. Both settings must be enabled to offer management.
When detection is off, the management setting is greyed out and unavailable.
Its saved choice is preserved and respected when detection is re-enabled.
Disabling management also prevents an already-open confirmation from starting a reinstall.

Apps found in `/Applications`, `~/Applications`, or your custom app directory that are
not tracked by the selected Homebrew appear as **Installed externally**. Detection uses
the cask's expected app bundle names (including renamed targets), with the display name
as a fallback when no app artifact is available. Non-app casks are not inferred from
package receipts or executables.

Use the **Installed externally** sidebar item or search-menu filter to find these apps.
Choose **Manage with Homebrew** on a card to review the exact command before continuing:
`brew install --cask <token> --force` (plus your custom app-directory option, if set).
This reinstalls the app so Homebrew can track its updates. A successful adoption refreshes
the managed state; a failed command preserves the previous state and exposes the full
Homebrew output, including stderr, from the card's terminal button.

## Development and AI

I'm the sole maintainer of Applite. Starting with version 1.4, I use [Claude Code](https://claude.com/claude-code) as part of my development workflow, and I'd rather state that plainly than leave people to guess.

The reason is capacity. This is a side project maintained by one person, and the realistic alternative to AI-assisted development is not hand-written code, it's a much slower release cycle or no releases at all. Several things that shipped recently, the SQLite migration and the six-language localization among them, would have sat in the backlog indefinitely otherwise.

Scope of what that actually means:

- The core of the app was written by hand, before any AI involvement.
- AI assistance is used for refactoring and reorganization work, and for small to medium sized new features.
- Architecture decisions, code review, and what does and doesn't go into the app are mine. Nothing merges that I haven't read.

If you object to AI-assisted code on principle, that's a legitimate position and [Cork](https://github.com/buresdv/Cork) is explicitly developed without it.

## Contact

If you have any questions, feel free to e-mail me: [milan@milanvarady.dev](mailto:milan@milanvarady.dev)

Or join the [Official Discord Server](https://discord.gg/MpDMH9cPbK).

The [FAQ](https://applite.app/faq) and [Troubleshooting](https://applite.app/troubleshooting) pages
answer most questions.

## Roadmap

I don't have much time for development, but I release updates periodically.

View the [roadmap](https://github.com/users/milanvarady/projects/1).

## Contributing

The project is open to contributions. See the [Contribution Guidelines](docs/CONTRIBUTING.md) for more information.

For typos and minor bugs, open a PR directly. For anything larger, open an issue or bring it up on Discord first, so we don't both spend time on something that doesn't fit the project's scope.

## Packages Used

- [Homebrew](https://github.com/homebrew) - the package manager everything is built on
- [GRDB.swift](https://github.com/groue/GRDB.swift), Gwendal Roué - SQLite database and FTS5 search
- [Sparkle](https://github.com/sparkle-project/Sparkle) - app updates
- [Kingfisher](https://github.com/onevcat/Kingfisher), Wei Wang - image downloading and caching
- [ButtonKit](https://github.com/Dean151/ButtonKit), Thomas Durand - async buttons
- [SwiftUI-Shimmer](https://github.com/markiv/SwiftUI-Shimmer), Vikram Kriplaney - loading placeholders

## Credits

App icons are sourced from [CaskFlow](https://github.com/alielsokary/CaskFlow) by Ali Elsokary (MIT), a metadata pipeline that extracts icons from vendor `.icns` files. Casks without a CaskFlow icon fall back to a generated monogram tile.

## License

Applite is licensed under the [MIT](https://choosealicense.com/licenses/mit/) License. See [LICENSE](LICENSE.txt) for more details.

## Alternatives

Compared above:

- [CaskHub](https://github.com/alielsokary/CaskHub) - cask-focused app store with strong discovery features
- [BrewUI](https://github.com/Homebrew/brewui) - Homebrew's official GUI, in early development
- [Cork](https://github.com/buresdv/Cork) - full-featured Homebrew GUI for power users

Others:

- [WailBrew](https://github.com/wickenico/WailBrew) (Go, Wails, React)
- [Brewer X](https://panini.house/brewer/) (paid)
- [BrewMate](https://github.com/romankurnovskii/BrewMate) (Electron based)
- [Brewlet](https://github.com/zkokaja/Brewlet) (menu bar app)
- [App Fair](https://github.com/App-Fair/App) (looks discontinued)
- [Cakebrew](https://github.com/brunophilipe/Cakebrew) (discontinued)
