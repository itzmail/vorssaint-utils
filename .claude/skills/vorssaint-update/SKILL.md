---
name: vorssaint-update
description: Check whether the upstream Vorssaint has a newer release or new commits than this fork, and plan how to bring the fork and the installed app up to date. Use when the user asks about a new Vorssaint version, an upstream update, syncing the fork, or updating the installed app.
---

# Vorssaint upstream update

This repository is a fork. The original lives upstream (GitHub reports it as the
fork's parent). Run the checker first; it is read-only.

```bash
Tools/check-upstream.sh          # full report
Tools/check-upstream.sh --quiet  # RESULT line only
```

The last line is `RESULT: UP_TO_DATE` (exit 0), `RESULT: UPDATE_AVAILABLE`
(exit 10) or `RESULT: ERROR <reason>` (exit 1).

## If up to date

Say so in one line with the installed, source and latest release versions. Stop.

## If an update is available

Report, from the checker's output:
1. Installed, source and latest release versions.
2. The upstream commits the fork's `main` lacks, and the release notes.
3. The overlap list: files upstream changed that the current branch also
   changed. These are where a merge or rebase needs care. The files that
   usually collide in this fork are `CHANGELOG.md`, `Resources/Info.plist`,
   `Sources/Vorssaint/Core/Defaults.swift`, `FeatureCatalog.swift`,
   `FeaturePresets.swift`, `SettingsDirectory.swift`, `Tests/generate_sources.py`.

Then propose a plan and WAIT for the user's approval. Do not merge, rebase,
build or install on your own. A typical plan:

1. Add the `upstream` remote if missing: `git remote add upstream https://github.com/<owner>/<name>.git`.
2. `git fetch upstream`; fast-forward the fork's `main` to `upstream/main` (it carries no fork-only commits).
3. Update each feature branch onto the new `main` (merge, as this fork's
   history already merges branches), resolving the overlap files above. Keep
   both sides in registries (`Defaults`, `FeatureCatalog`, `FeaturePresets`,
   `generate_sources.py`); the changelog keeps upstream's released sections and
   the fork's entries under `[Unreleased]`.
4. Run the full suite: `./build.sh --test`. Fix what the merge broke, test-first.
5. `./build.sh --install` replaces `/Applications/Vorssaint.app`; ask first.
6. Never push or open a PR unless asked.

## Notes

- A newer version means a higher version number; a fork ahead on a beta is not "behind".
- The checker needs `gh` logged in, `git` and `jq`. Set `VORSSAINT_UPSTREAM=owner/name` if GitHub cannot report the parent.
- Commit messages follow `[branch-name] short description`.
