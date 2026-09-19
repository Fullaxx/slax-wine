# Using Bottles on slax-bottles

slax-bottles is 64-bit Slax with [Bottles](https://usebottles.com) baked in: the Flatpak, its
GNOME runtime, and everything it needs to create a bottle **with no network**. It does not include
slax-wine's Debian Wine or Notepad++. Bottles brings its own Wine
([DECISIONS.md](DECISIONS.md) D-14).

## First run

Open **Bottles** from the launcher (Super, or Alt+F2). The first start takes a while: flatpak builds
its `ld.so` cache and GTK starts up, and on a machine without GPU acceleration that is noticeably
slow.

**Offline, the welcome wizard cannot finish, and that is expected.** Its last page tries to download
components, fails, and offers **Skip Setup**. Take it. Everything a bottle needs is already on the
image:

| component | what ships | where |
|---|---|---|
| runner | `sys-wine-11.0`, the Wine inside the Bottles Flatpak itself | the Flatpak |
| DXVK | `dxvk-3.1` | `~/.var/app/com.usebottles.bottles/data/bottles/dxvk/` |
| VKD3D | `vkd3d-proton-3.0.1` | `~/.var/app/com.usebottles.bottles/data/bottles/vkd3d/` |
| Wine Gecko / Mono | Flathub's `org.winehq.Wine.gecko` and `.mono` | the Flatpak runtimes |

**Measured, offline** (QEMU, no network device): Bottles 67.3 opens; the wizard ends in "Setup
could not be completed", with Skip Setup; `bottles-cli new --bottle-name offline1 --environment
application --runner sys-wine-11.0` creates a bottle; in it, `cmd /c ver` prints `Microsoft Windows
10.0.19045`, and `notepad.exe` opens a window on the Slax desktop. Creating the bottle took about 19
minutes under software emulation (no KVM). It has not been timed on real hardware.

**Without DXVK and VKD3D on disk, the same `bottles-cli new` fails** ("Missing essential components
… tried 3 times"), even though the runner is present. That measurement is why they ship.

Online, Bottles should behave as it does on any desktop, fetching other runners, newer DXVK and
dependencies (vcredist, .NET, fonts) from its repositories. **That has not been tested on this
image**: every run so far was offline.

## Where things live

Everything Bottles writes goes to `/root/.var/app/com.usebottles.bottles/`. On a plain boot that is
RAM, and your bottles are gone at shutdown. **On a persistent stick they survive**, the same way
slax-wine's `C:` drive does. [INSTALL.md](../INSTALL.md) covers setting up persistence. Budget the
space: a fresh bottle is **386 MiB** (measured) before you install anything into it.

## Files outside the sandbox

Bottles is a Flatpak, so it sees only what its sandbox allows. To run an installer from a USB stick
or `/root`, either copy it into a path Bottles can see, or grant access with Flatpak's standard
override (not yet exercised on this image):

```sh
flatpak override com.usebottles.bottles --filesystem=/media
flatpak override com.usebottles.bottles --filesystem=home
```

On a non-persistent boot the override is lost at shutdown, like everything else.

## Command line

The wrapper behind the launcher tile:

```sh
slax-bottles                     # the GUI
```

Bottles' own CLI is inside the Flatpak:

```sh
B="flatpak run --command=bottles-cli com.usebottles.bottles"
$B list bottles
$B new --bottle-name mygame --environment gaming --runner sys-wine-11.0
$B run -b mygame -e /path/to/setup.exe
$B shell -b mygame -i "cmd /c ver"
```

## Updating

Nothing updates by itself, and offline nothing can. Online:

```sh
flatpak update com.usebottles.bottles
```

The Flathub remote is already configured. On a non-persistent boot an update lands in RAM and is
gone at shutdown. A permanent update means a rebuild, which bumps the pin in `build.env`
(see [build.md](build.md), `BOTTLES_RELOCK`).

## What does not work, or is not known

- **3D acceleration is whatever Mesa manages on your hardware.** Stock Slax ships no GPU firmware
  (D-10), and that is unchanged here. Without `amdgpu` or `i915` firmware you get llvmpipe:
  software rendering, fine for applications, poor for games.
- **No `xdg-desktop-portal`.** It is not installed, and how Bottles' file choosers behave without
  it has not been tested. `bottles-cli` with a path (above) avoids the question.
- **Real hardware is untested.** Every observation above is from QEMU. Under QEMU's `-cpu max`,
  Bottles segfaulted in llvmpipe on an AVX2 instruction; with `-cpu Nehalem` it ran. We read that
  as QEMU's TCG AVX2 emulation rather than a fault in the image, but it has not been confirmed on
  real AVX2 hardware.
