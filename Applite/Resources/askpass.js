#!/usr/bin/env osascript -l JavaScript
//
// Applite askpass helper.
//
// Invoked by `sudo -A` (via the SUDO_ASKPASS env var set in Shell.swift) whenever a
// brew operation needs elevated privileges. It shows a password dialog and prints
// what the user types to stdout for sudo.
//
// The user types directly into this dialog, so the password never passes through
// Applite's own memory, arguments, or disk — it goes straight from here to sudo.
//
// The dialog shows Applite's icon so it's clear which app is asking. Applite writes
// its icon to its Application Support folder (see AskpassIcon.swift); we recompute
// that path here rather than reading an env var, because sudo sanitizes the askpass
// helper's environment. If the icon is missing for any reason we fall back to the
// system caution icon.

ObjC.import('stdlib')      // for $.exit
ObjC.import('Foundation')  // for the path + file-existence lookups below

const app = Application.currentApplication()
app.includeStandardAdditions = true

const appSupport = $.NSSearchPathForDirectoriesInDomains($.NSApplicationSupportDirectory, $.NSUserDomainMask, true).js[0].js
const iconPath = appSupport + '/Applite/prompt-icon.png'
const iconExists = $.NSFileManager.defaultManager.fileExistsAtPath(iconPath)

const options = {
  defaultAnswer: '',
  buttons: ['Cancel', 'OK'],
  defaultButton: 'OK',
  hiddenAnswer: true,
  withIcon: iconExists ? Path(iconPath) : 'caution',
}

try {
  const result = app.displayDialog(
    'Applite needs administrator privileges to continue.\n\nEnter your login password to allow it:',
    options
  )
  // Only reached when the user confirms — a button titled "Cancel" (and Esc) throws
  // instead of returning. The result is the script's stdout, which sudo reads.
  result.textReturned
} catch (e) {
  // User cancelled — exit non-zero so sudo aborts instead of retrying with a blank
  // password.
  $.exit(255)
}
