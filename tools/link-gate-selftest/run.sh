#!/usr/bin/env bash
# Proves the markdown link gate can fail, before it is trusted to pass (#352).
#
# Each fixture models one way a link rots, and the gate is asserted to notice:
#
#   contributing-good/       what CONTRIBUTING.md legitimately does — relative
#                            links, an org link, a fragment, an external site
#   contributing-missing/    a relative link to a target that was renamed away
#   contributing-typo-org/   #351's `…/vyncint/temlens/…`, one letter short
#   readme-relative/         the packaged README with a relative target, which
#                            crates.io resolves against the crate directory
#   readme-missing/          the packaged README with a dead absolute target
#
# The first and the last assertions are the ones that keep the gate honest: a
# fixture that must pass, and the repository's own two files, which must still
# pass. Usage: tools/link-gate-selftest/run.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
root="$(cd ../.. && pwd)"
gate="$root/.github/scripts/check-readme-links.sh"
status=0

# `<label> <expected: zero|nonzero> <file ...>`
expect() {
  label=$1
  want=$2
  shift 2
  got=0
  "$gate" "$@" > out.log 2>&1 || got=$?
  case "$want:$got" in
    zero:0 | nonzero:[1-9]*)
      printf '  ok    %-58s exit %s\n' "$label" "$got" ;;
    *)
      printf '  FAIL  %-58s exit %s, expected %s\n' "$label" "$got" "$want" >&2
      sed 's/^/        /' out.log >&2
      status=1 ;;
  esac
}

expect "CONTRIBUTING.md: relative links, org link, fragment, external" zero contributing-good/CONTRIBUTING.md
expect "CONTRIBUTING.md: a deleted in-repo target fails" nonzero contributing-missing/CONTRIBUTING.md
expect "CONTRIBUTING.md: a misspelled org repository fails (#351)" nonzero contributing-typo-org/CONTRIBUTING.md
expect "README.md: a relative target fails (crates.io rewrites it)" nonzero readme-relative/README.md
expect "README.md: a missing absolute target fails" nonzero readme-missing/README.md
expect "this repository's own two files pass" zero "$root/README.md" "$root/CONTRIBUTING.md"

rm -f out.log
if [ "$status" -eq 0 ]; then
  echo "link gate selftest: 6 expectation(s), the gate fails when it should"
fi
exit "$status"
