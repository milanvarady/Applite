# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Applite is a native macOS GUI application for Homebrew Casks, designed as an "app store for third-party apps" rather than a full Homebrew wrapper. Target audience is non-technical users who want simple app installation/management.

- **Language**: Swift with SwiftUI (`@Observable`, `@MainActor`, async/await)
- **Platform**: macOS 14+ (Apple Silicon and Intel)
- **Build System**: Xcode with Swift Package Manager for dependencies. Uses Xcode 16+ **file-system synchronized groups** (folder-based project): the on-disk folder structure *is* the project structure. Adding, removing, moving, or renaming source files needs **no `project.pbxproj` edits** — just change the files on disk and Xcode picks them up automatically. Do not hand-edit the pbxproj for file management.
- **Database**: GRDB.swift (SQLite) at `~/Library/Application Support/Applite/casks.sqlite`

## Build & Run

Open `Applite.xcodeproj` in Xcode and build/run (⌘R). Dependencies resolve automatically via SPM.

## Architecture

### Data Flow

1. **App Launch**: `ContentView.task(id: bootstrap.attempt)` calls `caskManager.bootstrapAndLoad()`
2. **First Run**: `HomebrewBootstrap` installs/validates brew; while `bootstrap.needsSetupOverlay` is true, `ContentView` covers the window with the non-dismissable `ComponentsInstallView` modal (`Features/Bootstrap/`). There is no separate onboarding flow — the app opens straight into the main UI
3. **Main UI**: `ContentView` with `NavigationSplitView` sidebar navigation
4. **Data Loading**: `CaskManager.loadData()` runs in two stages — catalog (DB-only, instant) then brew CLI state (slow). The UI lights up after stage 1; installed/outdated state arrives reactively as stage 2 completes.

### Key Components

The shared cask/brew engine lives under `Applite/Core/`, split into focused subfolders:

**Persistence** (`Applite/Core/Database/`)
- `AppDatabase` - Schema migrations, DatabasePool with WAL mode, FTS5 virtual table on `casks`
- `CaskRecord` - GRDB `FetchableRecord`/`PersistableRecord`, decodes from `CaskDTO`
- `CaskDatabaseService` - CRUD, FTS5 search (async), API sync

**Cask engine** (`Applite/Core/CaskCore/`) — the `@Observable` runtime layer
- `CaskViewModel` - `@Observable @MainActor` view model wrapping `CaskRecord` with runtime state (`isInstalled`, `isOutdated`, `progressState`)
- `CaskViewModelRegistry` - Single-identity store; `viewModels(for:)` is get-or-create so the same cask shares one VM across views. **Identity is `fullToken` everywhere** — DB primary key, registry key, brew ops. The bare `token` is not unique (two taps can each ship a "firefox"), so it must never key anything; it's indexed for lookup only
- `CaskDataLoader` - Orchestrates: `loadCatalogData()` (DB-only), `refreshInstalled()`/`refreshOutdated()` (brew CLI), `search(query:)` (FTS5). Defines `CategoryLoadResult` and `TapLoadResult`.
- `CaskWarning` - Warning enum (deprecated/disabled/caveat)
- `CaskProgressState`, `CaskLoadError` - install progress + load error types

**Plain models** (`Applite/Core/Models/`)
- `CaskDTO`, `CaskAdditionalInfo`, `BrewAnalytics` - decode-only DTOs for the Homebrew API/JSON
- `Category`, `CategoryLoadResult+LocalizedName`, `TapLoadResult`, `SidebarItem`, `SortingOptions`

Other `Core/` subfolders: `Core/Brew/` (brew CLI services + `BrewPaths`, `Shell`, `Installation/`), `Core/Preferences/`, `Core/Infrastructure/` (`AlertManager`, `AppPaths`, `SendNotification`, `MirrorEnvironment`, `NetworkProxyManager`, …).

**CaskManager** (`Applite/Core/CaskCore/CaskManager.swift`)
- Thin `@Observable @MainActor` coordinator owning `dataLoader`, `registry`, `brewService`
- `categories: [CategoryLoadResult]` and `taps: [TapLoadResult]` populated after stage 1
- `isResolvingInstalledState: Bool` is true during stage 2 (brew CLI); `isRefreshingCatalog: Bool` is true during a `forceSync` reload
- "Is brew usable" has exactly one owner: `bootstrap.phase` (`HomebrewBootstrap.Phase`). `isBrewReady` / `needsSetupOverlay` derive from it, and a broken brew surfaces only as the setup overlay. Don't add a parallel flag — `CaskManager.hasBrokenInstall` and `BrokenInstallView` were removed for exactly that reason. A `BrewService` op that finds the path invalid calls `recoverBrew` (wired to `bootstrap.run()`) instead of reacting on its own
- `alert: AlertManager` is the **main window's one alert surface** — brew failures, catalog/load failures and view-raised errors all queue in it, and `ContentView` presents it once at the window root via `.alertManager(_:)`. Rule: **one manager per window, bound at that window's root**; never inside a repeated view (binding it per cask card was the F5/P3-5 bug). Alerts carry their own buttons (`AppAlert.Action`), so nothing hand-rolls `.alert`. Windows that can't see that root (Settings' `UninstallView`) own a local one
- `loadData(forceSync:)` is non-throwing — it path-validates, runs stage 1, then stage 2, surfacing any failure through `alert` (with Retry/Quit actions). The same entry point powers initial load, the ⌘R menu action, and the "Refresh Catalog" prompt in Settings
- Forwards install/uninstall/update to `BrewService`

