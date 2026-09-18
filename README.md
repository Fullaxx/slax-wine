# slax-wine

Slax with Wine on it: a 32-bit Debian live system that runs Windows programs, with a persistent
`C:` drive when you install it to a USB stick.

```sh
git clone --recurse-submodules https://github.com/Fullaxx/slax-wine
cd slax-wine && ./build.sh          # -> out/slax-wine-1.0.0.iso
```

Needs `squashfs-tools`, `xorriso`, `curl` and a `python3` with `yaml` — and root (or `sudo`) for one
step. [docs/build.md](docs/build.md) has the full list, the hook setup, and the one `sudo` trap that
is not obvious.

## What you get

| | |
|---|---|
| Wine | **8.0~repack-4**, Debian bookworm main, 32-bit |
| a test application | Notepad++ 8.9.8 — the Windows installer, run under Wine |
| no browser | `05-chromium.sb` is removed to pay for Wine's size |
| ISO | **507.3 MiB** — 91.4 MiB over stock Slax |

Installing it to a USB stick so the Wine prefix survives a reboot is **[INSTALL.md](INSTALL.md)**.
What works and what does not is **[docs/using-wine.md](docs/using-wine.md)**.

## How it is built

Four recipes over [slax-kitchen](https://github.com/Fullaxx/slax-kitchen), pinned as a submodule.
slax-kitchen is the engine — generic, and knowing nothing about Wine; the recipes here say *what* to
change, never *how*.

| bundle | recipe |
|---|---|
| `20-wine.sb` | [`wine`](docs/50-cookbook/wine.md) — install Wine, drop Chromium to pay for it |
| `21-wine-desktop.sb` | [`wine-desktop`](docs/50-cookbook/wine-desktop.md) — launcher, environment, menu cleanup |
| `30-notepadpp.sb` | [`notepadpp`](docs/50-cookbook/notepadpp.md) — the swappable application layer |
| — | [`slax-wine-iso`](docs/50-cookbook/slax-wine-iso.md) — boot defaults, ISO identity, checksum |

`30-notepadpp.sb` is meant to be replaced. Delete that one file from `/slax/modules/` on a stick and
drop another in — no rebuild, no remaster. That is the whole point of the layering.

## Status

**boot-verified.** The image boots to `slax login:` with all nine bundles mounted in order.
**It is not `runtime-verified`** — Wine has not yet been observed running a Windows program on real
hardware. Every page states the rung it actually reached; the ladder is in the
[cookbook index](docs/50-cookbook/README.md).

## Documentation

| you want | read |
|---|---|
| to build it | [docs/build.md](docs/build.md) |
| to put it on a stick, with persistence | [INSTALL.md](INSTALL.md) |
| to use Wine, and what is missing | [docs/using-wine.md](docs/using-wine.md) |
| how it all works | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| why it looks like that | [docs/DECISIONS.md](docs/DECISIONS.md) |
| how we raise engine problems upstream | [docs/UPSTREAM.md](docs/UPSTREAM.md) |
| where the 507 MiB goes | [docs/sizing.md](docs/sizing.md) |
| which Slax each release is built on | [docs/base-versions.md](docs/base-versions.md) |
| what redistributing the ISO obliges | [NOTICE.md](NOTICE.md) |

## Credit

**Slax and Linux Live Kit are the work of [Tomáš Matějíček](https://github.com/Tomas-M).** This
project customizes *his*; without it there is nothing here. There is a donate link on
[slax.org](https://www.slax.org).

**Wine** is the [WineHQ project](https://www.winehq.org); **Notepad++** is
[Don Ho's](https://notepad-plus-plus.org). Neither is modified here.

MIT for this repository's own recipes, scripts and docs — see [LICENSE](LICENSE). Everything inside
a built ISO carries its own licence, and [NOTICE.md](NOTICE.md) sets out the boundary and the
obligations that come with redistributing an image.
