# NOTICE

## Credit

**Slax** and **Linux Live Kit** are the work of **Tomáš Matějíček** (`Tomas-M`). This project
customizes *his* work; without it there would be nothing here to customize.

- <https://www.slax.org> — the project, downloads, changelog, and his donate page
- <https://www.linux-live.org> — Linux Live Kit, the framework Slax is built on
- <https://github.com/Tomas-M/linux-live> — the source: Linux Live Kit *and* the complete official
  Slax build system. There is no separate `Tomas-M/slax` repository; this is it.
- <https://github.com/Tomas-M> — components Slax depends on directly: `dynfilefs`,
  `httpfs2-enhanced`, `ncurses-menu`, `mini-commander`

If you find this useful, support Slax upstream. This repository is not that project's home.

**Wine** is the work of the WineHQ project — <https://www.winehq.org>. **Notepad++** is Don Ho's —
<https://notepad-plus-plus.org>. Neither is modified here; both are redistributed as their
publishers built them.

**Bottles** is the work of the Bottles developers — <https://usebottles.com>,
<https://github.com/bottlesdevs/Bottles>. slax-bottles redistributes it exactly as **Flathub** built
it, together with the Flathub runtimes it depends on (the GNOME Platform, the freedesktop GL, compat
and codecs extensions, and WineHQ's Gecko and Mono). **DXVK** is Philip Rebohle's
(<https://github.com/doitsujin/dxvk>); **VKD3D-Proton** is Hans-Kristian Arntzen's and contributors'
(<https://github.com/HansKristian-Work/vkd3d-proton>). None of them is modified here. Bottles has a
donate link; it asks for one on first launch.

The build engine is [slax-kitchen](https://github.com/Fullaxx/slax-kitchen), pinned as a submodule.
Nineteen files here come from it. Twelve are copied verbatim (MIT → MIT): `ci/lib.sh`, seven
`ci/checks/*.sh`, the two helpers those gates call (`ci/md-links.py`, `ci/unit-run.py`), and
`tests/unit/test_ci_lib.py` and `test_unit_gate.py`. Seven are adapted: `ci/run-checks.sh`, five more
gates, and `tests/unit/test_desktop_entries.py`. Each carries a header naming the upstream commit it
came from, and `ci/checks/96-release-consistency.sh` fails if that commit is not the current
submodule pin — or if a file claiming *copied verbatim* differs from the vendored original.

## Licence boundary

| component | licence |
|---|---|
| slax-wine's own recipes, scripts, docs and workflows | **MIT** — see [LICENSE](LICENSE) |
| `vendor/slax-kitchen/` — pinned, unmodified submodule | MIT |
| `vendor/slax-kitchen/vendor/linux-live/` — nested submodule | **GPLv2**, © Tomáš Matějíček |
| Wine 8.0 (`wine`, `wine32`, `libwine`, `wine32-preloader`, `fonts-wine`) | **LGPL-2.1-or-later** |
| Notepad++ 8.9.8 | **GPLv3** |
| Bottles 67.3 (slax-bottles only) | **GPLv3** |
| the Flathub runtimes in slax-bottles | each component its own licence; the runtimes carry them under `files/share/licenses/` |
| DXVK 3.1, VKD3D-Proton 3.0.1 (slax-bottles only) | **zlib** / **LGPL-2.1** respectively |
| every other Debian package in the image | its own licence, per `/usr/share/doc/*/copyright` |
| the Linux kernel, aufs-patched by upstream Slax | **GPLv2** |
| non-free firmware in `01-firmware.sb` | per-package redistribution terms |
| the released `.iso` | an **aggregate**; no single licence covers it |

## Redistributing the ISOs

slax-kitchen deliberately publishes **no** ISO, and says why: the GPLv2 source-offer obligation falls
on whoever publishes a customized image. **slax-wine publishes four** — `slax32-wine-bios`,
`slax32-wine-uefi`, `slax64-wine-bios` and `slax64-wine-uefi` — so that obligation is ours, and this
section is how it is discharged rather than a disclaimer.

A base's two images contain the **same** software: identical bundles, identical packages. The 64-bit
images carry the 32-bit ones' software built for their base — Wine in both halves, amd64 and i386 —
plus the 64-bit build of Notepad++. The uefi images additionally carry a GRUB EFI binary built by
`grub-mkstandalone` from the host's GRUB 2, which is **GPLv3+** — a licence the rest of the image
does not use. It is generated at build time from packages the builder already has, so the
corresponding source is whatever GRUB the build host installed. `build.sh` records which one that
was on a `grub (ESP)` line in each uefi image's `out/build-summary-<variant>.txt`, so the claim
above points at something checkable rather than being a promise nothing keeps. The bios images
contain no GPLv3 component at all.

**slax-bottles is a third image**, with a different software set: 64-bit Slax, flatpak from
Debian bookworm, and the Bottles Flatpak with its runtimes, DXVK and VKD3D-Proton. It also carries the
same kind of GRUB ESP as the uefi image, so the same GPLv3+ note applies, recorded in
`out/build-summary-bottles.txt`. Everything in its Flatpak installation is pinned by ostree commit in
`BOTTLES_LOCK` (`build.env`) and listed inside the image at `/opt/bottles/VERSION`. That is what
identifies the corresponding source: Flathub builds from public manifests, and each commit records the
manifest revision that produced it.

**Nothing here is modified.** Every binary in the image is upstream's, redistributed as built. So
"complete corresponding source" means each component's own upstream release, and none of it had to be
written by us.

**Source is attached to the release, not merely linked.** GPLv2 §3's closing paragraph counts
offering source as distribution only when it is available *"from the same place"* as the binary — and
unlike GPLv3 §6(d), it does not bless pointing at a third-party server. So each release carries source
tarballs as assets alongside the ISO, for everything whose version is known:

| shipped binary | source attached |
|---|---|
| Wine 8.0~repack-4 and every other Debian package `20-wine.sb` ships: its dependencies — on 64-bit for i386 and amd64 — and the base packages it upgrades to match, each listed with its version in the image's `packages.tsv` | Debian `deb-src`, bookworm — also permanently at `snapshot.debian.org` |
| Notepad++ 8.9.8, the 32-bit and the 64-bit build | the `v8.9.8` tag, `notepad-plus-plus/notepad-plus-plus` |
| Linux Live Kit, and the Slax build system | `Tomas-M/linux-live` at the commit pinned by the nested submodule |
| `busybox` 1.26.2 in the initramfs | busybox.net, that release |
| `ncurses-menu`, `mount.dynfilefs`, `mount.httpfs2`, `mc` | Tomáš's repositories, at their releases |
| the kernel | upstream Slax's build, plus the out-of-tree aufs patch set |
| Bottles and its Flathub runtimes (slax-bottles) | the `flathub/com.usebottles.bottles` manifest and Bottles' `67.3` tag; each runtime's source per its Flathub/freedesktop-sdk/GNOME manifest at the locked commit |
| DXVK 3.1, VKD3D-Proton 3.0.1 (slax-bottles) | their upstream release tags |

### What we cannot supply, stated plainly

Three static binaries in the initramfs — **`blkid`, `eject` and `xfs_growfs`** — are prebuilt blobs
inherited from upstream Slax. Its `initramfs/static/README` says only *"To rebuild these static
binaries, use buildroot"*, and records neither the upstream release nor the build configuration. We
therefore cannot identify which source corresponds to them, and no build config exists publicly for
any of the static set.

We are not able to close that ourselves, and we do not pretend otherwise:

- an issue asking upstream for those versions and configs is open — see
  [docs/UPSTREAM.md](docs/UPSTREAM.md);
- **written offer:** for three years from each release, we will pass any request for source for those
  components to upstream and forward whatever is provided, at no charge beyond the cost of
  distribution. Open an issue on this repository.

This is a genuine and knowing gap, not an oversight, and it is the reason slax-kitchen chose to
publish no image at all. We have taken the other choice, with the limit documented. If that is not
good enough for your use, build the ISO yourself with `./build.sh` — nothing is distributed and the
question does not arise.

### If you rebuild and redistribute

The obligation becomes yours, not ours. MIT's no-warranty clause covers *our* recipes; it does not
and cannot waive anything for the aggregate.
