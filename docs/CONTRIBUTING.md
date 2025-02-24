# Applite Contribution Guide

## Table of Contents

1. [Project goal](#project-goal)
2. [If you found a bug](#if-you-found-a-bug)
   - [Finding logs in `Console.app`](#finding-logs-in-consoleapp)
3. [If you want to suggest a feature](#if-you-want-to-suggest-a-feature)
4. [If you want to contribute code](#if-you-want-to-contribute-code)


## Project Goal

> Applite aims to be more of an app store for third-party apps than a full-blown homebrew GUI wrapper.

The goal of Applite is to bring the convenience of Homebrew casks to the average user. It aims to be as simple as possible in every aspect. Easy setup, simple UI that can be understood at a glance, and no technical knowledge required.

Applite has features aimed at more experienced users (e.g. custom brew path and installation directory), but these are not part of the main interface by design.

## If you found a bug

> - Open a new issue 
> - Describe what the problem is
> - Describe the steps you took before it occurred
> - Include error messages, logs
> - Provide app version and device information (e.g. Applite: v1.2, MacBook Air M2)

If the problem is related to application actions, e.g. installing, updating, or uninstalling. Be sure to check if you can find the error message. When an app encounters an error it should look like this:

![Info button highlighted](https://i.imgur.com/Kik6s8q.jpg)

click on the info button to see the error.

### Finding logs in `Console.app`

If you are familiar with the console, you can check the Applite logs. Here is what you need to do:

- Click on your device in the `Console.app` 
- Click on the **Start** button to begin collecting logs
- After the bug has occurred pause log collection
- Filter for "applite" process in the search bar
- Look for the log entry that describes the error

![Console.app interface](https://i.imgur.com/04FHa9l.png)

If the command output is shown as `<private>`, as in the image above, follow [this stack exchange post](https://superuser.com/questions/1532031/how-to-show-private-data-in-macos-unified-log/1532052#1532052) to reveal it.

## If you want to suggest a feature

- Open a new issue, or a discussion if the feature is more open-ended
- Describe what you miss and why
- Optional: Suggest a solution

Your suggestion is likely to be rejected if it doesn't align with the [project goal](#project-goal).

## If you want to contribute code

> - If you find a typo or a minor bug, feel free to create a pull request right away
> - If you want to do something bigger, let's discuss it first, so you don't waste time on something that won't be accepted. Open a GitHub issue or join the [Official Discord Server](https://discord.gg/MpDMH9cPbK).

I'm open to all kinds of contributions!

This is my first project using Swift and SwiftUI, so the codebase isn't the cleanest. Feel free to contact me if you get lost in the code.
