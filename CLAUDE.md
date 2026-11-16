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

Before creating `CaskManager`, `AppliteApp.init` acquires `SingleInstanceLock` in the
per-user application-support directory. Repeat launches reopen the existing copy
and exit before database, Homebrew, or Sparkle initialization. The lock uses
nonblocking `flock`, is close-on-exec, and is never unlinked; the OS releases it on
exit. Startup/handoff failures are logged and shown with a native alert because
the normal window alert manager does not exist yet.

The main scene is a singleton `Window` with ID `main`. `MainWindowView` supplies
the delegate's reopen callback using its scene's `openWindow` action, so reopening
the app can restore its main window even while Settings is the only visible window.
Terminal output keeps its auxiliary window group. App information is a main-window
navigation destination, not a separate scene.

Self-uninstall has one destination: Settings' Uninstall pane. `SettingsNavigation`
owns the selected pane; the app menu and self-card select it before calling the
native `openSettings` action, which reuses the Settings window. There is no separate
`uninstall-self` scene.
The app menu's update-check action uses the same navigation model to select Updates
and focus Settings before invoking the existing updater; its busy-state gate stays intact.
`ContentView` lays out `AppStatusBar` below the navigation area in a vertical stack,
with a 16-point gap below the split view so scrollable panes and the sidebar do not
run into the bar. The setup overlay remains above the navigation area. The bar reads
existing bootstrap/catalog/installed-state/task/batch state; `AppStatusSummary` is
an ephemeral presentation snapshot, not another progress owner. Refresh calls the
existing forced reload and Tasks uses `requestedTab` so search is cleared normally.
Failed rows are not busy; download fractions and batch counts are real, while
catalog refresh remains indeterminate. Footer actions respect setup/loading and
the view's Homebrew-maintenance lockout.

1. **App Launch**: `ContentView.task(id: bootstrap.attempt)` calls `caskManager.bootstrapAndLoad()`
2. **First Run**: `HomebrewBootstrap` installs/validates brew; while `bootstrap.needsSetupOverlay` is true, `ContentView` covers the window with the non-dismissable `ComponentsInstallView` modal (`Features/Bootstrap/`). There is no separate onboarding flow — the app opens straight into the main UI
3. **Main UI**: `ContentView` with `NavigationSplitView` sidebar navigation
4. **Data Loading**: `CaskManager.loadData()` runs in two stages — catalog (DB-only, instant) then brew CLI state (slow). The UI lights up after stage 1; installed/outdated state arrives reactively as stage 2 completes.

### Key Components

The shared cask/brew engine lives under `Applite/Core/`, split into focused subfolders:

**Persistence** (`Applite/Core/Database/`)
- `AppDatabase` - Schema migrations, DatabasePool with WAL mode, FTS5 virtual table on `casks`
- `CaskRecord` - GRDB `FetchableRecord`/`PersistableRecord`, decodes from `CaskDTO`; persists expected app bundle names from cask artifacts
- `CaskDatabaseService` - CRUD, FTS5 search (async), API sync

