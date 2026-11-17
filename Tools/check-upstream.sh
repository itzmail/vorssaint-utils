#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
#
# Reports whether the upstream Vorssaint has something newer than this fork,
# and what an update would touch. Read-only: it never changes the working
# tree, branches or the installed app. Needs `gh` (logged in), `git`, `jq`.
#
#   Tools/check-upstream.sh            human readable report
#   Tools/check-upstream.sh --quiet    only the RESULT line
#
# Exit codes: 0 up to date, 10 update available, 1 error.
# The last line is always `RESULT: UP_TO_DATE`, `RESULT: UPDATE_AVAILABLE` or
# `RESULT: ERROR <reason>`, so an agent can read it without parsing the rest.
#
# Environment:
#   VORSSAINT_UPSTREAM   owner/name of the original repository. Default: the
#                        parent GitHub reports for this fork.

set -uo pipefail

quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1

say() { [ "$quiet" -eq 1 ] || printf '%s\n' "$*"; }
fail() { printf 'RESULT: ERROR %s\n' "$1"; exit 1; }

for tool in gh git jq; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"
done

root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
cd "$root" || fail "cannot enter $root"

# The fork this checkout pushes to, and the repository it was forked from.
origin_url="$(git remote get-url origin 2>/dev/null)" || fail "no origin remote"
fork="$(printf '%s' "$origin_url" | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
upstream="${VORSSAINT_UPSTREAM:-}"
if [ -z "$upstream" ]; then
    upstream="$(gh repo view "$fork" --json parent --jq '.parent | if . then .owner.login + "/" + .name else empty end' 2>/dev/null)"
fi
[ -n "$upstream" ] || fail "cannot tell the upstream of $fork; set VORSSAINT_UPSTREAM=owner/name"
upstream_owner="${upstream%%/*}"

# Versions: the source tree, the installed app, and the newest stable release.
plist="Resources/Info.plist"
source_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist" 2>/dev/null)" \
    || fail "cannot read the version from $plist"
installed_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
    /Applications/Vorssaint.app/Contents/Info.plist 2>/dev/null || echo "not installed")"

latest_json="$(gh api "repos/$upstream/releases/latest" 2>/dev/null)" || fail "cannot read the latest release of $upstream"
latest_tag="$(printf '%s' "$latest_json" | jq -r '.tag_name')"
latest_version="${latest_tag#v}"
latest_date="$(printf '%s' "$latest_json" | jq -r '.published_at')"
latest_url="$(printf '%s' "$latest_json" | jq -r '.html_url')"

# Newer means a higher version, not a different one: a fork may be ahead on a beta.
newest="$(printf '%s\n%s\n' "$source_version" "$latest_version" | sort -V | tail -1)"
release_newer=0
[ "$latest_version" != "$source_version" ] && [ "$newest" = "$latest_version" ] && release_newer=1

# Upstream commits this fork's main does not have yet.
upstream_main_sha="$(gh api "repos/$upstream/commits/main" --jq '.sha' 2>/dev/null)" || fail "cannot read main of $upstream"
compare="$(gh api "repos/$fork/compare/main...$upstream_owner:main" 2>/dev/null)" \
    || fail "cannot compare $fork main with $upstream main"
behind="$(printf '%s' "$compare" | jq -r '.ahead_by')"
fork_only="$(printf '%s' "$compare" | jq -r '.behind_by')"

branch="$(git branch --show-current)"

say "Fork:        $fork"
say "Upstream:    $upstream"
say "Source:      $source_version  (Resources/Info.plist, branch $branch)"
say "Installed:   $installed_version"
say "Latest rel.: $latest_version  ($latest_date)"
say "              $latest_url"
say "Main:        fork main is $behind commit(s) behind and $fork_only ahead of upstream main (${upstream_main_sha:0:8})"

if [ "$behind" -gt 0 ]; then
    say ""
    say "Upstream commits not in fork main (newest first):"
    printf '%s' "$compare" | jq -r '.commits | reverse | .[] | "  " + (.sha[0:8]) + " " + (.commit.message | split("\n")[0])' |
        { [ "$quiet" -eq 1 ] && cat >/dev/null || head -40; }

    # Files upstream changed, against the files this branch already changed:
    # the overlap is where a merge or rebase will need care.
    upstream_files="$(printf '%s' "$compare" | jq -r '.files[].filename' | sort -u)"
    local_files="$(git diff --name-only "main...HEAD" 2>/dev/null | sort -u)"
    overlap="$(comm -12 <(printf '%s\n' "$upstream_files") <(printf '%s\n' "$local_files") | sed '/^$/d')"
    say ""
    say "Files upstream changed: $(printf '%s\n' "$upstream_files" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [ -n "$overlap" ]; then
        say "Also changed on $branch (expect conflicts here):"
        printf '%s\n' "$overlap" | sed 's/^/  /' | { [ "$quiet" -eq 1 ] && cat >/dev/null || cat; }
    else
        say "None of them overlap with the changes on $branch."
    fi
fi

if [ "$release_newer" -eq 1 ]; then
    say ""
    say "Release notes of $latest_tag:"
    printf '%s' "$latest_json" | jq -r '.body // ""' | head -60 | sed 's/^/  /' |
        { [ "$quiet" -eq 1 ] && cat >/dev/null || cat; }
fi

say ""
if [ "$release_newer" -eq 1 ] || [ "$behind" -gt 0 ]; then
    [ "$release_newer" -eq 1 ] && say "A newer release exists ($source_version -> $latest_version)."
    [ "$behind" -gt 0 ] && say "Upstream main has $behind commit(s) the fork lacks."
    echo "RESULT: UPDATE_AVAILABLE"
    exit 10
fi
echo "RESULT: UP_TO_DATE"
exit 0
