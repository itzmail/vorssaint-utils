#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 itzmail
#
# Releases the Solvane fork: builds and signs the app, packages the DMG,
# publishes a GitHub release on the fork and bumps the Homebrew tap cask.
# Run from the release/personal branch, after merging upstream and re-running
# Tools/rebrand.sh. Tags look like <app version>-fork.<N>, e.g. 3.4.4-fork.2.
#
#   Tools/release-fork.sh 2             # build and package only, nothing published
#   Tools/release-fork.sh 2 --publish   # also create the release and update the tap
set -euo pipefail
cd "$(dirname "$0")/.."

FORK_REPO="itzmail/vorssaint-utils"
TAP_REPO="itzmail/homebrew-solvane"

N="${1:?usage: Tools/release-fork.sh <fork number> [--publish]}"
PUBLISH=0
[[ "${2:-}" == "--publish" ]] && PUBLISH=1

[[ "$(git branch --show-current)" == "release/personal" ]] || { echo "✗ run from release/personal" >&2; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "✗ commit your changes first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="$VERSION-fork.$N"
DMG="dist/Solvane-$VERSION.dmg"

if gh release view "$TAG" --repo "$FORK_REPO" >/dev/null 2>&1; then
    echo "✗ release $TAG already exists" >&2; exit 1
fi

echo "▸ Building Solvane $TAG"
./build.sh
codesign --verify --deep --strict build/stage/Solvane.app
codesign -dvv build/stage/Solvane.app 2>&1 | grep -q 'Authority=Solvane Signing' \
    || { echo "✗ not signed with the Solvane Signing identity; run Tools/setup-signing.sh" >&2; exit 1; }
build/stage/Solvane.app/Contents/MacOS/Solvane --selftest | tail -1

Tools/make-dmg.sh
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "▸ $DMG sha256 $SHA"

if (( ! PUBLISH )); then
    echo "Dry run: built $DMG, nothing published. Re-run with --publish."
    exit 0
fi

git push origin release/personal
gh release create "$TAG" "$DMG" --repo "$FORK_REPO" --target release/personal \
    --title "Solvane $TAG" \
    --notes "Unofficial fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils) based on $VERSION, with Mole, Command Code, Antigravity and Prayer times added. Not affiliated with or endorsed by the original authors. See MODIFICATIONS.md.

Install: \`brew tap itzmail/solvane && brew install --cask solvane\`, or \`brew upgrade --cask solvane\` to update."

TAP="$(mktemp -d)"
trap 'rm -rf "$TAP"' EXIT
gh repo clone "$TAP_REPO" "$TAP" -- -q
perl -i -pe "s/^  version \".*\"/  version \"$TAG\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/solvane.rb"
git -C "$TAP" commit -qam "[main] solvane $TAG"
git -C "$TAP" push -q origin main
echo "✓ Released $TAG. Friends update with: brew upgrade --cask solvane"
