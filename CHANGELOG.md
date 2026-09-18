# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are semver.

A release is defined by **both** halves — the slax-wine version and the base ISO it was built on.
See [docs/base-versions.md](docs/base-versions.md).

## [1.0.0] — unreleased

Built on `slax-32bit-debian-12.2.0.iso`
(`03b85cd259883f6781b3a3f30ed409b0b6a542b8f510094594c7600bd94e546b`).

### Added
- `wine` — Wine 8.0~repack-4 from Debian bookworm main as `20-wine.sb` (166.6 MiB), with
  `05-chromium.sb` removed first to pay for it.
- `wine-desktop` — launcher entry, `WINEARCH`/`WINEDLLOVERRIDES` defaults, the `slax-wine` wrapper
  and `/etc/slax-wine-release`, as `21-wine-desktop.sb` (4 KiB).
- `notepadpp` — the Notepad++ 8.9.8 NSIS installer and its launcher as `30-notepadpp.sb` (6.4 MiB),
  the swappable application layer.
- `slax-wine-iso` — `automount` removed from the boot line, ISO identity, sha256 beside the image.
- `build.sh`, eleven commit gates, and the engineering documentation set.

### Known limitations
- **Persistence is unverified.** The image is `runtime-verified` on a full desktop boot — the Wine
  tile opens, the Notepad++ installer runs under Wine, no Mono/Gecko prompt, no browser — but that
  was a **non-persistent** boot. Nothing has yet been shown to survive a reboot, so the persistent
  Wine `C:` drive on a USB stick, which is the point of [INSTALL.md](INSTALL.md), is still untested
  on hardware. Neither is `automount` removal, nor UEFI.
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
