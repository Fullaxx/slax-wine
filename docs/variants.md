# The variants: what is the same on purpose, and what is not

Eight images are built here, from two bases and three systems. Everything about them is
stated somewhere — `build.env` and `build.sh`'s `variant_config()` hold the facts a build
reads, [DECISIONS.md](DECISIONS.md) D-16 says why there are four slax-wine images,
[software.md](software.md) inventories what each system contains, [sizing.md](sizing.md)
where the bytes go, and `ci/checks/96-release-consistency.sh` enforces a handful of rules
in code. What did not exist until this page is the answer to one question asked across all
eight: **what do they have in common, and where do they deliberately differ.**

Sizes are one build's, 2026-09-21; [sizing.md](sizing.md) says why a rebuild can move them.

## The matrix

| variant | base | profile | ships | firmware | own bundles | volume id | size |
|---|---|---|---|---|---|---|---|
| `slax32-wine-bios` | `slax-32bit-debian-12.2.0.iso` | `slax32-wine-bios.yaml` | **yes** | BIOS | `20-wine`, `21-wine-desktop`, `30-notepadpp32`, `98-dpkg-db` | `SLAX32-WINE` | 531,935,232 |
| `slax32-wine-uefi` | `slax-32bit-debian-12.2.0.iso` | `slax32-wine-uefi.yaml` | **yes** | BIOS **and** UEFI | the same four, plus `boot/efi.img` | `SLAX32-WINE` | 538,425,344 |
| `slax32-wine-test` | `slax-32bit-debian-12.2.0.iso` | `slax32-wine-test.yaml` | no | BIOS and UEFI | the same four | `SLAX32-WINE` | 538,437,632 |
| `slax64-wine-bios` | `slax-64bit-debian-12.2.0.iso` | `slax64-wine-bios.yaml` | **yes** | BIOS | the four, plus `31-notepadpp64` | `SLAX64-WINE` | 855,173,120 |
| `slax64-wine-uefi` | `slax-64bit-debian-12.2.0.iso` | `slax64-wine-uefi.yaml` | **yes** | BIOS **and** UEFI | the five, plus `boot/efi.img` | `SLAX64-WINE` | 861,663,232 |
| `slax64-wine-test` | `slax-64bit-debian-12.2.0.iso` | `slax64-wine-test.yaml` | no | BIOS and UEFI | the five | `SLAX64-WINE` | 861,677,568 |
| `slax-bottles` | `slax-64bit-debian-12.2.0.iso` | `slax-bottles.yaml` | **yes** | BIOS and UEFI | `20-flatpak`, `30-bottles`, `98-dpkg-db` | `SLAX-BOTTLES` | 1,300,676,608 |
| `slax-bottles-test` | `slax-64bit-debian-12.2.0.iso` | `slax-bottles-test.yaml` | no | BIOS and UEFI | the same three | `SLAX-BOTTLES` | 1,300,688,896 |

**A uefi image is a superset of its bios twin, not an alternative.** `uefi-bootable` adds an
EFI El Torito entry and keeps the BIOS one, so a uefi image boots everywhere its bios twin
does *and* on UEFI firmware. The five stock Slax bundles — `01-core`, `01-firmware`,
`02-xorg`, `03-desktop`, `04-apps` — survive on every one of the eight; `05-chromium` is
removed from every one of the eight.

**The application id is set at pack time**, not in a recipe, so no version string lives in
YAML: `build.sh` passes `slax32-wine 1.0.0 bios (base slax-32bit-debian-12.2.0.iso)` and its
kind for each slax-wine variant, and `slax-bottles 1.0.0 (base slax-64bit-debian-12.2.0.iso)`
for slax-bottles.

## What is the same, and what holds it there

A rule with nothing enforcing it is a rule that drifts, so each row says what would catch a
breach — and the ones that say *prose only* are the ones to be careful with.

| held the same | enforced by |
|---|---|
| every recipe is named by some profile, and every recipe a profile names exists | gate 96 §5(a), §5(a2) |
| `remove-bundle` is listed, and listed **first**, in every shipped profile | gate 96 §5(a3) |
| bios, uefi and test of one base list **the same recipes in the same order** | gate 96 §5(b) |
| the 64-bit list is the 32-bit list plus `notepadpp64`, directly after `notepadpp32` | gate 96 §5(b) |
| a profile's name matches its `base.arch`, and its `-bios`/`-uefi` matches whether it lists `uefi-bootable` | gate 96 §5(c) |
| the profile's `base:` is the base the variant builds on, all three parts | `build.sh` guard (a), before apply |
| the built image's `/etc/slax-*-release` names the base ISO it was built from | `build.sh` guard (b), read back from the packed bundle |
| a 64-bit image carries `wine64`, `wine32:i386` and `libwine` for both architectures | `build.sh` guard (c), read from the image's own package database |
| the module list is exactly what the variant should carry | `build.sh`, against `WANT_MODULES32/64` and `BOTTLES_WANT_MODULES` |
| every variant in this table has a profile, and every profile has a row here | gate 96 §11 |
| the same `.desktop` rules on every image | `tests/unit/test_desktop_entries.py` |
| the ISO stays under its ceiling | `iso_assert.py --max-size-mib`, per variant |
| **the volume id is the same across a base's three variants** | prose only — `slax-wine-iso.yaml` sets it once per base |
| **the five stock bundles survive everywhere, and chromium never does** | prose only, beyond the per-variant module list above |

## What differs, and why

**The two bases.** slax-wine is the same system on both (D-16): one set of recipes, split by
`when: arch==32bit|64bit` so exactly one step of each pair runs. The 64-bit images add the
64-bit Notepad++, and their Wine is both halves — `wine64` plus `wine32:i386`, with an i386
copy of every library the 32-bit image gives its programs.

**`WINEARCH`.** slax32 sets `WINEARCH=win32`, because that base has nothing else to run.
slax64 sets nothing: new prefixes are win64, 32-bit programs run in them through `wine32`,
and a user's own `WINEARCH=win32` passes through. `notepadpp64` refuses such a prefix, and
refuses `WINEARCH=win32` before one is created.

**The test images do not ship.** They are the uefi recipes plus `serial-console` and
`testkit`: a serial entry to assert on, and a boot-time report of the files a recipe claims
to install. Everything automated is run against them, which is why they exist; they are not
part of a release, which is why they are not in `--all`.

**slax-bottles is a different system**, not a variant of slax-wine (D-14, D-15). It carries
no Debian Wine — Bottles brings its own — and exists only on the 64-bit base, because
Flathub builds Bottles for x86_64 alone. It shares the bases, the bootloader work and the
gates, and nothing else.

**Two size ceilings, on different bases.** `WINE32_MAX_ISO_MIB=532` is the *bios* image plus
5 %, `WINE64_MAX_ISO_MIB=862` the *uefi* one plus 5 %, and `BOTTLES_MAX_ISO_MIB=1304` the
one image plus 5 %. Each covers both of its architecture's images; the 6.2 MiB an ESP adds
is well inside the margin either way.

**`notepadpp64` is 64-bit only.** The x64 installer is a PE32 stub that installs x86-64
binaries, so it needs a 64-bit prefix, which a 32-bit image cannot provide.
