#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
#
# Fork rebrand: renames the user-visible product name "Vorssaint" to the fork's
# name inside Swift string literals and the bundle's plist/strings files, as
# TRADEMARKS.md requires of redistributed builds. Identifiers, file names, the
# SwiftPM target and every copyright notice are left alone so upstream merges
# stay small and the original authorship stays visible.
#
# Idempotent: run it again after each upstream merge. Dry run by default.
#   Tools/rebrand.sh            # report what would change
#   Tools/rebrand.sh --apply    # rewrite files in place
set -euo pipefail
cd "$(dirname "$0")/.."

BRAND="${REBRAND_NAME:-Solvane}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

export BRAND APPLY
# Swift: replace the word only inside string literals (single-line ones and the
# bodies of multi-line ones). Comments, identifiers and copyright strings stay.
# Plist and .strings files: every occurrence except the copyright line.
# BundleMigration renames upstream's pre-3.x "Vorssaint Utils.app" bundle, a
# path this fork never shipped, so its names must stay exactly as upstream's.
swift_files=("${(@f)$(find Sources -name '*.swift' ! -name 'BundleMigration.swift')}")
strings_files=("${(@f)$(find Resources -name 'InfoPlist.strings')}")
plist_files=(Resources/Info.plist)

perl -i.rebrand-bak -ne '
    BEGIN { our $in_block = 0; our $count = 0; }
    my $brand = $ENV{BRAND};
    my $line = $_;
    # The release boilerplate line matches the upstream GitHub release text
    # and must stay verbatim.
    my $is_comment = $line =~ m{^\s*//} || $line =~ /Signed with an Apple Developer ID/;
    my $triples = () = $line =~ /"""/g;
    my $starts_in_block = $in_block;
    if (!$is_comment) {
        if ($starts_in_block && $triples == 0) {
            # Whole line is literal text.
            $line =~ s/\bVorssaint\b/$brand/g unless $line =~ /©|Copyright/;
        } else {
            $line =~ s{("(?:[^"\\]|\\.)*")}{
                my $lit = $1;
                $lit =~ /©|Copyright/ ? $lit : do { (my $c = $lit) =~ s/\bVorssaint\b/$brand/g; $c };
            }ge;
        }
    }
    $in_block = !$in_block if $triples % 2 == 1;
    $count++ if $line ne $_;
    print $line;
    END { print STDERR "$ARGV changed=$count\n" if 0; }
' "${swift_files[@]}" 2>/dev/null || true

# The in-place pass above already wrote the files; keep a report, and either
# keep (apply) or restore (dry run) from the backups it left behind.
changed=0
for f in "${swift_files[@]}"; do
    bak="$f.rebrand-bak"
    [[ -f "$bak" ]] || continue
    if ! cmp -s "$f" "$bak"; then
        n=$(diff "$bak" "$f" | grep -c '^>' || true)
        changed=$((changed + 1))
        (( APPLY )) || echo "would change $n line(s): $f"
    fi
    (( APPLY )) || mv "$bak" "$f"
    (( APPLY )) && rm -f "$bak"
done

for f in "${strings_files[@]}" "${plist_files[@]}"; do
    [[ -f "$f" ]] || continue
    pending=$(grep '\bVorssaint\b' "$f" | grep -vc '©\|Copyright' || true)
    if (( pending > 0 )); then
        changed=$((changed + 1))
        if (( APPLY )); then
            perl -i -pe 'BEGIN{$b=$ENV{BRAND}} s/\bVorssaint\b/$b/g unless /©|Copyright/' "$f"
        else
            echo "would change $pending line(s): $f"
        fi
    fi
done

echo "files affected: $changed ($( (( APPLY )) && echo applied || echo 'dry run, nothing written'))"