**Brew services** (`Applite/Core/Brew/`)
- `BrewService` - Brew CLI operations; tracks `activeTasks: [ActiveBrewTask]`
- `InstalledCaskService` - Wraps `brew list --cask` and `brew outdated --cask` (the slow stage 2)

**Views** — split across `App/` (entry + `Commands`), `Navigation/` (shell), `Components/` (generic reusable views), `AppViews/` (the shared cask "app card" cluster), `Features/<Screen>/` (one folder per screen), and `Windows/` (standalone windows)
- `Navigation/` split into `ContentView` / `SidebarViews` / `DetailView`. `ContentView` is a `NavigationSplitView`; the detail closure picks `SearchView` (when `searchInput` is non-empty) or `DetailViews` (tab-driven), while a broken/installing brew is covered by the `ComponentsInstallView` overlay gated on `bootstrap.needsSetupOverlay`. The `.home` sidebar tab renders `DiscoverView` directly (no wrapper)
- `selection: SidebarItem?` is optional. Typing in the search field stashes the current selection into `lastSelection` and clears `selection` so a sidebar tap can interrupt the search; tapping a sidebar item while a search is active clears `searchInput`; clearing the search (Esc) restores `lastSelection`. Two `onChange` guards (`!searchInput.isEmpty` / `selection == nil`) keep the watchers from looping
- `Features/Search/SearchView` - Owns its own results state. Uses `.task(id: query)` with a 200ms `Task.sleep` for debounced live search; `ContentUnavailableView.search(text:)` for the empty state. Sort/filter are scoped here, not in ContentView
- `Features/Search/SortingOptionsToolbar` - Toolbar shared by SearchView (sort + hide-unpopular + hide-disabled toggles)
- `AppViews/` - App card display components (split across 8+ files). `AppliteAppView` (self-card in the installed list) reads the live app icon from `NSApplication.shared.applicationIconImage` so the new Icon Composer / Liquid Glass icon renders correctly
- `Features/Settings/SettingsView+BrewSettingsView` - Shows a single fixed-height "Refresh Catalog" prompt at the bottom whenever the brew-path option or the "Include Casks from Taps" toggle differs from the baselines captured `.onAppear`. The button calls `caskManager.loadData(forceSync: true)` and resets the baselines on success. The old "relaunch app" flow was replaced
- `Features/Bootstrap/` - `ComponentsInstallView` (the setup overlay) + `SetupStatusIcon`. Not an onboarding flow; it's a modal over the main window
- `App/Commands.swift` - Menu bar commands. "Refresh App Catalog" lives in the Applite menu (⌘R) and invokes `caskManager.loadData(forceSync: true)`

### External Data Sources

- Homebrew Cask API: `https://formulae.brew.sh/api/cask.json`
- Analytics API: `https://formulae.brew.sh/api/analytics/cask-install/365d.json`
- Custom taps via `brew ruby` script (`Applite/Resources/brew-tap-cask-info.rb`), invoked by `CaskDataLoader.fetchTapDTOs`. The script no-ops `Homebrew::Trust.require_trusted_cask!` so metadata loads from already-tapped repos on Brew 6+ without requiring `brew trust` (Applite only reads metadata; real `brew install` still honors trust). It also injects `tap` and `full_token` into each entry because `FromPathLoader`'s `to_h` leaves them `nil`

### Preferences

User settings stored via `@AppStorage` with keys defined in `Applite/Core/Preferences/Preferences.swift`.

## Dependencies

- **Sparkle** - Auto-updates
- **Kingfisher** - Async image loading/caching
- **GRDB.swift** - SQLite database
- **ButtonKit**, **SwiftUI-Shimmer** - UI components

## Code Patterns

- `@Observable` + `@MainActor` for view models and managers (macOS 14+)
- Async/await throughout; DB I/O uses GRDB's async API (`dbPool.read { ... }`/`.write { ... }`) — never block the main actor on disk
- Prefer SwiftUI built-ins over hand-rolled equivalents (e.g. `ContentUnavailableView`)
- Prefer Swift-native concurrency (e.g. `.task(id:)` for debounced cancellable work) over add-on packages where the native primitive suffices
- **One view struct per file**; do not split an owned type across multiple `Type+View.swift` extension files. Genuine extensions on *external/stdlib* types (`Array+`, `String+`, `URL+`, `View+Modify`) live in `Extensions/` and are fine. View helpers tightly coupled to a parent's `@State` stay as `private` computed properties/methods in the parent's own file (e.g. `AppView`'s `actionsView`), not as a struct or a separate extension file
- Two-stage data load: never block UI on `brew list --cask` / `brew outdated --cask`; let the registry update those flags reactively

## Contributing Notes

- For typos/minor bugs: PRs welcome directly
- For larger changes: Open issue or discuss on Discord first
- Project goal is simplicity for non-technical users; advanced features should not clutter main UI
