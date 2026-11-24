# Modifications

Solvane is a fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils)
(GPL-3.0-or-later, copyright 2026 Vorssaint). This file states the changes made
to the original, as GPL-3.0 section 5(a) asks. The branch `release/personal` of
this repository carries them. Original copyright notices and the `LICENSE` file
are kept unchanged.

Not affiliated with or endorsed by the original authors.

## Added features (2026)

- Mole cleanup with live progress and a terminal-style log.
- Command Code usage in the AI agent usage panel.
- Antigravity usage in the AI agent usage panel.
- Prayer times for Kemenag RI locations plus Makkah, Madinah and Jeddah, with an
  optional adhan (data and audio credits in `Resources/Prayer/NOTICE.txt`).

## Rebrand (November 2026)

Required by the original's `TRADEMARKS.md`, which asks forks to use their own
name, icon, bundle identifier, signing identity and update feed.

- Product name Vorssaint replaced by Solvane in user-visible strings, plist and
  `InfoPlist.strings` files (`Tools/rebrand.sh`, rerun after each upstream merge).
- Bundle identifier `com.itzmail.solvane`; fan helper plist renamed to match.
- New app icon and menu bar glyph (`Tools/MakeSolvaneIcon.swift`); the Vorssaint
  artwork is not used.
- In-app updater disabled; updates come through Homebrew.
- Screenshot and recording share links and the feedback form disabled, so the
  app never contacts the original maintainer's servers.
- About page links to this fork and to the original project; the copyright line
  credits the original.
- Swift identifiers, the SwiftPM target name and file names are left as upstream
  to keep merges small.
