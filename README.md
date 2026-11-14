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
**Version History**, directly below Check for Updates in Settings, opens the
official GitHub release notes in your browser and remains available during checks.

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

App names stay in their human-readable form. Clicking a name or description, or
choosing **Get Info**, opens a details page inside the main window, not a popup.
The name and description show a pointing-hand cursor on hover.
Native Back navigation returns to the previous list or search. The page shows the
app's full name, description, available version, installation details, source,
links, download size when available, and deprecation/disablement information.
Detected apps also show their bundle location and non-Homebrew management status.
Loading and retryable errors stay on the page; Homebrew tokens remain selectable.
Cmd-click continues to open the app's website instead of the details page.

**Include Self-Updating Apps** is configured in **Settings > Apps > Homebrew Management**, not duplicated in the
Updates toolbar. Updates retains its refresh button and search.

Applite does not show itself in the app lists by default. Its update and uninstall
actions remain in the app menu and Settings. A default-off, internal developer
preference can restore the Installed self-card for diagnostics; see the
[diagnostic instructions](Testing/README.md#optional-applite-self-card).

## App settings

**Settings > Apps** groups managed-app preferences in one place:

- **App Catalog**: refresh frequency and third-party Homebrew taps.
- **Installed App Detection**: read-only discovery of external apps (on by default).
- **Installation Location**: the existing custom app-directory controls.
- **Homebrew Management**: opt-in management offers and self-updating-app updates.
- **Notifications**: successful/failed app installs and updates.
- **Advanced: App Management Source Overrides**: separate, default-off overrides
  for Microsoft Intune (Company Portal), Apple App Store, Setapp, and ArtCraft Launcher.

General retains appearance; Brew retains executable selection and Applite's own
Homebrew freshness. Updates still controls updates/version history for Applite
itself. Existing preferences keep their saved values and list/search toolbar
controls remain available.

Source overrides require both external detection and **Offer Manage with Homebrew**.
Enabling each override requires a warning confirmation; canceling changes nothing.
Only enable one if you are authorized to replace those apps: licenses, settings,
and future updates can be affected, and the original manager may reinstall them.
Overrides lift Applite's source guard only, not device enrollment, organizational
policies, license checks, or Homebrew eligibility/inventory requirements.

Each detected source must be overridden independently. Overriding Intune does not
silently override an App Store receipt, for example. Details retain all detected
sources, **Tracked by Homebrew**, and applicable **Source Overrides**. Installed
retains detected source filters; an overridden, Homebrew-tracked app can also
appear under Homebrew-managed. Adoption still previews the exact
command and warns about the overridden source(s).

Turning off detection or **Offer Manage with Homebrew** suspends every override
without forgetting saved choices. Disabling an override restores its protection
immediately, including pending confirmations and queued work; settings are checked
again after asynchronous metadata verification, before modifying commands start.
Already-running Homebrew commands are not undone. Unreadable/unsupported inventories
still block writes even when all source overrides have been enabled.

## App icons

Discovery caches and in-flight requests are isolated by effective proxy settings.
Unusable redirected pages use the final site's root favicon, and truncated comments,
scripts, or styles never expose their literal link/base text as metadata.

Favicon downloads pick up proxy preference changes without restarting Applite.
Discovery ignores comments/script/style contents before finding the head boundary,
uses the first base element with an href, and decodes numeric/named URL references.

Applite tries its normal CaskFlow icon first. If that image fails, it reads the
app's metadata homepage for declared favicon or Apple touch-icon links, then tries
the site's `/favicon.ico`. A letter tile remains the offline/failure fallback.
This applies to app cards and migration selection rows; working primary icons and
their caches are unchanged.

Website discovery happens only after a primary icon failure, not for the entire
catalog. It contacts the website directly (including any declared icon CDN),
without a third-party favicon lookup service, cookies, or stored credentials.
Discovery uses the configured proxy, reads at most 128 KiB of HTML, and caches
candidate URLs in memory for five minutes. Icon images use a separate Kingfisher
cache namespace. Website icons are a best-effort brand fallback, not necessarily
the app's own logo.

For example, the CaskFlow `copilot-cli.png` asset returned HTTP 404 when this fix
was verified; GitHub Docs declares a working favicon at a nonstandard asset path.

## Built With

Swift and SwiftUI, targeting macOS 14 so `@Observable` and `NavigationSplitView` are available without back-deployment shims. No Combine. The cask catalog is a local SQLite database (GRDB.swift, WAL mode) synced from the Homebrew JSON API, with FTS5 and BM25 ranking for full-catalog search. Loading is two-stage: SQLite paints the UI immediately, then `brew list --cask` and `brew outdated --cask` fill in installed and outdated state reactively, so nothing blocks on the brew CLI.

Architecture notes are in [CLAUDE.md](CLAUDE.md).

### Externally installed apps

Bulk imports skip apps already present outside the selected Homebrew; use the
single-app management confirmation instead. Disabling either management prerequisite
permanently invalidates open/queued confirmations until a new confirmation is made.
Receipt refreshes are bound to their selected Homebrew configuration and cannot
publish after it changes. Path edits debounce detection; superseded scans are canceled.

Install rechecks the expected app bundle before running, so an unfinished detection
scan cannot silently turn Install into Homebrew adoption. Adoption confirmation is
bound to the selected Homebrew and installation directory; changing either requires
a fresh confirmation, including for queued work. Detection drops superseded scans,
and a failed post-install refresh retains the command's output alongside its error.

**Settings > Apps > Installed App Detection > Detect externally installed apps** is enabled by
default. Turn it off to stop external-app scans and remove detected apps and
management offers from Installed. Homebrew-managed apps are
unaffected, and no apps are changed or removed. Turning it back on rescans locally;
no catalog download is required.

**Offer Manage with Homebrew**, under **Homebrew Management**, defaults to off when
no preference has been saved. Enable it to offer Homebrew management on external
app cards; otherwise, they show **Open** while detection, status, filters, and
counts remain available. Both settings must be enabled to offer management.
When detection is off, the management setting is greyed out and unavailable.
Its saved choice is preserved and respected when detection is re-enabled.
Disabling management also prevents an already-open confirmation from starting a reinstall.

Applite only manages Homebrew casks; an arbitrary app on disk, a formula, or a
matching display name does not make an app Homebrew-compatible. Unknown import
tokens are not offered as installable apps. Before every queued install/adoption,
update, reinstall, or bulk entry, Applite asks the selected Homebrew for fresh cask
metadata and requires one exact token/full-token/tap match with an enabled cask.
Missing, mismatched, disabled, malformed, or failed lookups block the modifying
command and expose the reason in Active Tasks. Existing ownership protection wins
before this check.

Each operation pins its Homebrew executable and app-directory configuration.
Ownership evidence is refreshed again after metadata verification, including
recorded Caskroom targets in previous custom app directories. Bulk operations
refresh shared inventories after all metadata requests, then make final override
decisions without yielding. Changing the selection invalidates pending writes.
Installed rows, search filtering, and totals use canonical bundle identities;
duplicate receipts stay intact, and single/bulk installs reconcile the projection.

Disabled/unavailable apps cannot offer adoption, installation, updates, or reinstall;
cards show **Homebrew unavailable** with an explanatory tooltip. Open/Get Info remain
available for local apps. **Refresh App Catalog** clears transient verification
errors so checks can be retried; disabled catalog entries stay blocked until their
metadata changes. A disabled or retired app already owned by Homebrew may still
be uninstalled to allow cleanup; external/protected apps cannot use that exception.
Deprecation alone does not mean disabled. These checks verify cask availability
and enabled state, not that vendor software will run correctly; Homebrew remains
responsible for its OS, architecture, dependency, and installer requirements.

Apps found in `/Applications`, `~/Applications`, their `Setapp` subfolders, or your custom app directory that are
not tracked by the selected Homebrew appear alongside managed apps in **Installed**.
Both use the simple **Installed** card status; Homebrew management remains a separate,
opt-in action, and only managed apps offer Homebrew uninstall/update operations. Detection uses
the cask's expected app bundle names (including renamed targets), with the display name
as a fallback when no app artifact is available. Non-app casks are not inferred from
package receipts or executables.

Use the **Installed** sidebar item or search-menu filter to find these apps.
Installed's **Sort & Filter** toolbar button offers A-to-Z (default), Z-to-A, and
download sorting; all, Homebrew-managed, Intune-managed, App Store-managed, Setapp-managed, ArtCraft-managed, or other
installed apps; and an updates-only filter. Other installed apps exclude Homebrew,
Intune, App Store, Setapp, and ArtCraft ownership. These choices are remembered separately from Search and Discover.
The menu shows matching/total counts and can reset sorting and filters; the
sidebar badge continues to show the full installed total.

The following source protections apply by default; only the explicitly confirmed
[source overrides](#app-settings) can relax their individual ownership guards.

App Store ownership takes precedence over Homebrew, including when Homebrew still has an old
receipt for the same app. A local `Contents/_MASReceipt/receipt` file identifies
these apps; the card shows a grey, disabled **App Store-managed** button instead of
offering Homebrew management. **Open** remains in the app's menu. Details show the
App Store source and bundle location, and Homebrew update lists exclude these apps.
All queued Homebrew installs, updates, reinstalls, uninstalls, and bulk operations
recheck for App Store receipts before writing. Protected apps report a blocked
action; eligible apps in mixed batches can still proceed.
These are local receipt-presence checks, not cryptographic receipt validation or
an App Store account lookup. Disabling external listings does not remove known
App Store protection or bypass the pre-write checks.

Microsoft Intune (Company Portal) ownership takes precedence over the App Store,
Setapp, ArtCraft Launcher, and Homebrew. Applite matches an installed bundle's exact `CFBundleIdentifier`
against the local Intune agent's per-app policy cache, opened **read-only**. Matching
apps show a grey, disabled **Intune-managed** button, retain Open/Get Info, and have
their own Installed source filter. Homebrew modifying actions are blocked, including
stale confirmations, imports, and protected entries in mixed batches.
Company Portal/agent presence alone never labels every app as managed. No cloud
sign-in, administrator privileges, agent changes, account data, or scripts are needed.

This is best-effort local detection using the agent's currently observed
`SideCar/sidecar.sqlite` app-policy schema, not a supported universal Intune inventory
API. It covers bundle IDs in that cache; script-only or native MDM/VPP deployments
without corresponding cache entries cannot reliably be identified as Intune-owned.
Independent App Store receipt protection still applies. Cached policies may remain
protective until Company Portal syncs. If the agent exists but its inventory is
missing, unreadable, malformed, or unsupported, Applite reports the error and blocks
Homebrew writes instead of assuming ownership is absent.
See Microsoft's [Intune agent troubleshooting](https://techcommunity.microsoft.com/blog/intunecustomersuccess/support-tip-troubleshooting-microsoft-intune-management-agent-on-macos/4431810)
for the distinction between agent app policies, bundle IDs, and script deployments.

Setapp distributions show a grey, disabled **Setapp-managed** button instead of
Homebrew management. Open/Get Info, source/location details, and a Setapp source
filter remain available; Homebrew Updates and modifying actions exclude these apps.
Detection checks the app's documented `-setapp` bundle-ID suffix or its main-bundle
`Contents/Resources/setappPublicKey.pem` file. The resource marker also covers builds
with older/nonstandard IDs. These are distribution-marker checks, not cryptographic
key validation or a check of your subscription/account. No key contents, license
data, or Setapp databases are read. Folder names, vendor names, and the Setapp client
being installed do not establish ownership.

Both standard Setapp installation folders are scanned: `/Applications/Setapp`
and `~/Applications/Setapp`. Setapp builds moved into another scanned folder
are still recognized by their bundle markers. The shared Spotlight-preview folder
`/Users/Shared/Apps/Setapp` is not added to scanning. As with other protected
sources, imports, stale confirmations, and queued/bulk writes recheck protection
even when external listings are disabled. Replacing a Setapp build with an unmarked
ordinary build clears Setapp ownership on refresh. Ownership priority is
**Intune > App Store > Setapp > ArtCraft Launcher > Homebrew**.
See Setapp's [bundle-ID requirements](https://docs.setapp.com/docs/set-an-app-bundle-id),
[public-key resource requirements](https://docs.setapp.com/docs/add-a-public-key-to-your-app-1),
and [installation locations](https://support.setapp.com/hc/en-us/articles/360002037440-Where-does-Setapp-store-its-files).

ArtCraft Launcher apps show a grey, disabled **ArtCraft-managed** button, retain
Open/Get Info, and have an Installed source filter. Applite reads only the current
user's `~/Library/Application Support/ArtCraft Launcher/installed.json` inventory,
matching existing macOS (`Dmg`) app-bundle records by canonical path. Exact recorded
paths also work outside the standard scan folders. Symlink aliases cannot bypass
ownership, and matching cask aliases still produce one Installed entry.
Homebrew adoption, installs/imports, updates, reinstall/removal, and bulk operations
recheck the inventory when they execute, even with external listings disabled.

This uses the launcher's installed-record format, verified against its
[v0.19.2 manifest](https://github.com/storytold/craft-launcher/blob/v0.19.2/crates/native/src/manifest.rs)
and [macOS installation behavior](https://github.com/storytold/craft-launcher/blob/v0.19.2/crates/native/src/install.rs).
Launcher presence, an app name, or a vendor bundle-ID prefix alone never establishes
ownership. A missing inventory means no recorded launcher ownership; an existing
unreadable, malformed, or unsupported inventory reports an error and blocks Homebrew
writes. Records are last-known evidence: replacing an app at the same recorded path
remains protected until the launcher record is removed or its source guard is explicitly overridden. Unrecorded/manual installs,
other users' inventories, and nonstandard/portable inventory locations are not
inferred. No launcher activation, token, settings, log, account data, or inventory
modification is needed.

Choose **Manage with Homebrew** on a card to review the exact command before continuing:
`brew install --cask <token> --force` (plus your custom app-directory option, if set).
This reinstalls the app so Homebrew can track its updates. A successful adoption refreshes
the managed state; a failed command preserves the previous state and exposes the full
Homebrew output, including stderr, from the card's terminal button.

The Installed badge counts visible managed and detected apps, excluding Applite.
If several casks match the same resolved app bundle (for example 1Password's stable,
beta, and nightly casks all declaring `1Password.app`), detection shows it once.
A Homebrew receipt takes precedence; otherwise, a supported official unversioned
cask is preferred deterministically. Bundle presence alone does not prove a release
channel. Separate app bundles remain separate, even when their display names match.
Alternative channels remain available in the catalog; no apps or cask records are deleted.

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
