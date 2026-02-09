# iCloud App History Sync

## Overview

Add an opt-in iCloud sync feature that tracks every app the user has ever installed via Applite. A new "App History" sidebar section shows previously installed apps that are not currently installed, enabling easy reinstallation on new or wiped machines.

## Approach

Use `NSUbiquitousKeyValueStore` (iCloud Key-Value Store) to sync a `Set<CaskId>` across devices. This is the simplest iCloud mechanism — no CloudKit container or schema needed, just an entitlement. The 1MB limit easily holds thousands of cask ID strings.

## Data Layer

### ICloudSyncManager

New file: `Utilities/ICloudSyncManager.swift`

- `@MainActor final class ICloudSyncManager: ObservableObject`
- Wraps `NSUbiquitousKeyValueStore.default`
- Storage key: `"previouslyInstalledCasks"`
- Serialization: JSON-encoded `[String]` array

**Published state:**
- `@Published var previouslyInstalledCaskIds: Set<CaskId>`

**Methods:**
- `addCask(_ id: CaskId)` — insert and write to store (no-op if sync disabled)
- `addCasks(_ ids: Set<CaskId>)` — bulk insert and write (no-op if sync disabled)
- `removeCask(_ id: CaskId)` — remove and write to store
- `clearAll()` — empty the set, write to store, remove from iCloud
- `sync()` — force read from store

**External change handling:**
- Subscribe to `NSUbiquitousKeyValueStore.didChangeExternallyNotification` on init
- On external change: merge remote set with local set (union) to avoid losing installs from concurrent syncs
- Respects `Preferences.iCloudSyncEnabled` — when off, does not write to the store

## Integration

### Automatic tracking (CaskManager)

1. **On data load** (`CaskManager+LoadData.swift`): After `loadData()` completes, call `iCloudSyncManager.addCasks()` with all currently installed cask IDs.

2. **On install** (`CaskManager+BrewFunctions.swift`): After a successful install action, call `iCloudSyncManager.addCask()` with the newly installed cask ID.

### Environment wiring (AppliteApp.swift)

- Create `ICloudSyncManager` as `@StateObject` in `AppliteApp`
- Pass as `.environmentObject(iCloudSyncManager)` alongside `caskManager`

## Sidebar

### SidebarItem enum

Add case: `.appHistory`

Place in sidebar between "Active Tasks" and "App Migration".

### Visibility

The "App History" sidebar item is hidden when:
- iCloud sync is disabled (`Preferences.iCloudSyncEnabled` is false), OR
- The filtered count is zero (all previously installed apps are currently installed)

Shows a badge with the count of apps available to reinstall.

## Detail View

### AppHistoryView

New file: `Views/Detail Views/AppHistoryView.swift`

- Reuses `AppView` cards (existing component) in a grid layout
- Filters `iCloudSyncManager.previouslyInstalledCaskIds` against `caskManager.installedCasks` to show only apps not currently installed
- Each card has a context menu with "Remove from History" calling `iCloudSyncManager.removeCask()`
- Resolves cask IDs to `Cask` objects via `caskManager.casks` dictionary; silently skips IDs that no longer exist in the catalog

## Settings

### General Settings tab (`SettingsView+GeneralSettings.swift`)

- **Toggle:** "Sync App History to iCloud" — backed by `@AppStorage(Preferences.iCloudSyncEnabled.rawValue)`, defaults to `false`
- **Clear All button:** Enabled only when toggle is on. Shows confirmation alert: "This will remove your app history from all devices. Are you sure?" On confirm, calls `iCloudSyncManager.clearAll()`
- When toggled on: immediately syncs currently installed apps to the store
- When toggled off: stops writing but does not delete existing iCloud data

### Preferences enum

Add case: `iCloudSyncEnabled`

## Entitlements

Add to both `Applite.entitlements` and `AppliteDebug.entitlements`:

```xml
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```

No other iCloud capabilities required.

## Files to create

| File | Description |
|------|-------------|
| `Utilities/ICloudSyncManager.swift` | iCloud KVS sync manager |
| `Views/Detail Views/AppHistoryView.swift` | App History detail view |

## Files to modify

| File | Change |
|------|--------|
| `Model/SidebarItem.swift` | Add `.appHistory` case |
| `Model/Preferences/Preferences.swift` | Add `iCloudSyncEnabled` case |
| `AppliteApp.swift` | Create and inject `ICloudSyncManager` |
| `Views/Content View/ContentView+SidebarViews.swift` | Add App History sidebar item |
| `Views/Content View/ContentView+DetailView.swift` | Add `.appHistory` detail case |
| `CaskManager+LoadData.swift` | Sync installed cask IDs after load |
| `CaskManager+BrewFunctions.swift` | Sync after successful install |
| `Views/Settings/SettingsView+GeneralSettings.swift` | Add toggle and clear button |
| `Applite.entitlements` | Add iCloud KVS entitlement |
| `AppliteDebug.entitlements` | Add iCloud KVS entitlement |
