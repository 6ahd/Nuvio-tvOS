#!/bin/bash
# Move patches/legacy-tvos.patch to a new nuvio-native-legacy release.
# usage: tvos/rebase-legacy.sh v2.0.7
# Clean result: the patch is rewritten for the new tag. Conflicts: it stops in
# work/legacy-rebase with the files to fix (see UPDATING.md).
set -euo pipefail
NEW="${1:?usage: rebase-legacy.sh <new tag>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OLD="$(grep -oE 'LEGACY_TAG:-v[0-9.]+' "$REPO/tvos/prepare.sh" | cut -d- -f2)"
W="$REPO/work/legacy-rebase"
echo "legacy $OLD -> $NEW"
rm -rf "$W"; mkdir -p "$REPO/work"
git clone -q https://github.com/iqui27/nuvio-native-legacy.git "$W"
cd "$W"
G=(-c user.name=port -c user.email=port@localhost)
git checkout -q -b port-old "$OLD"
git apply --whitespace=nowarn "$REPO/patches/legacy-tvos.patch"
git add -A src && git "${G[@]}" commit -qm "tvOS port"
git checkout -q -b port-new "$NEW"
if git "${G[@]}" cherry-pick port-old >/dev/null 2>&1; then
  git diff "$NEW" HEAD -- src > "$REPO/patches/legacy-tvos.patch"
  sed -i.bak "s/LEGACY_TAG:-$OLD/LEGACY_TAG:-$NEW/" "$REPO/tvos/prepare.sh" && rm -f "$REPO/tvos/prepare.sh.bak"
  echo "clean: patch rewritten for $NEW, prepare.sh now uses $NEW. Build and test."
else
  echo "conflicts to fix in $W:"
  git diff --name-only --diff-filter=U
  echo "then: git add -A src && git -c core.editor=true cherry-pick --continue"
  echo "      git diff $NEW HEAD -- src > $REPO/patches/legacy-tvos.patch"
  exit 1
fi
