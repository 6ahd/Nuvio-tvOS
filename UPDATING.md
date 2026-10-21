# Moving to a new nuvio-native-legacy release

All changes to the legacy code are one patch (`patches/legacy-tvos.patch`)
made against the tag in `tvos/prepare.sh` (`LEGACY_TAG`). The tvOS layer under
`tvos/` does not depend on the release.

## Steps

```sh
bash tvos/rebase-legacy.sh v2.0.7     # the new tag
bash tvos/ipa.sh                      # build, then test on the Apple TV
```

`rebase-legacy.sh` applies the patch to the old tag, replays it onto the new
one with git (three way, so upstream changes next to ours merge by themselves),
and rewrites the patch. When git cannot merge a spot it stops and lists the
files.

## Usual conflicts and how to solve them

* **`src/idioma_*.h` (translations).** Take the new release's files
  (`git checkout --ours src/idioma_*.h`), add our few strings back to
  `idioma_tab.h` in byte order, run `python3 tools/idiomas.py --sincronizar`,
  fill our strings' English text into the empty sibling entries, and check
  with `python3 tools/idiomas.py`.
* **`src/ajustes.c`, `ajustes.h`, `ajustes_ux_*.inc` (settings).** Upstream and
  we both append to the same lists. Keep both: upstream's lines first, ours
  (`AJ_PLAYER_APPLE`, `AJ_PLAYER_APPLE_LEG`) after, in every list (enum, OPCOES,
  CHAVE keys, defaults). Where a `case` line conflicts, use upstream's line and
  add our two cases to it.
* **`src/video.h`.** New functions declared in the Android sections are also
  seen by tvOS (`NV_ANDROID || NV_TVOS`). If the build fails at link time with
  a missing `video_*`, add it to `src/video_tvos.c` (usually a stub that
  returns 0).

Then check the guards: new upstream code under `#ifdef __APPLE__` means the
Mac development build, so on Apple TV it usually wants
`defined(__APPLE__) && !defined(NV_TVOS)`.

## Versions

The IPA shows the legacy version (`2.0.6`) plus the build number
`b<yymmddHHMM>`. Add a line to CHANGELOG.md for each release you publish.
