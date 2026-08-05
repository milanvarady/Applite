# Contributing to Applite

Contributions are welcome, and not only code. Bug reports, translations, and well-argued feature
suggestions are all useful.

## Table of Contents

1. [Project goal](#project-goal)
2. [Reporting a bug](#reporting-a-bug)
   - [Getting the terminal output](#getting-the-terminal-output)
   - [Getting logs from Console.app](#getting-logs-from-consoleapp)
3. [Suggesting a feature](#suggesting-a-feature)
4. [Contributing code](#contributing-code)
   - [Building](#building)
   - [Project layout](#project-layout)
   - [AI-assisted contributions](#ai-assisted-contributions)
5. [Contributing a translation](#contributing-a-translation)

## Project Goal

> Applite aims to be more of an app store for third-party apps than a full-blown Homebrew GUI
> wrapper.

The goal is to bring Homebrew casks to people who would never open a Terminal. Simple setup, a UI
that can be understood at a glance, no technical knowledge required.

Applite does have features aimed at experienced users, such as a custom brew path and a custom
installation directory. Those stay out of the main interface by design. This is the standard the
project measures suggestions against, and it is the usual reason something gets turned down.

## Reporting a Bug

Open an issue and include:

- What went wrong
- The steps you took before it happened
- Any error message or terminal output (see below)
- App version and hardware, for example "Applite 1.4, MacBook Air M2"

### Getting the terminal output

If the problem happened during an install, update, or uninstall, the app card itself will show a red
**Error** label with two buttons next to it. The terminal icon opens the full Homebrew output in a
new window. That output is the single most useful thing you can paste into an issue, so please
include it rather than only describing the failure.

<!-- TODO: screenshot of the failed-state app card, showing the Error label and terminal button -->

### Getting logs from Console.app

For anything that isn't a failed cask operation, the unified log is the next best source.

1. Open **Console.app** and select your device in the sidebar
2. Click **Start** to begin streaming
3. Reproduce the bug, then pause
4. Filter for the `dev.aerolite.Applite` subsystem, or search for "applite"
5. Copy the entries around the failure

If values show up as `<private>`, follow [this Stack Exchange
answer](https://superuser.com/questions/1532031/how-to-show-private-data-in-macos-unified-log/1532052#1532052)
to reveal them.

<!-- TODO: screenshot of Console.app filtered to the Applite subsystem -->

## Suggesting a Feature

- Open an issue, or a discussion if the idea is open-ended
- Describe what you're missing and why
- Suggesting a solution is optional

Check it against the [project goal](#project-goal) first. Features that would only make sense to
someone who already knows Homebrew are usually declined, however well built.

## Contributing Code

Small fixes need no ceremony. If you spot a typo or a minor bug, open a pull request.

For anything larger, open an issue or bring it up on the [Discord
server](https://discord.gg/MpDMH9cPbK) before you write the code. It is a bad experience for
everyone when a well-made PR gets turned down on scope, and a five-minute conversation up front
avoids it.

### Building

Open `Applite.xcodeproj` in Xcode 16 or newer and build. Swift Package Manager resolves the
dependencies on first build; there is nothing else to install. The deployment target is macOS 14.

### Project layout

The project uses Xcode 16 **file-system synchronized groups**, which means the folder structure on
disk *is* the project structure. To add, remove, move, or rename a source file, just do it on disk.
Xcode picks it up automatically.

Do not hand-edit `project.pbxproj` to manage files. It is not needed, and it produces merge
conflicts and broken references for no benefit.

The architecture is documented in [CLAUDE.md](../CLAUDE.md) at the repo root. It's written as context
for AI coding agents, which makes it terse, but it's the most current description of how the app fits
together and is worth reading before a larger change.

A few conventions that are easy to miss:

- `@Observable` and `@MainActor` for view models and managers. No Combine.
- Cask identity is `full_token` (`tap/token`) everywhere. The bare token is not unique across taps,
  since two taps can each ship a cask called `firefox`.
- Never block the UI on the brew CLI. Catalog data comes from SQLite first; installed and outdated
  state arrives afterwards and updates reactively.
- One view struct per file.

### AI-assisted contributions

I use AI assistance on this project myself, so it would be strange to forbid it here. Use whatever
tools you like.

What I ask is that you can explain and defend every line you submit, and that you have actually run
it. A PR whose author can't answer questions about it costs me more time to review than writing the
change myself, and that is the only kind I will close on sight.

## Contributing a Translation

Applite ships in English plus Hungarian, French, Japanese, Simplified Chinese, Traditional Chinese
(Hong Kong), and Turkish. Translation help is very welcome, both for new languages and for fixing
awkward wording in the existing ones.

Everything lives in a single String Catalog, `Localizable.xcstrings`, with English as the source
language. You can edit it directly in Xcode's catalog editor.

**Read [TRANSLATING.md](../TRANSLATING.md) first.** It is the glossary: the agreed rendering of the
terms that recur across the UI, plus the register each language uses, how buttons are phrased, and
the spacing rules. Consistency matters more than any single elegant sentence. An app feels broken
much faster when the same button is called three different things than it does from one awkward
phrase.

Maintenance scripts live in `Scripts/Localization/` and have [their own
README](../Scripts/Localization/README.md). You don't need them to submit a translation. If you're
adding new localized strings to the code, though, note that `xcodebuild` never writes new keys back
into the catalog. Only building inside Xcode does. `sync_catalog.py` exists to cover that gap.

One trap worth knowing: in a String Catalog an empty translation is not the same as a missing one. A
missing entry falls back to English, while an empty string renders as blank space in the UI. If you
don't have a translation for something, leave the entry out rather than filling it with `""`.
