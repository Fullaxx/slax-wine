# `notepadpp` — the swappable application layer

**Status: boot-verified** — the bundle builds, ships the verified installer plus its launcher, and
the ISO booted under TCG to `slax login:` with `30-notepadpp.sb` mounted. **Running the installer
under Wine is not yet verified** — that is the `runtime-verified` rung, and the acceptance test for
this whole project.

```sh
./build.sh
```

One bundle, deliberately separable: this is the layer a games variant replaces.

## Numbering is the mechanism, not a convention

Load order is the numeric prefix, higher wins, and `union_append_bundles` inserts each bundle at aufs
branch index 1 so each arrival outranks the last. Delete `30-notepadpp.sb` from `/slax/modules/` on a
stick and drop another `30-*.sb` in its place — no rebuild, no remaster — or swap it live with
`slax activate`.

slax-kitchen allocates `00`–`09` to the platform, **`10`–`89` to forks**, `90`–`97` to headroom, and
refuses `98` and `99`. Inside the fork band this project uses `20`–`29` for its platform and
`30`–`89` for applications; `10`–`12` are left alone because slax-kitchen's own example app recipes
sit there.

**This bundle depends on `21-wine-desktop.sb`**, which supplies `/usr/local/bin/slax-wine`. That is
correct rather than a flaw: `20`+`21` are the platform, `30` is an app on it.

## The installer, not the portable build

A portable `.exe` would prove only that Wine can load a PE binary and open a window. The NSIS
installer additionally exercises the installer runtime, registry writes, file creation inside the
prefix and shortcut generation — much closer to what a game needs. It also makes updating trivial:
`APP_URL` and `APP_SHA256` in `build.env`, and nothing else changes.

| | |
|---|---|
| asset | `npp.8.9.8.Installer.exe` |
| size | 6,806,520 B |
| sha256 | `9753e2eba8f0ff056d60c52a917f7760ea81227e41b1786260e1ac76db398434` |
| type | **PE32 / Intel 80386 — 32-bit**, Nullsoft self-extracting |

The hash is upstream's own published value — it appears verbatim in
`npp.8.9.8.checksums.sha256`, which Notepad++ also signs. 32-bit matters: the `x64` and `arm64`
installers are separate assets and would not run under `wine32`.

## It cannot run at build time

`bundle.script`'s chroot has no `/proc`, and `wineboot` needs it. So the bundle ships the installer
and the live system runs it. That is not a compromise — it is the demonstration.

`/usr/local/bin/notepadpp` installs on first use and launches thereafter:

```sh
NPP="$HOME/.wine/drive_c/Program Files/Notepad++/notepad++.exe"
[ -f "$NPP" ] || wine /opt/notepadpp/npp-installer.exe "$@"
[ -f "$NPP" ] && exec wine "$NPP"
```

A 32-bit prefix has one `Program Files`, not a `(x86)` variant, so the path is predictable. The
guard means a cancelled install does not loop.

**Wine sees it with no prefix setup at all**, because Wine maps `Z:` to `/` by default — so
`/opt/notepadpp/` is reachable as `Z:\opt\notepadpp\` without touching the prefix.

## The best thing about shipping an installer

On a non-persistent boot the install lands in the RAM writable layer and is gone at shutdown, so it
must be re-run every boot. On a persistent USB it happens once and stays.

That makes Notepad++ a live demonstration of what persistence is for, which ties this bundle,
[`wine`](wine.md) and [INSTALL.md](../../INSTALL.md) into one story.

## What it proves, and what it does not

It exercises PE loading, the NSIS runtime, registry writes, file creation in the prefix, and the
common-controls GUI. It does **not** exercise DirectDraw/Direct3D, DirectSound, MSI or 16-bit code —
which for an old game are precisely the risky parts. A games variant should not inherit confidence
from this page.

Note also that stock Slax ships **no GPU firmware at all** — no `amdgpu`, `i915`, `radeon` or
`nouveau` — so 3D under Wine falls back to software rendering until slax-kitchen's
`firmware-refresh` recipe is applied. Notepad++ does not care; a game would. See
[DECISIONS.md](../DECISIONS.md).

## Verified

```
built slax/modules/30-notepadpp.sb (6556 KiB, 4 files)
  /opt/notepadpp/npp-installer.exe      (6,806,520 B, sha256 verified against upstream)
  /opt/notepadpp/VERSION
  /usr/local/bin/notepadpp
  /usr/share/applications/7notepadpp.desktop
```

`30-notepadpp.sb` is 6,713,344 B — **6.4 MiB**. The payload barely compresses, because an NSIS
installer is already a compressed archive.

| you want | use |
|---|---|
| Wine itself | [`wine`](wine.md) |
| the launcher plumbing this relies on | [`wine-desktop`](wine-desktop.md) |
| to run without it | `noload=30-notepadpp.sb` at the boot prompt |
| to swap in your own application | replace `30-notepadpp.sb`, or copy this recipe |
