# Cookbook

One page per recipe. Each states what it does, what it measured, and what it cannot do.

| recipe | what it does |
|---|---|
| [`wine`](wine.md) | install Wine 8.0 from bookworm main: the i386 build on the 32-bit base, `wine64` and `wine32` on the 64-bit one |
| [`wine-desktop`](wine-desktop.md) | launcher entry, environment defaults, and masking the browser we removed |
| [`notepadpp32`](notepadpp32.md) | the 32-bit (x86) Notepad++ installer, to run under Wine — on every slax-wine image |
| [`notepadpp64`](notepadpp64.md) | the 64-bit (x64) Notepad++ installer — **slax64-wine only** |
| [`slax-wine-iso`](slax-wine-iso.md) | boot defaults, ISO identity, and a checksum beside the image |
| [`bottles`](bottles.md) | **slax-bottles only**: flatpak, and Bottles with its runtimes, DXVK and VKD3D baked in |
| [`slax-bottles-iso`](slax-bottles-iso.md) | **slax-bottles only**: the same boot default and checksum as `slax-wine-iso`, with its own identity |

The first five recipes are slax-wine's, which is four images: bios and uefi on each base.
`wine`, `wine-desktop` and `slax-wine-iso` serve both bases: each carries one step per base, guarded
by `when: arch==32bit` or `arch==64bit`, and only the one matching the base runs.

| profile | base | recipes, after upstream's `remove-bundle` |
|---|---|---|
| [`slax32-wine-bios`](../../profiles/slax32-wine-bios.yaml) | 32-bit | `wine`, `wine-desktop`, `notepadpp32`, `slax-wine-iso` |
| [`slax32-wine-uefi`](../../profiles/slax32-wine-uefi.yaml) | 32-bit | the same, then upstream's `uefi-bootable` |
| [`slax64-wine-bios`](../../profiles/slax64-wine-bios.yaml) | 64-bit | `wine`, `wine-desktop`, `notepadpp32`, `notepadpp64`, `slax-wine-iso` |
| [`slax64-wine-uefi`](../../profiles/slax64-wine-uefi.yaml) | 64-bit | the same, then upstream's `uefi-bootable` |

Every shipped profile lists upstream's `remove-bundle` **first** — it has no page here because it is
not ours; it drops `05-chromium.sb` with a pattern each profile states rather than inherits, and the
engine refuses a plan where a removal follows anything that builds. The profiles are authoritative —
`build.sh` drives them with `kitchen apply --profile`, and a recipe named by no profile is never
built. `ci/checks/96-release-consistency.sh` fails on an unbuilt recipe; on the profiles of one base
disagreeing about their recipes; on the 64-bit list being anything but the 32-bit one plus
`notepadpp64`; on a profile whose name does not match its base or firmware; and on any shipped profile
dropping the removal or listing it late.

The last two belong to a different image, [`slax-bottles`](../../profiles/slax-bottles.yaml): 64-bit
Slax, `remove-bundle`, then `bottles`, `slax-bottles-iso` and `uefi-bootable`. It uses none of the
Wine recipes. Bottles is sandboxed and brings its own Wine, so it could not use ours
([DECISIONS.md](../DECISIONS.md) D-14). Gate 96 holds it to removal-first, but not to the slax-wine
recipe list.

## The verification ladder

Every page opens with the rung it actually reached, in slax-kitchen's vocabulary:

`schema-valid` → `gate-clean` → `matrix-verified` → `artifact boot-verified` → `boot-verified` →
`runtime-verified`

**Matrix-verified is not boot-verified, and boot-verified is not runtime-verified.** A correct file
in the right place is not a working feature. `ci/checks/95-status-vocab.sh` rejects any other word.
