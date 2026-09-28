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
Twenty-one files here come from it. Twelve are copied verbatim (MIT → MIT): `ci/lib.sh`, six
`ci/checks/*.sh`, the two helpers those gates call (`ci/md-links.py`, `ci/unit-run.py`),
`ci/yamllint.yaml`, and `tests/unit/test_ci_lib.py` and `test_unit_gate.py`. Nine are adapted:
`ci/run-checks.sh`, the two hooks in `ci/hooks/`, five more gates, and
`tests/unit/test_desktop_entries.py`. Each carries a header naming the upstream commit it came from,
and `ci/checks/96-release-consistency.sh` fails if that commit is not the current submodule pin — or
if a file claiming *copied verbatim* differs from the vendored original.

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
| every other Debian package in the image | its own licence. Those `20-wine.sb` and `20-flatpak.sb` install carry their `copyright` files under `/usr/share/doc`; Slax's build removed them from its own bundles |
| the Linux kernel, aufs-patched by upstream Slax | **GPLv2** |
| non-free firmware in `01-firmware.sb` | per-package redistribution terms |
| the released `.iso` | an **aggregate**; no single licence covers it |

## Redistributing the ISOs

**slax-wine publishes five images:** `slax32-wine-bios`, `slax32-wine-uefi`, `slax64-wine-bios` and
`slax64-wine-uefi`, which are one system on two bases, and **slax-bottles**, a second system on the
64-bit base: flatpak from Debian bookworm, and the Bottles Flatpak with its runtimes, DXVK and
VKD3D-Proton. Each is an aggregate, and we publish it the way slax-kitchen's
[NOTICE.md](https://github.com/Fullaxx/slax-kitchen/blob/4a10303/NOTICE.md#publishing-an-image-built-with-slax-kitchen)
describes, under the policy set here on 2026-09-26
([D-12](docs/DECISIONS.md#d-12--publish-the-isos-with-pointers-to-their-source)):

- **What we changed is in this repository.** The recipes, the files beside them, the boot-menu
  edits, the launchers and the build script are here, and the engine that ran them is slax-kitchen,
  at the commits each image's `<image>.iso.provenance.json` records.
- **What we did not change is pointed to, not attached.** No upstream program is modified. What
  the recipes change is configuration, the boot menus for instance, and each change is a recipe
  here. So no source is attached to a release. Each image's `<image>.SOURCES.md`,
  written by `kitchen sources`, lists every file in it and where its upstream publishes the source.
- **Each release carries** the images, one `SHA256SUMS`, and per image its `.iso.sha256`,
  provenance sidecar, `packages.tsv` and the two sources files.

Where each part's source is published:

| part | source published at |
|---|---|
| Slax 12.2.0 as Tomáš built it: Linux Live Kit, the kernel (Debian's `linux-source-6.1` plus aufs `6.1-20230724`, its configuration embedded in `vmlinuz`), the initramfs userland, and the desktop tools | slax-kitchen's [What a built image contains](https://github.com/Fullaxx/slax-kitchen/blob/4a10303/NOTICE.md#what-a-built-image-contains), which points at `Tomas-M/linux-live` and the repositories it names, and records the initramfs binaries one by one |
| Wine 8.0~repack-4 and every other Debian package, each named with its version in the image's `packages.tsv` | snapshot.debian.org. For what `20-wine.sb` and `20-flatpak.sb` add, `SOURCES.md` gives each source package's `https://snapshot.debian.org/package/<source>/<version>/`. For stock Slax's, `https://snapshot.debian.org/binary/<package>/` names the source of each version `packages.tsv` lists |
| Notepad++ 8.9.8, 32- and 64-bit | the `v8.9.8` tag of <https://github.com/notepad-plus-plus/notepad-plus-plus> |
| Bottles 67.3 and its Flathub runtimes (slax-bottles) | the manifests that built each ref at the commit `BOTTLES_LOCK` in `build.env` pins: <https://github.com/flathub/com.usebottles.bottles>, freedesktop-sdk, GNOME's `gnome-build-meta`, and Flathub's `org.winehq.Wine` for the Gecko and Mono extensions. `/opt/bottles/VERSION` in the image lists every ref and commit |
| DXVK 3.1 and VKD3D-Proton 3.0.1 (slax-bottles) | their release tags at <https://github.com/doitsujin/dxvk> and <https://github.com/HansKristian-Work/vkd3d-proton> |
| the GRUB EFI loader in the uefi images and slax-bottles, **GPLv3+** | built by `grub-mkstandalone` from the build host's unmodified GRUB. Each image's sidecar names the package and version it came from, and Launchpad publishes that source package's source: `grub2-unsigned` `2.12-1ubuntu7.3` in the builds of 2026-09-28 |

**Firmware.** Using an image that contains firmware implies acceptance of each firmware's licence
terms. Stock Slax's `01-firmware.sb` ships as Slax ships it, and Slax's build removed its packages'
`copyright` files; slax-kitchen's [Firmware](https://github.com/Fullaxx/slax-kitchen/blob/4a10303/NOTICE.md#firmware)
section records exactly what is in it, the Broadcom b43 files that never had a licence text
included.

### If you rebuild and redistribute

The obligation becomes yours, not ours. MIT's no-warranty clause covers *our* recipes; it does not
and cannot waive anything for the aggregate.
