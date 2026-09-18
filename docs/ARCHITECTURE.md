# Architecture

What slax-wine is and how every part works, at the level of detail needed to change it safely a year
from now. Why it looks like this is [DECISIONS.md](DECISIONS.md); how we raise engine problems is
[UPSTREAM.md](UPSTREAM.md).

---

## The shape of the thing

slax-wine owns no engine code. It is four recipes, a profile, a build script and eleven gates, laid
over `slax-kitchen` pinned as a submodule at `vendor/slax-kitchen`.

```
build.env          version + base identity -- the single source of truth
profiles/          the authoritative ordered recipe list
recipes/available/ four recipes
build.sh           fetch -> stage -> unpack -> apply -> pack -> assert -> measure
ci/                eleven gates; six copied verbatim, four adapted, one ours
vendor/            the engine, pinned by commit
```

`kitchen apply --profile` takes the recipe list *and* any per-recipe var overrides from the profile,
so there is exactly one place that says what this image is. A recipe absent from the profile is never
built — `ci/checks/96-release-consistency.sh` fails on an orphan for that reason.

## The layer model

Slax's root filesystem is a union of numbered squashfs bundles. **Load order is the numeric prefix
and higher wins**, because `union_append_bundles` inserts each bundle at aufs branch index 1, so each
arrival outranks the last.

That is the whole mechanism. It is not a naming convention laid over something else.

| bundle | ships | may be switched off with |
|---|---|---|
| `01-core` … `04-apps` | upstream Slax, untouched | — |
| `20-wine.sb` | Wine and its dependency closure | `noload=20-wine.sb` |
| `21-wine-desktop.sb` | launcher entry, env defaults, the wrapper | `noload=21-wine-desktop.sb` |
| `30-notepadpp.sb` | the application layer | `noload=30-notepadpp.sb` |
| `98-dpkg-db.sb` | generated at pack time | — |
| `99-changes-N.sb` | a saved session, if any | — |

`05-chromium.sb` is **deleted**, not overridden. Removal is the one case where deleting beats
overriding: a whiteout hides a file but does not reclaim its space.

### Numbering

slax-kitchen's canonical table — `vendor/slax-kitchen/docs/10-anatomy/bundles-squashfs.md`:

| range | whose |
|---|---|
| `00`–`09` | upstream Slax and slax-kitchen — the platform |
| `10`–`89` | **forks** — applications and content |
| `90`–`97` | slax-kitchen headroom; `97` is the ceiling for a recipe |
| `98` / `99` | generated database / `savechanges` — **refused at apply time** |

Inside the fork band this project uses **`20`–`29` for its platform and `30`–`89` for
applications**. `10`–`12` are left to slax-kitchen's example app recipes.

`98` and `99` are refused by every bundle verb, and the refusal is at apply time rather than in the
schema so there is one implementation rather than two that can drift.

### The swap contract

`30-notepadpp.sb` is deliberately self-contained apart from one dependency: its launcher calls
`/usr/local/bin/slax-wine` from `21-wine-desktop.sb`. **`20`+`21` are the platform; `30` is an app on
it.** A variant replaces `30-*.sb` only — delete the file from `/slax/modules/` on a stick and drop
another in, with no rebuild, or swap it live with `slax activate`.

The application's `.desktop` entry ships **in the application bundle**, not in the platform bundle,
so swapping the bundle swaps its launcher. That property is what makes the swap a file operation.

## The package database

This changed under us during development and the current shape matters.

Bundles no longer ship `var/lib/dpkg/status` — `BUNDLE_EXCLUDE` drops it. `bundle.packages` instead
writes `var/lib/slax-kitchen/dpkg-status.d/<bundle>`, holding only the stanzas it added or changed.
`kitchen pack` then calls `lib/dpkgdb.py`, which walks the bundles in load order, takes the **highest
real `status` as the base**, applies every fragment above it, and generates `98-dpkg-db.sb` — below
`99-changes-N` so a saved session still wins.

