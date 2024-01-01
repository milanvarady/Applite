#! /bin/ksh

# Add homebrew bin directories to path
typeset PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/Library/Application Support/Applite/homebrew/bin:${PATH}"

# Prompt user for password and return it
printf "%s\n" "SETOK OK" "SETCANCEL Cancel" "SETDESC Applite needs your admin password to complete the task" "SETPROMPT Enter Password:" "SETTITLE Applite Password Request" "GETPIN" | /usr/bin/env pinentry-mac --no-global-grab --timeout 60 | /usr/bin/awk '/^D / {print substr($0, index($0, $2))}'
