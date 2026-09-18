# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are semver.

A release is defined by **both** halves — the slax-wine version and the base ISO it was built on.
See [docs/base-versions.md](docs/base-versions.md).

## [1.0.0] — unreleased

Built on `slax-32bit-debian-12.2.0.iso`
(`03b85cd259883f6781b3a3f30ed409b0b6a542b8f510094594c7600bd94e546b`), with slax-kitchen pinned at
`bcd4f00`.

**Two images, same system.** `slax-wine-bios-1.0.0.iso` (507.3 MiB) uses the stock Slax bootloader.
`slax-wine-uefi-1.0.0.iso` (513.5 MiB) adds upstream's `uefi-bootable` recipe — a GRUB EFI loader in
an El Torito ESP — and is a **superset**: it keeps the BIOS entry, so it boots everywhere the first
does, and UEFI additionally works from an **ext4** stick because GRUB reads ext4 where
`syslinux.efi` does not. Both carry the same nine bundles.

### Added
- `wine` — Wine 8.0~repack-4 from Debian bookworm main as `20-wine.sb` (166.6 MiB), with
  `05-chromium.sb` removed first to pay for it.
- `wine-desktop` — launcher entry, `WINEARCH`/`WINEDLLOVERRIDES` defaults, the `slax-wine` wrapper
  and `/etc/slax-wine-release`, as `21-wine-desktop.sb` (4 KiB).
- `notepadpp` — the Notepad++ 8.9.8 NSIS installer and its launcher as `30-notepadpp.sb` (6.4 MiB),
  the swappable application layer.
- `slax-wine-iso` — `automount` removed from the boot line, ISO identity, sha256 beside the image.
- `build.sh`, eleven commit gates, and the engineering documentation set.
- `uefi-bootable` — **upstream's** recipe, applied only by `profiles/slax-wine-uefi.yaml`. Builds no
  bundle; adds one 6.2 MiB `boot/efi.img`.

### Known limitations
- **Persistence: half observed, half still not.** The **ext4 native perch** path now survives a
  reboot in a VM — two boots on one disk, marker written and `sync`ed on the first, found on the
  second. The **FAT32 route is untested**: no dynfilefs container, no XFS, no `perchsize=`, no
  `xfs_growfs`, and nothing has run `bootinst` or booted from a real stick. So the Wine `C:` drive
  surviving on the kind of stick most people will use is still read from source, not measured.
- **UEFI is untested on a slax-wine image.** The `slax-wine-uefi` variant carries a loader upstream
  boot-tests on our exact target, but we have not run it; and the `slax-wine-bios` route from a stick
  uses a different loader (`syslinux.efi`) that nothing has exercised.
- `automount` removal is still unverified — see the `slax-wine-iso` cookbook page.
- No Wine Mono or Wine Gecko, so .NET and embedded-HTML applications do not run. Debian packages
  neither; the first-run prompt is suppressed rather than satisfied.
- No GPU firmware, because stock Slax ships none — 3D under Wine falls back to software rendering.
- No browser: `05-chromium.sb` is removed. It is gone from the xlunch launcher; the Fluxbox
  right-click menu still carries a "Web Browser" entry that offers to `apt install` one, because
  that menu is a static file in a stock bundle. See
  [wine-desktop](docs/50-cookbook/wine-desktop.md).
- **No 32-bit UEFI.** Slax ships only `bootx64.efi` and no `bootia32.efi`, so machines with 32-bit
  UEFI firmware and no legacy/CSM cannot boot this image by any route. 64-bit UEFI from a FAT32
  stick is expected to work but has **not** been tested here — only a direct-kernel boot was run.
- Releases are **unsigned by choice** — this project has no signing key. (`iso.checksums: sign`
  was unusable upstream when this was written; that was our issue 3 and it was fixed in `7971eb5`,
  which is in the pinned engine.)