**Cask engine** (`Applite/Core/CaskCore/`) — the `@Observable` runtime layer
- `CaskViewModel` - `@Observable @MainActor` view model wrapping `CaskRecord` with runtime state (`isInstalled`, `externalAppURL`, `isOutdated`, `progressState`). `isInstalled` remains Homebrew-managed only; `installationState` distinguishes `.installed`, `.externalInstalled`, and `.notInstalled`, with managed state taking precedence
- `CaskViewModelRegistry` - Single-identity store; `viewModels(for:)` is get-or-create so the same cask shares one VM across views. **Identity is `fullToken` everywhere** — DB primary key, registry key, brew ops. The bare `token` is not unique (two taps can each ship a "firefox"), so it must never key anything; it's indexed for lookup only
- `CaskDataLoader` - Orchestrates: `loadCatalogData()` (DB-only), `refreshInstalled()`/`refreshOutdated()` (brew CLI), `search(query:)` (FTS5). Defines `CategoryLoadResult` and `TapLoadResult`.
- `CaskWarning` - Warning enum (deprecated/disabled/caveat)
- `ExternalAppDetector` - Disk-only detection using artifact bundle names, or display-name fallback, in the configured app directory, `/Applications`, `~/Applications`, and the two standard `Setapp` subfolders. `installations` assigns each resolved bundle path once: managed ownership first, then supported official unversioned casks, then full-token tie-break. Applite is excluded; distinct bundle paths remain distinct. `refreshInstalled()` scans the entire catalog off the main actor.
- `ExternalAppDetector.ScanResult` also carries Intune/App Store URLs. App Store evidence is a local `Contents/_MASReceipt/receipt` file (not sandbox receipts or cryptographic validation). `IntuneAppDetector` opens the agent's SideCar SQLite cache read-only using GRDB, selecting only primary/AppInfos bundle-ID fields from app-policy records, never scripts, credentials, or account details. Exact bundle-ID matches are required; agent presence alone does not imply per-app ownership. This observed, undocumented schema is best-effort (native MDM/VPP or script-only apps without cache entries aren't covered); unknown/unreadable schemas fail closed for writes.
- `ExternalAppDetector` also identifies Setapp distributions from the documented `-setapp` bundle-ID suffix or a main-bundle `Contents/Resources/setappPublicKey.pem` file (presence only, not key/subscription validation). Do not infer ownership from a vendor, folder name, client install, or SDK framework alone. `InstalledAppLocator.bundleIdentifier(at:)` shares fresh plist decoding with Intune; no `Bundle` metadata caching, so queued operations see replaced bundles. Missing plists return nil; malformed/unreadable metadata propagates as an error. Do not scan Setapp's shared Spotlight-preview folder.
- `ArtCraftAppDetector` reads only the current user's `ArtCraft Launcher/installed.json` manifest (`apps` records' `kind`/`path`, verified with launcher v0.19.2). Existing `Dmg` `.app` records establish canonical-path ownership; not a vendor/name/client-presence heuristic. Recorded paths can supplement scan candidates outside standard roots without scanning unrelated folders. Missing inventory means no records; unreadable/malformed/unsupported data fails closed for writes. Records are last-known evidence and cannot distinguish an unrelated replacement at the same path. Do not read the instance token, account/settings files, or logs. Other users' and portable inventories aren't covered.
- `ProtectedAppInstallation` retains all detected source URLs, with primary priority Intune > App Store > Setapp > ArtCraft Launcher. Scan results and the registry preserve secondary source evidence too: overriding one source must not waive another. `CaskViewModel.isInstalled` preserves raw brew receipts and detected source filters/details retain provenance. `managementProtection` excludes only explicitly enabled source overrides from the evidence; `isManagementProtected` means an effective guard remains. Known ownership survives clearing external listings. `BrewService` refreshes ownership off-main at queued single/bulk execution, even for imports or disabled detection, then reads current override preferences again after metadata awaits, before mutations. A batch shares fresh Intune/ArtCraft inventory snapshots. Failed inventories always block, even with overrides enabled. Isolated tests inject fixture loaders, never real management data.
- Source override preferences default false individually and are effective only while both detection and management offers are enabled. `CaskManager.requestManagementSourceOverride` confirms before persisting an enable (through the calling window's alert), rechecks prerequisites on confirmation, and disables immediately. Settings synchronizes observable VM override snapshots through the registry and refreshes outdated state on the serial queue when ready; unchanged snapshots avoid duplicate refreshes. Backend checks always read live preferences, not cached VM permission. Overrides never remove source evidence, edit inventories, bypass Homebrew eligibility, or alter OS enrollment/licensing policies.
- Homebrew eligibility is independent of ownership: `homebrewManagementBlockReason` combines catalog disablement and the last failed metadata check. `BrewService` reuses `getAdditionalInfoForCask` (30-second bound), requiring exactly one token/full-token/tap match from the selected brew before queued install/adopt/update/reinstall or each eligible bulk entry. Missing/disabled/mismatched/malformed/failed metadata blocks writes through normal task failures. Protected-source checks run first. Actual Homebrew-owned uninstall is intentionally exempt from availability/disablement so retired casks remain removable; external uninstall is blocked. Cask requirements remain Homebrew's responsibility, not a local OS/architecture guess.
- Cards retain Open/Get Info for local unsupported apps, show a disabled Homebrew unavailable action instead of install/adopt/update, and disable reinstall. Unsupported casks are excluded from actionable outdated lists/counts. Catalog reload clears transient `homebrewManagementError` values, not disablement. Search/get-or-create must not clear those errors as a side effect. Do not synthesize installable casks from arbitrary app names or non-cask imports.
- `Preferences.detectExternallyInstalledApps` defaults to true. Settings > Apps > Installed App Detection clears external runtime state and suspends overrides immediately when disabled; Installed then contains only managed apps. Enabling rescans locally. Scan-result application and adoption confirmation reject stale in-flight work.
- `Preferences.offerHomebrewManagement` defaults to false (opt-in), preserving saved choices. Settings > Apps > Homebrew Management disables the control when detection is off without overwriting its saved value. Both preferences are required for offers and source overrides. Disabling management preserves external detection/status/counts, suspends all overrides, and blocks pending adoption. All four advanced overrides default false; no separate source-store installer or enrollment bypass is introduced.
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
- `confirmAdoption(_:)` uses the root alert to preview and confirm `brew install --cask <fullToken> --force`, then refreshes installed state inside the serialized operation on success. Failures retain external state and expose stderr through the existing card/Active Tasks error surface

**Brew services** (`Applite/Core/Brew/`)
- `BrewService` - Brew CLI operations; tracks `activeTasks: [ActiveBrewTask]`
- `InstalledCaskService` - Wraps `brew list --cask` and `brew outdated --cask` (the slow stage 2)

**Views** — split across `App/` (entry + `Commands`), `Navigation/` (shell), `Components/` (generic reusable views), `AppViews/` (the shared cask "app card" cluster), `Features/<Screen>/` (one folder per screen), and `Windows/` (standalone windows)
- `Navigation/` split into `ContentView` / `SidebarViews` / `DetailView`. `ContentView` is a `NavigationSplitView`; the detail closure picks `SearchView` (when `searchInput` is non-empty) or `DetailViews` (tab-driven), while a broken/installing brew is covered by the `ComponentsInstallView` overlay gated on `bootstrap.needsSetupOverlay`. The `.home` sidebar tab renders `DiscoverView` directly (no wrapper)
- `selection: SidebarItem?` is optional. Typing in the search field stashes the current selection into `lastSelection` and clears `selection` so a sidebar tap can interrupt the search; tapping a sidebar item while a search is active clears `searchInput`; clearing the search (Esc) restores `lastSelection`. Two `onChange` guards (`!searchInput.isEmpty` / `selection == nil`) keep the watchers from looping
- `Features/Search/SearchView` - Owns its own results state. Uses a task keyed by query and Installed filter with a 200ms `Task.sleep` for debounced live search. Installed filtering includes managed and detected apps reactively and searches beyond the usual 50-result limit. Sort/filter are scoped here, not in ContentView
- `Features/Search/SortingOptionsToolbar` - SearchView toolbar (sort + hide-unpopular + hide-disabled + Installed toggles). The single Installed destination and badge use `locallyInstalledViewModels` / `locallyInstalledCount`, excluding Applite; `installedViewModels` remains managed-only for Homebrew operations and exports. Card status is Installed for either state; management actions still depend on the underlying state.
- `Features/Installed/InstalledView` owns a Sort & Filter toolbar menu. `InstalledListOptions` combines its local search, source/update filters, and friendly-name/download sorting with deterministic full-token tie-breaks. `installedSortOption`, `installedSourceFilter`, and `installedUpdatesOnly` persist independently of Search/Discover; defaults are A to Z, all sources, and no update restriction. Empty filtered results offer Show All; the menu shows matching/total counts without changing the sidebar badge.
- `AppViews/` - App card display components (split across 8+ files). `AppliteAppView` is a diagnostic-only Installed self-card gated by `Preferences.showAppliteInInstalledList` (default false, no Settings control). It reads the live app icon from `NSApplication.shared.applicationIconImage` so the new Icon Composer / Liquid Glass icon renders correctly. Normal update/uninstall entry points remain in the menu and Settings.
- App-name/description clicks and Get Info share `AppView.showInfo`, which sets `CaskManager.selectedAppDetails`. `ContentView` binds it to a native `NavigationStack` destination; Back restores the source list/search, and changing sidebar/search clears the destination. `Features/AppDetails/AppDetailsView` owns cancellable metadata/download-size loading and inline errors with Retry; the Cask Info window scene is removed. Names always use `cask.name`; Cmd-click still opens the homepage. `CaskAdditionalInfo` keeps optional name/description/available-version metadata compatible with older responses.
- Installed details independently read fresh bundle plist, localization directories and unverified signing identity off-main, preferring the detected protected/external path. Homebrew errors do not hide local facts. Update status is Unknown for external/protected installations, self-updating casks, placeholders, or missing Homebrew version/status fields; do not compare a foreign distribution with a cask version. Signing identity is explicitly unverified.
- `Features/Settings/AppSettingsView` groups catalog frequency/taps, detection, installation directory, management/greedy updates, install/update notifications, and advanced source overrides in the Apps tab. General retains appearance; Brew retains executable/annex freshness; Updates manages Applite itself. Apps owns its tap-change refresh prompt; Brew owns the brew-path prompt. Each uses the Settings root alert and `loadData(forceSync: true)`, clearing its baseline only on success. Existing preference keys/defaults remain stable; no restart is needed.
- `Features/Bootstrap/` - `ComponentsInstallView` (the setup overlay) + `SetupStatusIcon`. Not an onboarding flow; it's a modal over the main window
- `App/Commands.swift` - Menu bar commands. "Refresh App Catalog" lives in the Applite menu (⌘R) and invokes `caskManager.loadData(forceSync: true)`

### External Data Sources

- Homebrew Cask API: `https://formulae.brew.sh/api/cask.json`
- Analytics API: `https://formulae.brew.sh/api/analytics/cask-install/365d.json`
- App icons: CaskFlow via jsDelivr first, then `AppIconView` lazily asks `FaviconResolver` for metadata-homepage icon links and `/favicon.ico`. Discovery is bounded to 128 KiB, coalesced, and cached for five minutes (maximum 256 pages); image candidates are limited to three declared links plus the root fallback. Website requests respect proxies and omit cookies/credentials. Kingfisher caches favicon images separately from primary app icons; the deterministic monogram remains the last resort.
- Release notes: opening app details looks up the selected cask's exact Homebrew version on GitHub when its homepage or release-download URL identifies a repository. Requests respect proxies, omit cookies/credentials, limit responses, and never query the installed-app inventory. Unmatched releases offer only a clearly labeled history link; network failures are shown inline.
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
