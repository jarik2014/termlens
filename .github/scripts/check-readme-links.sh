#!/usr/bin/env bash
# Every link in the markdown we ship, or hand a contributor, must point at
# something that exists.
#
# Two files are read, and the rules differ between them for a reason that is
# worth knowing before changing either half:
#
# * `README.md` is packaged. `crates/termlens/Cargo.toml` sets
#   `readme = "../../README.md"`, so crates.io renders it as the crate's
#   README and rewrites a *relative* link against the crate's directory in the
#   repository rather than the repository root -- `docs/DESIGN.md` became
#   `…/crates/termlens/docs/DESIGN.md`, and every one of the ten relative
#   links on the 0.10.2 page was a 404. Nothing in this repository could see
#   it, because the same file renders correctly on GitHub, where it *is* at
#   the root. So absolute links only, and that rule applies to `README.md`
#   alone.
# * `CONTRIBUTING.md` is not packaged and legitimately uses relative links
#   (`AGENTS.md`, `docs/RELEASING.md`, `.github/workflows/ci.yml`), so for it
#   the relative form is fine. The target still has to exist, and until #352
#   no file checked that.
#
# So each file gets the rule that generalises -- an in-repo target names a path
# that is really here -- and only the packaged one gets the absolute-only rule
# on top. Relative links are resolved against the repository root, which is
# where both files live.
#
# The other half is a URL naming no in-repo path at all: #351 shipped
# `…/vyncint/temlens/…` (one letter short) into `CONTRIBUTING.md` and all
# sixteen checks reported success. The org is asserted against the list below
# rather than asked over the network, deliberately: a link checker that asks
# GitHub is online, flaky, and can report a 200 for the wrong reason, which is
# the failure mode this script exists to avoid. `temlens` is not in the list.
#
# Usage: check-readme-links.sh [file ...]   (default: README.md)
set -euo pipefail

base="https://github.com/vyncint/termlens/blob/main/"

# Repositories that exist in the vyncint org: the four that share this
# contributor pattern. A `github.com/vyncint/<anything else>` link is a typo or
# a repository that moved, and either way it is a dead end for a reader.
known_repos="launchbound mossaic reconverge termlens"

files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
  files=(README.md)
fi

root=$(cd "$(dirname "$0")/../.." && pwd)
status=0
total=0

for file in "${files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "LINK GATE: \"$file\" is not a file" >&2
    status=1
    continue
  fi

  # Only the packaged README may not use relative links.
  absolute_only=no
  if [ "${file##*/}" = "README.md" ]; then
    absolute_only=yes
  fi

  checked=0
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    checked=$((checked + 1))
    case "$link" in
      '' | '#'* | mailto:*)
        ;;
      http://* | https://*)
        case "$link" in
          "$base"*)
            path=${link#"$base"}
            path=${path%%#*}
            if [ ! -e "$root/$path" ]; then
              echo "$file LINK: \"$path\" is linked but not in the repository" >&2
              status=1
            fi
            ;;
          */github.com/vyncint/*)
            rest=${link#*github.com/vyncint/}
            repo=${rest%%[/?#]*}
            known=no
            for candidate in $known_repos; do
              if [ "$repo" = "$candidate" ]; then
                known=yes
              fi
            done
            if [ "$known" = no ]; then
              echo "$file LINK: github.com/vyncint/$repo names no repository in the org" >&2
              status=1
            fi
            ;;
        esac
        ;;
      *)
        if [ "$absolute_only" = yes ]; then
          echo "README LINK: relative target \"$link\" — crates.io rewrites it against" >&2
          echo "  crates/termlens/, where it does not exist. Use ${base}${link}" >&2
          status=1
        else
          path=${link%%#*}
          path=${path%%\?*}
          if [ ! -e "$root/$path" ]; then
            echo "$file LINK: \"$link\" is linked but not in the repository" >&2
            status=1
          fi
        fi
        ;;
    esac
  done <<<"$(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\(//; s/\)$//' | sort -u || true)"

  total=$((total + checked))
  echo "$file: $checked distinct link target(s)"
done

if [ "$status" -eq 0 ]; then
  echo "markdown links: $total target(s) across ${#files[@]} file(s), every in-repo target present"
fi
exit "$status"
