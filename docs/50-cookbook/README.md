# Cookbook

One page per recipe. Each states what it does, what it measured, and what it cannot do.

| recipe | what it does |
|---|---|
| [`wine`](wine.md) | install Wine 8.0 from bookworm main, and drop Chromium to pay for its size |
| [`wine-desktop`](wine-desktop.md) | launcher entry, environment defaults, and masking the browser we removed |
| [`notepadpp`](notepadpp.md) | the swappable application layer — a Windows installer to run under Wine |
| [`slax-wine-iso`](slax-wine-iso.md) | boot defaults, ISO identity, and a checksum beside the image |

All four are applied, in that order, by **both** shipped profiles:
[`slax-wine-bios`](../../profiles/slax-wine-bios.yaml) and
[`slax-wine-uefi`](../../profiles/slax-wine-uefi.yaml), which adds upstream's `uefi-bootable` after
them. Both also list upstream's `remove-bundle` **first** — it has no page here because it is not
ours; it drops `05-chromium.sb` with a pattern each profile states rather than inherits, and the
engine refuses a plan where a removal follows anything that builds. The profiles are authoritative —
`build.sh` drives them with `kitchen apply --profile`, and a recipe named by no profile is never
built. `ci/checks/96-release-consistency.sh` fails on an unbuilt recipe, on the two profiles
disagreeing about the core four, and on either of them dropping the removal or listing it late.

## The verification ladder

Every page opens with the rung it actually reached, in slax-kitchen's vocabulary:

`schema-valid` → `gate-clean` → `matrix-verified` → `artifact boot-verified` → `boot-verified` →
`runtime-verified`

**Matrix-verified is not boot-verified, and boot-verified is not runtime-verified.** A correct file
in the right place is not a working feature. `ci/checks/95-status-vocab.sh` rejects any other word.