For this image: `05-chromium` is removed, so the base is `04-apps` at 576 packages and the
`20-wine` fragment declares 60. **Measured result: 635 packages** — not 636, because the fragment
adds **59 new** entries and *upgrades* one. `libgnutls30` is in both: the base carries `3.7.9-2` and
apt moves it to `3.7.9-2+deb12u7`. Worth spelling out, because "576 + 60" reads like a derivation
and is not one.

The old design had every bundle carry a cumulative status, and a high-numbered bundle shipping a
short copy would shadow a longer one. That is gone, but its shadow remains in one place — see the
`from:` trap below.

## The `from:` trap

`bundle.packages` builds its chroot from the bundles named in `from:`, and apt installs only what
that chroot says is missing. **The default is now every bundle that will sit below this one.**

For a `20-` bundle that includes `05-chromium.sb`. Building against it and then removing it produces
an image whose binaries depend on files that left with the bundle. Measured here:

| | |
|---|---|
| `libwine` Depends | `libpulse0 (>= 0.99.1)` — hard, not a Recommends |
| `libpulse0` in `01-core`…`04-apps` | absent |
| `libpulse0` in `05-chromium.sb` | present |

The failure is silent: the build succeeds, all gates pass, and the merged database is *correct* —
it rightly does not claim `libpulse0`. You find out when Wine will not start.

`wine.yaml` removes first **and** names the stack. Reported upstream; see
[UPSTREAM.md](UPSTREAM.md) issue 1.

## Boot, and how `/etc/profile.d` reaches the desktop

```
firmware → isolinux/syslinux → vmlinuz + initrfs.img
  → find_data (scans every block device, up to 45 s)
  → persistent_changes  (only if "perch" appears in /proc/cmdline)
  → copy_to_ram         (only under "toram" -- init:43, BEFORE mount_bundles, and
                         unconditional over the whole directory, so noload= does not
                         reduce what it copies)
  → mount_bundles → init_union → union_append_bundles
  → copy_rootcopy_content → fstab_create → user_preinit
  → change_root → systemd → xorg.service
       ExecStart=/bin/su --login -c "/usr/bin/Xdetect -- :0 vt7 -ac -nolisten tcp"
  → startx → /root/.xinitrc ("startfluxbox") → /root/.fluxbox/startup → fluxbox
```

**`su --login` is the load-bearing link.** It makes the session a login shell, so `/etc/profile`
runs, and `01-core`'s `/etc/profile` ends with the standard `for i in /etc/profile.d/*.sh` loop.
That is why `WINEARCH` and `WINEDLLOVERRIDES` reach Fluxbox, xlunch, and everything launched from
them. `/usr/local/bin/slax-wine` sources the file again anyway, because being wrong about this
produces a Gecko prompt on an offline machine and nothing says why.

## Persistence

`persistent_changes()` activates only if the string `perch` appears in `/proc/cmdline`, then picks
one of two storage modes by testing whether the medium can do symlinks and the executable bit:

| medium | storage | limit |
|---|---|---|
| ext4 (any POSIX fs, not NTFS) | `mount --bind <medium>/slax/changes/<N>/` | none |
| FAT32 / NTFS | `dynfilefs` container `changes.dat`, split at 4000 MB, XFS inside | `perchsize`, floor **16000 MB** |

`/root/.wine` lives in the writable layer, so persistence covers the Wine prefix with no special
handling. `savechanges` is a **different** mechanism — a snapshot into `99-changes-N.sb` staged
through tmpfs — and is the wrong tool for a prefix, which will not fit in RAM.

Upstream already ships persistence on by default down one route only: `syslinux.cfg` (USB/HDD) has
`perchdir=resume` on the auto-booted entry, while `isolinux.cfg` (CD) has the session entries as
`MENU DISABLED`. A `dd`'d ISO boots through `isolinux.cfg` on a read-only filesystem, so it cannot
persist at all.

