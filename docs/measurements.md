# Measurements

Every number this project has measured, in one place: sizes, timings, memory, counts, and the
estimates they replaced. No other page states a measured number. A page that needs one links to its
row here, by the row's `id`, and says what it is without repeating it, for example
`[the slax-bottles ISO](measurements.md#iso-slax-bottles)`. So when a number moves, it is changed
once, and nothing elsewhere can go stale.

## The rules

- **One row per quantity, with how it was measured.** "Measured on" gives the date, the build or
  engine, and where it ran: **KVM** (the boot host), **TCG** (QEMU without an accelerator: a
  container, this build host), or a **runner** (GitHub's hosted machines, in the release workflow).
  Two conditions are never merged into one range: each value says which it was measured under.
- **"Re-measure" says how, where a table has that column.** A cell of the form `summary <image> <key>` names a line in the build
  summary, `out/build-summary-<variant>.txt`, which `./build.sh` writes. `ci/measure-check.sh`
  compares those rows with the summaries in `out/`. Everything else is measured by hand: as the
  cell says, or, in a table without the column, the way the row describes.
- **`TBD-MEASURED` is the placeholder for a number not measured yet,** and it goes in this page's
  value column and nowhere else. Write it bare. Gate 96 §6 refuses a tagged release while this page
  still has one. Quoted in backticks, as here, it is a mention, and the gate skips it.
- **Exempt, because each is a dated record rather than a claim about now:**
  - [UPSTREAM.md](UPSTREAM.md), the history of each engine bump;
  - CHANGELOG entries for released versions;
  - the command transcripts in the cookbook's *Verified* sections, which are output as it was
    seen, with its date;
  - comments in `ci/` about the gates' own speed.
- **Text an image shows its user keeps its number,** because a dialog cannot link a row and a
  number is what the reader needs there. It changes only with a rebuild, so its row names where it
  is quoted, and whoever changes the row changes the dialog in the same commit. Two do today: the
  Notepad++ launchers' question about a second prefix, in `recipes/available/notepadpp32.yaml`
  ([`prefix-win32-slax64`](#prefix-win32-slax64)) and `notepadpp64.yaml`
  ([`prefix-win64`](#prefix-win64)).
- **Config is not a measurement.** `BASE*_SIZE`, `APP*_SIZE` and the `*_MAX_ISO_MIB` caps in
  `build.env` are values a build enforces. They stay there, and the *Size caps* table below says
  which measurement each cap was derived from.
- **What this page is not:** a gate on the numbers themselves. A rebuild legitimately moves bytes
  (see [*Why a rebuild moves bytes*](#why-a-rebuild-moves-bytes)), and slax-bottles takes whatever
  Flathub serves that day, so `ci/measure-check.sh` reports differences and never fails a build.
  [DECISIONS.md](DECISIONS.md) D-21 says why.

## Images

The five shipped images' sizes are the files published in the
[v1.0.0 release](https://github.com/Fullaxx/slax-wine/releases/tag/v1.0.0), built by the release
workflow on 2026-09-30. The slax-wine ISOs there are the same size, to the byte, as the local
build of 2026-09-28. slax-bottles is not, since Flathub's runtimes float (D-20): the local build that the
[ledger](#slax-bottles-where-the-size-goes) below itemises is 4,096 bytes smaller. Test images are
never published, so theirs are local builds.

| id | bytes | MiB | what | measured on | re-measure |
|---|---|---|---|---|---|
| <a id="base-slax32"></a>`base-slax32` | 436,060,160 | 415.9 | stock `slax-32bit-debian-12.2.0.iso` | enforced: `BASE32_SIZE`, which gate 96 holds to the pinned `sources.yaml` | `stat -c%s isos/slax-32bit-debian-12.2.0.iso` |
| <a id="base-slax64"></a>`base-slax64` | 435,853,312 | 415.7 | stock `slax-64bit-debian-12.2.0.iso` | enforced: `BASE64_SIZE`, as above | `stat -c%s isos/slax-64bit-debian-12.2.0.iso` |
| <a id="iso-slax32-wine-bios"></a>`iso-slax32-wine-bios` | 588,742,656 | 561.5 | the shipped ISO | v1.0.0 release | `summary slax32-wine-bios ISO` |
| <a id="iso-slax32-wine-uefi"></a>`iso-slax32-wine-uefi` | 595,232,768 | 567.7 | the shipped ISO | v1.0.0 release | `summary slax32-wine-uefi ISO` |
| <a id="iso-slax32-wine-test"></a>`iso-slax32-wine-test` | 595,245,056 | 567.7 | the test image: uefi plus `serial-console` and `testkit` | local build, 2026-09-30 | `summary slax32-wine-test ISO` |
| <a id="iso-slax64-wine-bios"></a>`iso-slax64-wine-bios` | 911,984,640 | 869.7 | the shipped ISO | v1.0.0 release | `summary slax64-wine-bios ISO` |
| <a id="iso-slax64-wine-uefi"></a>`iso-slax64-wine-uefi` | 918,474,752 | 875.9 | the shipped ISO | v1.0.0 release | `summary slax64-wine-uefi ISO` |
| <a id="iso-slax64-wine-test"></a>`iso-slax64-wine-test` | 918,489,088 | 875.9 | the test image | local build, 2026-09-30 | `summary slax64-wine-test ISO` |
| <a id="iso-slax-bottles"></a>`iso-slax-bottles` | 1,362,518,016 | 1299.4 | the shipped ISO, with the runtimes Flathub served on 2026-09-30 | v1.0.0 release | `summary slax-bottles ISO` |
| <a id="iso-slax-bottles-test"></a>`iso-slax-bottles-test` | 1,362,526,208 | 1299.4 | the test image, with the runtimes Flathub served that day | local build, 2026-09-30 | `summary slax-bottles-test ISO` |
| <a id="release-assets"></a>`release-assets` | 4,378,208,826 | 4175.4 | all 32 files of a release together, which is what the workflow uploads | v1.0.0 release | `gh release view v<version> --json assets --jq '[.assets[].size]\|add'` |

## Where the size goes

Each ledger adds up to the byte. It is one build's, taken from its build summary.

### slax32-wine

The local build of 2026-09-28, the first with the firmware; the rebuild of 2026-09-29 matched it to
the byte.

| id | | bytes | MiB | re-measure |
|---|---|---|---|---|
| `base-slax32` | stock `slax-32bit-debian-12.2.0.iso` | 436,060,160 | 415.9 | see [Images](#images) |
| <a id="l32-chromium"></a>`l32-chromium` | − `05-chromium.sb`, the stock browser | −85,659,648 | −81.7 | `stat` it in the stock ISO |
| <a id="l32-firmware-debian"></a>`l32-firmware-debian` | + `09-firmware-debian.sb` (`firmware-refresh`: Debian's current firmware packages) | +51,118,080 | +48.8 | `summary slax32-wine-bios 09-firmware-debian.sb` |
| <a id="l32-firmware-linux"></a>`l32-firmware-linux` | + `09-firmware-linux.sb` (`firmware-refresh`: files from linux-firmware, with their licences and `WHENCE`) | +5,677,056 | +5.4 | `summary slax32-wine-bios 09-firmware-linux.sb` |
| <a id="l32-wine"></a>`l32-wine` | + `20-wine.sb` | +174,686,208 | +166.6 | `summary slax32-wine-bios 20-wine.sb` |
| <a id="l32-wine-desktop"></a>`l32-wine-desktop` | + `21-wine-desktop.sb` | +4,096 | +0.004 | `summary slax32-wine-bios 21-wine-desktop.sb` |
| <a id="l32-notepadpp32"></a>`l32-notepadpp32` | + `30-notepadpp32.sb` | +6,713,344 | +6.4 | `summary slax32-wine-bios 30-notepadpp32.sb` |
| <a id="l32-dpkg-db"></a>`l32-dpkg-db` | + `98-dpkg-db.sb` (generated at pack time) | +143,360 | +0.1 | `summary slax32-wine-bios 98-dpkg-db.sb` |
| `iso-slax32-wine-bios` | **slax32-wine-bios** | **588,742,656** | **561.5** | |
| <a id="esp"></a>`esp` | + `boot/efi.img` (uefi images only: a FAT12 ESP, **not** a bundle), and the `/boot` directory that holds it | +6,488,064 + 2,048 | +6.2 | `summary slax32-wine-uefi boot/efi.img` |
| `iso-slax32-wine-uefi` | **slax32-wine-uefi** | **595,232,768** | **567.7** | |

| id | value | what |
|---|---|---|
| <a id="net-slax32-wine"></a>`net-slax32-wine` | +152,682,496 B (+145.6 MiB) bios; +159,172,608 B (+151.8 MiB) uefi | over stock |
| <a id="firmware-total"></a>`firmware-total` | +54.2 MiB | what `firmware-refresh` costs, on every image: the two `09-firmware` bundles together |

### slax64-wine

The same system on the 64-bit base ([DECISIONS.md](DECISIONS.md) D-16), from the same build.

| id | | bytes | MiB | re-measure |
|---|---|---|---|---|
| `base-slax64` | stock `slax-64bit-debian-12.2.0.iso` | 435,853,312 | 415.7 | see [Images](#images) |
| <a id="l64-chromium"></a>`l64-chromium` | − `05-chromium.sb` | −82,903,040 | −79.1 | `stat` it in the stock ISO |
| `l32-firmware-debian` | + `09-firmware-debian.sb`, the same bundle as on 32-bit | +51,118,080 | +48.8 | `summary slax64-wine-bios 09-firmware-debian.sb` |
| `l32-firmware-linux` | + `09-firmware-linux.sb`, the same | +5,677,056 | +5.4 | `summary slax64-wine-bios 09-firmware-linux.sb` |
| <a id="l64-wine"></a>`l64-wine` | + `20-wine.sb` (both halves of Wine, and the base packages lifted to match their i386 twins) | +488,517,632 | +465.9 | `summary slax64-wine-bios 20-wine.sb` |
| `l32-wine-desktop` | + `21-wine-desktop.sb` | +4,096 | +0.004 | `summary slax64-wine-bios 21-wine-desktop.sb` |
| `l32-notepadpp32` | + `30-notepadpp32.sb` | +6,713,344 | +6.4 | `summary slax64-wine-bios 30-notepadpp32.sb` |
| <a id="l64-notepadpp64"></a>`l64-notepadpp64` | + `31-notepadpp64.sb` | +6,860,800 | +6.5 | `summary slax64-wine-bios 31-notepadpp64.sb` |
| `l32-dpkg-db` | + `98-dpkg-db.sb` | +143,360 | +0.1 | `summary slax64-wine-bios 98-dpkg-db.sb` |
| `iso-slax64-wine-bios` | **slax64-wine-bios** | **911,984,640** | **869.7** | |
| `esp` | + `boot/efi.img` and its `/boot` directory | +6,488,064 + 2,048 | +6.2 | `summary slax64-wine-uefi boot/efi.img` |
| `iso-slax64-wine-uefi` | **slax64-wine-uefi** | **918,474,752** | **875.9** | |

**`20-wine.sb` is 2.8 times the 32-bit one**, and not because 64-bit code is bigger. It carries Wine
twice, `libwine` for amd64 and for i386, plus an i386 copy of the libraries that 32-bit programs
load. Mesa is among them, since the 64-bit base has only its own amd64 Mesa. It also carries the
base packages that apt upgraded in lockstep
([`count-wine64-lifted`](#count-wine64-lifted)), which ship in this bundle rather than in the
base's.

**The ESP is 6.2 MiB, not a few KiB.** `grub-mkstandalone` embeds GRUB's modules into the EFI binary,
and they are most of it. This is worth stating because the obvious guess, that an ESP is a stub
loader, is wrong by three orders of magnitude.

### slax-bottles: where the size goes

A different image on a different base ([DECISIONS.md](DECISIONS.md) D-14). This is the local build
of 2026-09-29, with the GNOME 50 runtime Flathub served that day. The published image is 4,096
bytes larger ([`iso-slax-bottles`](#iso-slax-bottles)); which bundle the difference is in was not
measured.

| id | | bytes | MiB | re-measure |
|---|---|---|---|---|
| `base-slax64` | stock `slax-64bit-debian-12.2.0.iso` | 435,853,312 | 415.7 | see [Images](#images) |
| `l64-chromium` | − `05-chromium.sb` | −82,903,040 | −79.1 | |
| `l32-firmware-debian` | + `09-firmware-debian.sb` | +51,118,080 | +48.8 | `summary slax-bottles 09-firmware-debian.sb` |
| `l32-firmware-linux` | + `09-firmware-linux.sb` | +5,677,056 | +5.4 | `summary slax-bottles 09-firmware-linux.sb` |
| <a id="lbt-flatpak"></a>`lbt-flatpak` | + `20-flatpak.sb` (flatpak and its dependency closure) | +8,372,224 | +8.0 | `summary slax-bottles 20-flatpak.sb` |
| <a id="lbt-bottles"></a>`lbt-bottles` | + `30-bottles.sb` (the Flatpak installation, DXVK, VKD3D, launcher) | +937,771,008 | +894.3 | `summary slax-bottles 30-bottles.sb` |
| <a id="lbt-dpkg-db"></a>`lbt-dpkg-db` | + `98-dpkg-db.sb` | +135,168 | +0.1 | `summary slax-bottles 98-dpkg-db.sb` |
| `esp` | + `boot/efi.img` and its `/boot` directory | +6,488,064 + 2,048 | +6.2 | `summary slax-bottles boot/efi.img` |
| <a id="lbt-total"></a>`lbt-total` | **slax-bottles, local build of 2026-09-29** | **1,362,513,920** | **1299.4** | |

Earlier builds of the same image, for comparison. They are not current, and nothing links them as
though they were:

| id | value | what | measured on |
|---|---|---|---|
| <a id="bottles-0918"></a>`bottles-0918` | 1294.5 MiB in all; `30-bottles.sb` 889.4 MiB (5,124,096 B less than `lbt-total`) | slax-bottles with the runtimes of 2026-09-18, pinned until D-20 | local build, 2026-09-28 |
| <a id="bottles-no-dxvk"></a>`bottles-no-dxvk` | 1225.7 MiB in all; `30-bottles.sb` 874.8 MiB | slax-bottles before DXVK and VKD3D were pre-seeded, so their cost in the bundle is 16.0 MiB | local build, before the firmware |
| <a id="bottles-inplace"></a>`bottles-inplace` | 970,056 KiB, 73,418 files, updated in place; 915,792 KiB, 60,231 files, installed fresh | `30-bottles.sb` after one GNOME 50 update: what `flatpak update` keeps of the replaced commit | local builds, 2026-09-29 |

### Inside `30-bottles.sb`

| id | value | what | measured on |
|---|---|---|---|
| <a id="flatpak-tree"></a>`flatpak-tree` | 3,231 MiB of distinct file data (3.2 GiB by `du -sh`) | the Flatpak tree unpacked, as staged in `recipes/available/bottles.files/`. xz squashes it to about 878 MiB of the bundle | the staged tree, 2026-09-29 |
| <a id="dxvk-vkd3d-staged"></a>`dxvk-vkd3d-staged` | 79 MB | DXVK 3.1 and VKD3D-Proton 3.0.1 unpacked in the stage | the staged tree |

The ostree repo's objects are the same inodes as the deployed files, so this table counts them once.
In the bundle they cost nothing extra either. The copy made while building keeps the hardlinks since
slax-kitchen `f5e6673`, and mksquashfs stores a hardlinked file once, as it stored identical files
once before that. Per ref, measured on the staged tree of 2026-09-29 by inode. "Own" counts only the
bytes no other ref shares:

| id | ref | unpacked MiB | own MiB |
|---|---|---|---|
| <a id="ref-gnome"></a>`ref-gnome` | `org.gnome.Platform//50` | 976.6 | 974.9 |
| <a id="ref-bottles"></a>`ref-bottles` | `com.usebottles.bottles//stable` (includes its own Wine 11.0) | 503.5 | 503.3 |
| <a id="ref-compat-i386"></a>`ref-compat-i386` | `org.freedesktop.Platform.Compat.i386//25.08` | 290.6 | 289.2 |
| <a id="ref-gecko"></a>`ref-gecko` | `org.winehq.Wine.gecko//stable-25.08` | 204.2 | 204.2 |
| <a id="ref-mono"></a>`ref-mono` | `org.winehq.Wine.mono//stable-25.08` | 180.5 | 180.5 |
| <a id="ref-gl32"></a>`ref-gl32` | `org.freedesktop.Platform.GL32.default` `//25.08` + `//25.08-extra` | 464 each | 92.8 + 92.9 |
| <a id="ref-gl"></a>`ref-gl` | `org.freedesktop.Platform.GL.default` `//25.08` + `//25.08-extra` | 440 each | 88.3 + 88.3 |
| <a id="ref-codecs"></a>`ref-codecs` | `org.freedesktop.Platform.codecs-extra` + `codecs_extra.i386` | 41.4 + 29.2 | 41.2 + 29.0 |

## Size caps

The caps are config in `build.env`. `kitchen test --structure --max-size-mib` enforces them on every
build. Each one is a measured image plus 5%:

| id | cap | derived from | headroom now |
|---|---|---|---|
| <a id="cap-wine32"></a>`cap-wine32` | `WINE32_MAX_ISO_MIB=589` | [`iso-slax32-wine-bios`](#iso-slax32-wine-bios) + 5%. It covers the uefi image too | 27.5 MiB bios, 21.3 MiB uefi |
| <a id="cap-wine64"></a>`cap-wine64` | `WINE64_MAX_ISO_MIB=919` | [`iso-slax64-wine-uefi`](#iso-slax64-wine-uefi) + 5%. It covers the bios image too | 49.3 MiB bios, 43.1 MiB uefi |
| <a id="cap-bottles"></a>`cap-bottles` | `BOTTLES_MAX_ISO_MIB=1364` | [`lbt-total`](#lbt-total) + 5% | 64.6 MiB |
| <a id="cap-github"></a>`cap-github` | 2 GiB per asset (`RELEASE_MAX_BYTES` in `ci/release-lib.sh`) | GitHub's limit, not ours; `ci/release-stage.sh` and `ci/release-sums.sh` refuse anything larger | |

## Building and releasing

| id | value | what | measured on | re-measure |
|---|---|---|---|---|
| <a id="disk-bottles-build"></a>`disk-bottles-build` | about 14 GB free | the disk to budget for a `--bottles` build. It was the sum of the rows below when the work copy cost its per-name size; since slax-kitchen `f5e6673` they add up to about 10 GB, and the budget has not been lowered | local build, 2026-09-28 | add up the rows below |
| <a id="disk-stage"></a>`disk-stage` | 3.2 GiB, plus [`dxvk-vkd3d-staged`](#dxvk-vkd3d-staged) | `recipes/available/bottles.files/`, the same tree as [`flatpak-tree`](#flatpak-tree) | 2026-09-28 | `du -sh recipes/available/bottles.files` |
| <a id="disk-work-copy"></a>`disk-work-copy` | 3.3 GiB by `du`; 7.3 GiB by `du --count-links` | the copy `bundle.files` makes under `work/` while it builds `30-bottles.sb`. Since slax-kitchen `f5e6673` (#64) it keeps the stage's hardlinks, so `du` is its cost. Counted per name, which is what it cost before, it is the larger figure. It is removed when the bundle is done | 2026-09-28 | `du -sh` and `du -sh --count-links` on it mid-build |
| <a id="disk-work-bottles"></a>`disk-work-bottles` | 0.4 GB unpacked base, plus the 0.9 GB bundle | `work/bottles/` | 2026-09-28 | `du -sh work/bottles` |
| <a id="disk-out-bottles"></a>`disk-out-bottles` | [`iso-slax-bottles`](#iso-slax-bottles) | `out/slax-bottles-<ver>.iso` | | |
| <a id="restage-download"></a>`restage-download` | about 1 GB | the download when a stale stage is installed again from nothing | 2026-09-29 | |
| <a id="flathub-commit-life"></a>`flathub-commit-life` | at most 11 days | how long Flathub kept the files of a replaced commit: `org.gnome.Platform//50` as pinned on 2026-09-18 answered HTTP 404 on 2026-09-29 | runner, run `36560764961` | `flatpak remote-info --commit=<old> flathub <ref>` |
| <a id="runner-disk"></a>`runner-disk` | 108 GB free on `/` | a hosted runner after the build job removes its preinstalled SDKs. GitHub promises about 14 GB | runner, first rehearsal, 2026-09-29 | the build job's `df -h /` step |
| <a id="release-run"></a>`release-run` | 29 min | a whole tag run, `guard` to `finish` | runner, run `36699966431`, 2026-09-30 | `gh run view <id> --json createdAt,updatedAt` |
| <a id="release-run-jobs"></a>`release-run-jobs` | slax64-wine 28.7 min, slax-bottles 26.8 min, slax32-wine 16.6 min; `guard`, `gates` and `finish` under a minute each | each job of that run. The build jobs run in parallel, so the longest one sets the run's length | runner, run `36699966431` | `gh run view <id> --json jobs` |

## Booting

A boot is timed to `Live Kit done`, which the harness reports as `waited`. Each route is one boot,
except `--persistence`, which is two.

| id | value | what | measured on |
|---|---|---|---|
| <a id="boot-kvm"></a>`boot-kvm` | 4–6 s | a boot, on any route, on all three test images: six at 6 s, six at 4 s, three at 5 s | KVM, 2026-09-21, engine `7f9c4f8`; and `slax32-wine-uefi` through its own loader at 6 s, 2026-09-18 |
| <a id="boot-kvm-command"></a>`boot-kvm-command` | 8–15 s per route | the whole `kitchen test` command on the boot host, the transfer included | KVM, 2026-09-21 |
| <a id="boot-tcg"></a>`boot-tcg` | 21–31 s | a boot under TCG on this project's own machines, across both bases | TCG, 2026-09-19 |
| <a id="boot-tcg-slax64"></a>`boot-tcg-slax64` | `--kernel` 28 s, `--bios` 31 s, `--uefi` 29 s | the routes of `slax64-wine-test` | TCG, 2026-09-19 |
| <a id="boot-runner-kvm"></a>`boot-runner-kvm` | 4–6 s | a boot of `slax64-wine-test` or `slax-bottles-test` on a runner, under its KVM | runner, run `36699966431` |
| <a id="boot-runner-tcg"></a>`boot-runner-tcg` | 19–20 s | a boot of `slax32-wine-test` on a runner under TCG, with `--tcg-keys` | runner, run `36699966431` |
| <a id="boot-runner-32-kvm"></a>`boot-runner-32-kvm` | no boot within the 600 s ceiling | `slax32-wine-test` under a runner's KVM: the guest stopped after `Live Kit init` on all four routes. Cause not established | runner, run `36560764961`, 2026-09-29 |
| <a id="grub-menu-tcg"></a>`grub-menu-tcg` | drawn at 3.2 s idle, 6.9 s with the vCPU sharing a core; countdown over at 8.3 s and 22.8 s | GRUB's 5-second UEFI menu | TCG, 2026-09-19 |
| <a id="key-lead-tcg"></a>`key-lead-tcg` | 1–2 s fail, 3–6 s pass, 8–16 s fail; on a starved core 4 s fails too | a keystroke lead sweep through the harness, idle host | TCG, 2026-09-19 |
| <a id="grub-menu-kvm"></a>`grub-menu-kvm` | about 1 s | GRUB's UEFI menu first drawn (upstream's figure, `docs/50-cookbook/uefi-bootable.md`). At a load average of 12 the harness's 2 s lead missed it twice | KVM, 2026-09-21 |

## Running it

| id | value | what | measured on |
|---|---|---|---|
| <a id="prefix-win64"></a>`prefix-win64` | 1,265 MiB | a fresh 64-bit Wine prefix, the default on slax64. Quoted as "1.2 GiB in RAM" in the `notepadpp64` launcher's dialog | 2026-09-21 |
| <a id="prefix-win32-slax32"></a>`prefix-win32-slax32` | 587 MiB | a fresh 32-bit prefix on slax32, the default there | 2026-09-21 |
| <a id="prefix-win32-slax64"></a>`prefix-win32-slax64` | 589 MiB | a fresh `WINEARCH=win32` prefix on slax64. Quoted as "589 MiB in RAM" in the `notepadpp32` launcher's dialog | 2026-09-21 |
| <a id="prefix-time-kvm"></a>`prefix-time-kvm` | 65 s a 64-bit prefix on slax64; 32 s a 32-bit one there; 23 s on slax32 | creating a prefix, idle host | KVM, 2026-09-21 |
| <a id="prefix-time-tcg"></a>`prefix-time-tcg` | about 4 min a 64-bit prefix on slax64 (258 s on one run); 90 s a 32-bit one there | the same | TCG, 2026-09-19 |
| <a id="prefix-time-tcg-slax32"></a>`prefix-time-tcg-slax32` | idle: **the records disagree**, 90 s ([UPSTREAM.md](UPSTREAM.md#when-kvm-lands-it-did-on-2026-09-21-and-this-is-what-it-changed)) against about 4 min (the `notepadpp32` page). Busy: 7–9 min, past the 5 minutes Wine waits, so that first launch failed | slax32's prefix. Unresolved until re-measured under TCG | TCG, 2026-09-19 |
| <a id="npp-install-x86"></a>`npp-install-x86` | 1.3 s on slax32, 1.6 s on slax64; 29 s under TCG | the Notepad++ x86 installer, `/S` | KVM, 2026-09-21; TCG, 2026-09-19 |
| <a id="npp-install-x64"></a>`npp-install-x64` | 1.7 s; 29–32 s under TCG | the Notepad++ x64 installer, `/S` | the same |
| <a id="ram-slax32"></a>`ram-slax32` | boots in 2 GiB; in 3 GiB, 1,273 MiB used after the first prefix and Notepad++, 645 MiB of it the RAM layer | memory. No minimum established | QEMU; date not recorded |
| <a id="ram-slax64"></a>`ram-slax64` | in 3 GiB: 452 MiB used at the idle desktop, 1.8 GiB after the Wine tile's first run. Keeping two prefixes and making a third stalled it until reset, with no OOM kill | memory. No minimum established | QEMU; date not recorded |
| <a id="ram-slax-bottles"></a>`ram-slax-bottles` | boots in 3 GiB; in 6 GiB, 550 MiB at the idle desktop, 738 MiB with Bottles open, 1.75 GiB after creating a bottle | memory. No minimum established | QEMU; date not recorded |
| <a id="bottle-fresh"></a>`bottle-fresh` | 386 MiB on one run, 491 MiB on another, not reconciled | a fresh bottle, before anything is installed in it | offline, in QEMU; date not recorded |
| <a id="bottle-create-tcg"></a>`bottle-create-tcg` | 19 min (19½) on one run, 24 min on another that shared the host with a build | `bottles-cli new`, offline. Never timed under KVM | TCG |
| <a id="mono-gecko-download"></a>`mono-gecko-download` | about 136 MiB | what Wine's Mono/Gecko prompt would fetch from winehq at runtime | winehq's files; date not recorded |

## Counts

| id | value | what | re-measure |
|---|---|---|---|
| <a id="packages-slax32-wine"></a>`packages-slax32-wine` | 642, in 651 database entries | installed packages, in each slax32-wine image: 567 + 16 + 59 | `summary slax32-wine-bios packages` |
| <a id="packages-slax64-wine"></a>`packages-slax64-wine` | 832, in 841 database entries | installed packages, in each slax64-wine image: 566 + 16 + 60 + 190 | `summary slax64-wine-bios packages` |
| <a id="packages-slax-bottles"></a>`packages-slax-bottles` | 613, in 622 database entries | installed packages in slax-bottles: 566 + 16 + 31 | `summary slax-bottles packages` |
| <a id="count-stock"></a>`count-stock` | 600 packages in the full stock image. After `05-chromium` is removed, the database starts from `04-apps`': 567 installed in 576 entries on 32-bit, 566 in 575 on 64-bit | the stock bases | `dpkg -l` on the stock image |
| <a id="count-wine32-closure"></a>`count-wine32-closure` | 60 packages: 59 new, plus the `libgnutls30` upgrade. 635 in the database of `04-apps` and `20-wine` alone, before the firmware | apt's closure for `20-wine` on 32-bit | the `20-wine` fragment |
| <a id="count-wine64-closure"></a>`count-wine64-closure` | 329: 60 amd64, 190 i386, and the lifted base packages | the same on 64-bit | the `20-wine` fragment |
| <a id="count-wine64-lifted"></a>`count-wine64-lifted` | 79 | base packages apt upgraded in lockstep with their i386 twins, which ship in 64-bit `20-wine.sb` | the `20-wine` fragment |
| <a id="count-flatpak-closure"></a>`count-flatpak-closure` | 36: 31 new, and 5 upgraded from the base (`gpgv`, `libcurl4` and three `libavahi` packages) | apt's closure for `20-flatpak` | the `20-flatpak` fragment |
| <a id="count-firmware"></a>`count-firmware` | 16 packages with 26 `copyright` files, and 65 files from linux-firmware | what `firmware-refresh` installs | the `09-firmware` fragments |
| <a id="count-flatpak-refs"></a>`count-flatpak-refs` | 13: Bottles and 12 runtime refs, eleven of them visible to `flatpak list` | the Flatpak installation | `.flatpak.txt` |

## Estimates, and what they came to

| id | estimated | measured | what |
|---|---|---|---|
| <a id="est-wine-bundle"></a>`est-wine-bundle` | 105–120 MiB | [`l32-wine`](#l32-wine) | the 32-bit Wine bundle, reasoned from `.deb` sizes. Wrong by about 50 MiB; [why](#why-the-estimate-was-wrong) |
| <a id="est-firmware"></a>`est-firmware` | 90 MiB (D-10) | [`firmware-total`](#firmware-total) | `firmware-refresh` |
| <a id="est-chromium-current"></a>`est-chromium-current` | 114 MiB, net +35 MiB on debian-64bit | | upstream's `chromium-current`, the alternative D-2 declined |

| id | value | what |
|---|---|---|
| <a id="deb-wine-sources"></a>`deb-wine-sources` | i386 `.deb` download: bookworm's Wine 8.0 ~91 MiB, bullseye's 5.0.3 ~24 MiB, WineHQ 6.0.4 ~72 MiB, WineHQ 10.0 / 11.0 ~99–103 MiB | the four Wine sources D-1 priced |
| <a id="deb-libwine"></a>`deb-libwine` | 91 MiB download, 563 MiB installed | the `libwine` `.deb` |
| <a id="deb-wine32-closure"></a>`deb-wine32-closure` | 126,948,952 B (121.1 MiB) | the 60 packages the 32-bit `20-wine` fragment declares, as `.deb` downloads |
| <a id="ratio-squashfs-deb"></a>`ratio-squashfs-deb` | 1.38 (about 1.4×); 1.8× against `libwine` alone, which misleads | bundle size over `.deb` download size |
| <a id="deb-libgnutls"></a>`deb-libgnutls` | about 3.6 MB | the `libgnutls30` upgrade Wine pulls in |
| <a id="src-wine"></a>`src-wine` | 826 MiB | Debian's source for Wine, measured 2026-09-26 |

## Why the estimate was wrong

The plan predicted the Wine bundle ([`est-wine-bundle`](#est-wine-bundle)) by reasoning from
Debian's `.deb` sizes: `libwine`'s download is a small fraction of its installed size
([`deb-libwine`](#deb-libwine)), so the compressed payload "should" be about that download plus
dependencies.

It came out much larger ([`l32-wine`](#l32-wine)), and the gap is the compression format. A `.deb`'s
payload is a *solid* `.tar.xz`: one stream, so xz's window spans the whole archive. A squashfs
bundle is built with `-b 1024K`, so xz restarts every mebibyte and cannot exploit redundancy across
block boundaries. Wine's payload is thousands of PE modules with a great deal of cross-file
similarity, which is exactly the case that suffers.

The lesson for the app layer: **estimate bundle size from squashfs, not from `.deb` size.** The
rule from this data point is [`ratio-squashfs-deb`](#ratio-squashfs-deb). Compare against
*everything installed* ([`deb-wine32-closure`](#deb-wine32-closure)), not one headline package.

## Installed size is not a runtime cost

`libwine`'s installed size appears nowhere in the ledgers. Squashfs holds it compressed and
decompresses on read, so what costs you is the bundle. That holds under `toram` as well, which
copies the compressed bundles into RAM rather than an installed tree.

## What could shrink it

### slax-wine

| | saves | cost |
|---|---|---|
| `noload=30-notepadpp32.sb` at boot | a squashfs mount and an aufs branch, **not** [the bundle's size](#l32-notepadpp32) in RAM: `copy_to_ram` runs at `init:43`, *before* `mount_bundles` at `:46`, and copies unconditionally, so under `toram` the bundle is in RAM either way | no test application |
| drop `01-firmware.sb` | the stock firmware bundle | no network firmware at all: wifi stops working |
| drop the two absent Recommends | a few MiB | bitmap fonts, and no PulseAudio output from Wine |

### slax-bottles

Nothing here has been tried. Each item is a lever with a known cost:

- **Gecko and Mono** ([`ref-gecko`](#ref-gecko), [`ref-mono`](#ref-mono)). Dropping them brings back
  slax-wine's position (D-4): no .NET, and no embedded HTML.
- **The `-extra` GL branches** ([`ref-gl`](#ref-gl), [`ref-gl32`](#ref-gl32), their own bytes).
  These are Mesa builds with extra video codecs, installed alongside the plain ones. Which one
  flatpak picks at runtime has not been measured.
- **The GNOME runtime cannot go.** Bottles is a GTK 4 / libadwaita app built against it.

## Why a rebuild moves bytes

**A ledger is one build's bytes, and a rebuild does not always land on the same total.** A squashfs
stores an mtime per file and a creation time of its own. So two runs of one tree differ in bytes,
and sometimes in size, by a 4 KiB padding block. This was measured on 2026-09-21 while bumping the
engine to `7f9c4f8`. Rebuilding the 2026-09-20 tree gave a 64-bit `20-wine.sb` 4,096 bytes larger
and a `30-bottles.sb` 1,372,160 bytes smaller, with the same packages at the same versions and all
the Flatpak refs at the same commits. The same refs do not mean the same bytes. Since D-20 the
refs under Bottles are not pinned either, so a Flathub update between two builds moves the bundle
too. `mksquashfs -mkfs-time 0 -all-time 0` would make the squashfs half reproducible, and is not
used.

**No sha256 is recorded here, deliberately.** A hash would identify one build, not the version.
slax-wine packs with `genisoimage`, which stamps PVD timestamps it cannot pin. Upstream measures
the difference as 19 of 212,819 sectors, all of them timestamp fields, with the payload
byte-identical. So two builds of the same tree have the same size, the same bundles and the same
package count, but different hashes. `xorriso --modification-date` would pin them, at the cost of
uppercasing the application id, which carries our version string. For a download, the authority is
the `.sha256` published beside that particular ISO.
