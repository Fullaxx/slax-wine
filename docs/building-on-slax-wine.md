# Building on slax-wine

For a project that takes a slax-wine image as its base and builds its own on top —
[slax-rpgs](https://github.com/Fullaxx/slax-rpgs) is the first. slax-kitchen's
[LAYERING.md](https://github.com/Fullaxx/slax-kitchen/blob/0dd1b53/LAYERING.md) is the model: a
project builds on another project's released **image**, not its source, and vendors the engine
itself. This page is slax-wine's side of that:
[what a base project owes](https://github.com/Fullaxx/slax-kitchen/blob/0dd1b53/LAYERING.md#what-a-base-project-owes-the-projects-built-on-it)
the projects built on it, answered for these images, with where each answer was measured.

## Which image to build on

**Any of them, with `uefi-bootable` listed last** if your image should boot on UEFI, as
[LAYERING.md's step 6](https://github.com/Fullaxx/slax-kitchen/blob/0dd1b53/LAYERING.md#what-a-consumer-does)
says.

| you build on | `uefi-bootable` |
|---|---|
| a `-bios` image | builds the ESP and GRUB menu the image never had |
| a `-uefi` image, or slax-bottles | rebuilds the ESP the image came with, from *your* boot menu. That is a rebuild, not a second application |

Projects were built on all three kinds of base at the `0dd1b53` pin
([the record](UPSTREAM.md#adopted-at-the-0dd1b53-bump)):

- **On `slax64-wine-bios` and `slax64-wine-uefi`:** a profile shaped like LAYERING.md's example —
  our Notepad++ bundles removed, a bundle of its own at `30`, its own volume id, `uefi-bootable`
  last — was green, with the structure test passing.
- **On `slax-bottles`:** a profile that only set its own identity and listed `uefi-bootable` was
  green too.

Each was built and structure-tested on one base and not booted, which is short of
`matrix-verified`.

**Our ESPs are exactly what `uefi-bootable` builds**: FAT12, labelled `SLAXEFI`, holding only an
unsigned `EFI/BOOT/BOOTX64.EFI`, which is the one shape it agrees to replace. That was measured on
`slax64-wine-uefi`
([the record](UPSTREAM.md#measured-at-7664625-a-project-built-on-our-images-and-kitchen-sources-on-them)),
and every ESP here comes from that one recipe, unmodified.
Nothing here signs a loader or adds one. A release that ever does will say so in its notes, because
`uefi-bootable` would then refuse that ESP, naming what it found, and you would build on the
`-bios` image instead.

**The one wrong choice is a UEFI image without `uefi-bootable`.** The UEFI boot entry is written
when an image is mastered, so it does not carry over: your image would ship our ESP with nothing
pointing at it. `kitchen pack` warns, and `kitchen test --structure` fails it.

## Pinning it

- **Pin the image by file name and sha256.** Each image has `<image>.iso.sha256` beside it, with the
  file name inside written relative, so `sha256sum -c` works wherever the pair lands.
- **Vendor the engine yourself, at the commit that built the image**: `kitchen.commit` in
  `<image>.iso.provenance.json`. `CHANGELOG.md` names the same pin for each release. If you boot
  your tests on a boot host, its `boot-host.ini` goes inside that vendored engine, the only place the
  engine reads it, where the engine's own `.gitignore` already keeps it out of your repository.
- **Until a release is published, pin a local build.** Only the machine that built it has those
  bytes: images are
  [not byte-reproducible](https://github.com/Fullaxx/slax-kitchen/blob/0dd1b53/docs/40-workflow/reproducibility.md).

## The release file, and the browser mask

Every slax-wine image carries `/etc/slax-wine-release`, in `21-wine-desktop.sb`:

| field | holds |
|---|---|
| `NAME` | `slax-wine` |
| `VERSION` | the slax-wine version, which gate 96 binds to `build.env` |
| `BASE_ISO`, `BASE_SHA256` | the stock Slax ISO the image was built on |
| `WINE` | the Wine version, and where it came from |
| `HOME_URL` | this repository |

It describes the platform, and it stays true in your image, whose Wine came from slax-wine. Write
your own release file beside it, `/etc/slax-rpgs-release` say, rather than replacing it. It lives
in the platform bundle rather than a product-only one because it is the one record inside the image
of which platform it carries.

`21-wine-desktop` also masks `5chromium.desktop`, with `Hidden=true` and `NoDisplay=true`: every
slax-wine image removes `05-chromium.sb`, but that launcher entry lives in stock `03-desktop.sb`
([wine-desktop](50-cookbook/wine-desktop.md)). A project that adds a browser back ships its own
launcher entry in a bundle numbered above `21`, because the higher bundle wins.

## Bundle numbers

| range | whose | on our images |
|---|---|---|
| `00`–`09` | upstream Slax and slax-kitchen | `01-core`, `01-firmware`, `02-xorg`, `03-desktop`, `04-apps`; `05-chromium` removed |
| `10`–`19` | the bottom of the band slax-kitchen gives projects, left to its example recipes (`10`–`16` today) | none |
| `20`–`29` | **slax-wine's platform**: keep these | `20-wine`, `21-wine-desktop` |
| `30`–`89` | **applications**: yours to replace | `30-notepadpp32`, and `31-notepadpp64` on 64-bit |
| `90`–`97` | slax-kitchen headroom | none |
| `98` | the package database | regenerated by your own `kitchen pack` |

Remove ours first — `remove-bundle` with `drop: "^3[01]-notepadpp(32|64)\\.sb$"` — and take `30`–`89`
for your own. An application bundle sources `/etc/profile.d/wine.sh` from `21-wine-desktop.sb`,
runs `20-wine.sb`'s Wine, and ships its own `.desktop` entry: that is
[the swap contract](ARCHITECTURE.md#the-swap-contract). Give the entry an absolute `Icon=` path and
`Terminal=false`. Slax's launcher drops a tile whose icon file does not exist, and wraps a command
that does not link `libX11` itself in an xterm
([wine-desktop](50-cookbook/wine-desktop.md) has both). slax-bottles divides the same way, with
`20-flatpak` its platform and `30-bottles` its application.

The split is a promise to the projects built on these images. Moving a platform bundle out of
`20`–`29`, or an application out of `30`–`89`, would break them
([D-5](DECISIONS.md#d-5--bundles-at-20213031)).

## What each image already applied

Do not apply these again. The engine cannot warn you: the journal that records what ran lives in our
work tree, not in the image.

- **The list is the profile, and the record is the sidecar.** `profiles/<image>.yaml` names the
  recipes in order, and each image's `<image>.iso.provenance.json` records what ran:
  `jq -r '.recipes[].recipe'` on `slax64-wine-uefi` prints `remove-bundle`, `wine`,
  `wine-desktop`, `notepadpp32`, `notepadpp64`, `slax-wine-iso` and `uefi-bootable`.
- **`uefi-bootable` is the exception.** List it again, last, as above.
- **`slax-wine-iso`'s boot-menu edit is the one that bites.** It removed `automount` from every
  boot entry our image has, and that carries over. An entry *you* add brings its own command line,
  though, and `serial-console`'s is stock Slax's, with `automount` in it: measured at `0dd1b53`
  ([the record](UPSTREAM.md#adopted-at-the-0dd1b53-bump)). If you add entries and want our default,
  remove it again after them. Our own test profiles list `serial-console` first for the same reason.
- **What does not carry over** is what gets written when an image is mastered: the volume id and the
  rest of the identity, the UEFI boot entry, and a hybrid MBR, which none of ours has. Write your
  own, as LAYERING.md's steps 5 and 6 say.

## Moving to a new slax-wine release

1. Read `CHANGELOG.md`, and check the new image's sha256.
2. Rebuild, and run `kitchen diff old.iso new.iso --bundles` to see what changed underneath you.
3. Move your engine to the new sidecar's `kitchen.commit`, unless you have a reason not to.

[UPSTREAM.md](UPSTREAM.md) records our review of every engine commit a bump took, in its *Adopted
at* sections. Read them, but your own bar still applies. There is no CI here, so each release's
notes say what ran in its place: the gates, every image's build assertions, and the boot routes.

## Working around a slax-wine bug

File it [here](https://github.com/Fullaxx/slax-wine/issues), and mark the code
`WORKAROUND https://github.com/Fullaxx/slax-wine/issues/N`. The repository goes in the marker as
well as the number, as LAYERING.md asks, so that a marker for our bug is not read as one for the
engine's.

## Publishing your image

The engine's release procedure does not support an image built on another project's image yet
([LAYERING.md](https://github.com/Fullaxx/slax-kitchen/blob/0dd1b53/LAYERING.md#provenance-and-publishing)).
Our own images do not pass it either, for two reasons that carry into yours
([the record](UPSTREAM.md#measured-at-7664625-a-project-built-on-our-images-and-kitchen-sources-on-them)):

- the Notepad++ installers are copied from a staging directory the commit does not hold
  ([D-7](DECISIONS.md#d-7--fetch-the-payload-do-not-commit-it)), which dropping `30` and `31`
  removes;
- stock Slax's `01-firmware.sb` has no licence texts, which stays unless you add `firmware-refresh`
  or remove `01-firmware`, the two remedies the engine names.

How slax-wine itself publishes is [Cutting a release](build.md#cutting-a-release).