## Filesystem layering

Only one layer is a human choice:

| layer | filesystem | chosen by | when |
|---|---|---|---|
| the medium | FAT32 **or** ext4 | you, with `mkfs` | before anything is copied |
| the perch container (FAT32 path only) | XFS | Slax, automatically | first persistent boot, once |
| the running root | aufs union | Slax | every boot |

XFS is never a decision — it appears inside the container because FAT32 cannot store symlinks or the
executable bit, and a Wine prefix needs both. On ext4 there is no container and no XFS.

## Things that will bite you

A register, because every one of these cost time to find.

| | |
|---|---|
| **`from:` default includes a bundle you may delete** | see above. Remove first *and* name the stack |
| **`Terminal=false` is mandatory on a `.desktop`** | `fbappselect` runs `ldd $binary \| grep libX11` and wraps in an xterm when empty. Debian's `/usr/bin/wine` is a shell script, so it always looks like a console program |
| **`NoDisplay` does not hide anything in xlunch** | `xlunch_genquick` greps `^(Name\|Icon\|Exec\|Hidden\|Terminal)=` and tests `Hidden`. Use `Hidden=true`. *(A stub with neither still vanishes — see the next row for why — so upstream's `NoDisplay`-only example does work.)* |
| **An `Icon=` that does not resolve DELETES the entry** | `xlunch_genquick:52` ends each entry with `if [ -e "$Icon" ]`. The search covers only numeric size dirs under `hicolor`/`pixmaps`/`icons-gnome` and only appends `.png` — so `scalable/*.svg` and anything under `Adwaita/` are invisible, `$Icon` stays a bare string, and the launcher silently disappears. This cost slax-wine **both** its tiles. Use an absolute path, or verify with `xlunch_genquick 64 --desktop` |
| **`noautomount` is ignored** | `fstab_create` tests `grep -vq automount`, and `noautomount` *contains* `automount`. Remove the flag, do not negate it |
| **`perch` is a substring match** | `perchsize=` on the `toram` entry would enable persistence on the one entry that unmounts the medium |
| **FAT32 perch floor is 16 GB and cannot be lowered** | a smaller `perchsize=` is silently raised; the size is fixed at creation |
| **`kitchen build` fails on a custom volid** | `iso_assert.py`'s `--volid` *defaults* to `slax` (`:49`), and `lib/build.sh` never passes it. Not a hardcode — but the effect is the same, hence `build.sh` |
| **`bundle.fromTarball` is tar-only** | `tarfile.open`, so no `.zip` and no `.7z` |
| **Recipes are not idempotent** | `apply` consults its journal and refuses a second application. `build.sh` unpacks fresh every run |
| **A bundle name can be produced once** | two steps targeting the same bundle is refused. Combine them into one `bundle.files` |
| **Estimate bundle size from squashfs, not from `.deb`** | `-b 1024K` restarts xz every mebibyte, so a bundle is ~**1.4×** the `.deb`s it came from. Compare against ALL the packages installed (121.1 MiB for Wine's 60), never one headline `.deb` |
| **`98-dpkg-db.sb` appears in the output** | generated at pack time. An expected-modules assertion that omits it fails on its own build |
| **Piping into `tee` hides a failure** | the pipeline's status is `tee`'s. POSIX sh has no `PIPESTATUS`; record success out of band |
| **`savechanges` first session is `99-changes-99.sb`** | its arithmetic runs on the last file in `slax/modules/`, now `98-dpkg-db`. Harmless; it increments correctly |

## What is verified, and what is not

`boot-verified`: the ISO boots under TCG to `slax login:` with all three livekit markers and all nine
bundles mounted in order. `runtime-verified` — Wine actually running a Windows program — is **not yet
claimed**. The ladder is in the [cookbook index](50-cookbook/README.md), and the distinction is the
one thing this project treats as a real error.
