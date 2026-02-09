# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Applite is a macOS GUI application for managing Homebrew Casks, built with Swift 6.0 and SwiftUI. It targets macOS 13+ and aims to be a simple "app store" for third-party apps rather than a full Homebrew wrapper. Bundle ID: `dev.aerolite.Applite`.

## Build & Run

This is an Xcode project (`Applite.xcodeproj`). There is no Makefile or CLI build script.

```bash
# Build from command line
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Debug build

# Build for release
xcodebuild -project Applite.xcodeproj -scheme Applite -configuration Release build
```

Open in Xcode for the standard build/run/debug workflow. There are no tests in this project.

## Architecture

### Entry Point & App Lifecycle

`AppliteApp.swift` is the `@main` entry point. It creates a `CaskManager` as `@StateObject` and passes it via `@EnvironmentObject`. On first launch, `SetupView` handles Homebrew detection/installation; thereafter `ContentView` is shown.

### Core Data Flow

**CaskManager** (`Model/Cask Models/Cask Manager/`) is the central state manager:
- Holds all casks in `[CaskId: Cask]` dictionary
- Maintains three `SearchableCaskCollection`s: all, installed, outdated
- Tracks active brew tasks and categories
- `loadData()` delegates to `CaskDataCoordinator` which fetches from network/cache in parallel

**Cask** (`Model/Cask Models/Cask/`) is the core entity — an `ObservableObject` with `CaskInfo` (static data) and `@Published` state for install status and progress. Protocol conformances are split across extension files (`Cask+Hashable.swift`, `Cask+Searchable.swift`, etc.).

**Data Models** (`Model/Cask Models/Data Models/`): `CaskDTO` for API deserialization, `CaskInfo` for domain model, `BrewAnalytics` for download counts.

### Shell Execution

`Shell` (`Utilities/Shell/Shell.swift`) is the namespace for all shell interactions:
- `run()` — synchronous execution
- `runAsync()` — async execution
- `runBrewCommand()` — brew-specific async execution
- `stream()` — returns `AsyncThrowingStream<String, Error>` for real-time output
- Verifies askpass script checksum (MD5) for security before each execution
- Configures proxy and mirror environment variables automatically

### View Organization

Views are heavily decomposed using Swift extensions:
- `ContentView` splits into `+SidebarViews`, `+DetailView`, `+LoadCasks`, `+SearchFunctions`
- `AppView` splits into `+ActionsView`, `+DownloadButton`, `+UpdateButton`, `+UninstallButton`, etc.
- Major screens: `DiscoverView`, `HomeView`, `InstalledView`, `UpdateView`, `CategoryView`
- Setup wizard: `SetupView` + multiple extension files for each step

### Key Utilities

- **BrewPaths** (`Utilities/Other/BrewPaths.swift`): Manages multiple brew executable paths (app-specific, Apple Silicon, Intel, custom)
- **NetworkProxyManager**: System proxy detection (HTTP, HTTPS, SOCKS5)
- **MirrorEnvironment**: Homebrew mirror configuration for restricted regions
- **DependencyManager**: Handles Homebrew and Xcode CLT installation
- **AlertManager**: Centralized alert presentation via view modifier

## Dependencies (Swift Package Manager)

- **Sparkle** — Auto-update framework (appcast.xml at project root)
- **Kingfisher** — Image downloading/caching (configured with proxy in `AppliteApp.init()`)
- **Ifrit** (fuse-swift fork) — Fuzzy search for cask names
- **ButtonKit** — Enhanced async button components
- **SwiftUI-Shimmer** — Loading placeholder animations
- **CircularProgressSwiftUI** — Progress indicators
- **DebouncedOnChange** — Debounced SwiftUI onChange modifier

## Key Patterns

- `@MainActor` on all `ObservableObject` classes (CaskManager, Cask)
- `async/await` throughout; `AsyncThrowingStream` for streaming brew output
- `@AppStorage` wrapping `Preferences` enum raw values for UserDefaults
- `@EnvironmentObject` for injecting `CaskManager` into views
- Logging via `OSLog` with `Logger` instances per class
- Localization via `Localizable.xcstrings` (English, French, Hungarian, Japanese, Chinese Simplified)

## Resources

- `Resources/categories.json` — Handpicked app categories for the Discover page
- `Resources/askpass.js` — JXA script for sudo authentication (checksum-verified)
- `Resources/brew-tap-cask-info.rb` — Ruby script for fetching tap cask info
