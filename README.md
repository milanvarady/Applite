[![License](https://img.shields.io/github/license/milanvarady/Applite)](LICENSE.txt)
[![Latest release](https://img.shields.io/github/v/release/milanvarady/Applite)](https://github.com/milanvarady/Applite/releases/latest)
[![All releases](https://img.shields.io/github/downloads/milanvarady/Applite/total)](https://github.com/milanvarady/Applite/releases)
[![Contributors](https://img.shields.io/github/contributors/milanvarady/Applite)](https://github.com/milanvarady/Applite/graphs/contributors)
![GitHub commits since latest release (by SemVer including pre-releases)](https://img.shields.io/github/commits-since/milanvarady/Applite/latest)


# Applite

A native macOS app store for software that isn't on the App Store, backed by [Homebrew Cask](https://github.com/Homebrew/homebrew-cask).

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
- Self-contained Homebrew installation, no Command Line Tools required
- Works with an existing Homebrew installation if you have one
- Handpicked gallery of apps, plus full-catalog FTS5 search
- Brewfile import and export for migrating to a new Mac
- Casks from custom taps
- System proxy support (HTTP, HTTPS, SOCKS5)
- Localized in 7 languages
- Free and open source, no telemetry

## Screenshots

![Discover Page Screenshot](https://github.com/user-attachments/assets/d6861ab4-d9ce-40de-982b-8940fc1d1fbf)
![Productivity Category Screenshot](https://github.com/user-attachments/assets/e17846e0-bdbf-4ac3-b922-572ffe69acc2)

## Download

[Download DMG](https://github.com/milanvarady/applite/releases/latest/download/Applite.dmg)

or

`$ brew install --cask applite`

Minimum OS version: **macOS 14+**. Universal binary, Apple Silicon and Intel.

## Built With

Swift and SwiftUI, targeting macOS 14 so `@Observable` and `NavigationSplitView` are available without back-deployment shims. No Combine. The cask catalog is a local SQLite database (GRDB.swift, WAL mode) synced from the Homebrew JSON API, with FTS5 and BM25 ranking for full-catalog search. Loading is two-stage: SQLite paints the UI immediately, then `brew list --cask` and `brew outdated --cask` fill in installed and outdated state reactively, so nothing blocks on the brew CLI.

Architecture notes are in [CLAUDE.md](CLAUDE.md).

## Development and AI

I'm the sole maintainer of Applite. Starting with version 1.4, I use [Claude Code](https://claude.com/claude-code) as part of my development workflow, and I'd rather state that plainly than leave people to guess.

The reason is capacity. This is a side project maintained by one person, and the realistic alternative to AI-assisted development is not hand-written code, it's a much slower release cycle or no releases at all. Several things that shipped recently, the SQLite migration and the six-language localization among them, would have sat in the backlog indefinitely otherwise.

Scope of what that actually means:

- The core of the app was written by hand, before any AI involvement.
- AI assistance is used for refactoring and reorganization work, and for small to medium sized new features.
- Architecture decisions, code review, and what does and doesn't go into the app are mine. Nothing merges that I haven't read.

If you object to AI-assisted code on principle, that's a legitimate position and [Cork](https://github.com/buresdv/Cork) is explicitly developed without it.

## Contact

If you have any questions, feel free to e-mail me: [milan@aerolite.dev](mailto:milan@aerolite.dev)

Or join the [Official Discord Server](https://discord.gg/MpDMH9cPbK).

FAQ on the [official website](https://aerolite.dev/applite/FAQ.html).

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
