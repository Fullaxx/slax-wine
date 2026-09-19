# Which Slax each release is built on

The base ISO is not in the output filename, so this table is the authority. A release is defined by
**both** halves: the slax-wine version and the exact base it was built on. Changing either is a
version bump.

| slax-wine | Slax | base ISO | base sha256 |
|---|---|---|---|
| 1.0.0 (slax32-wine-bios, -uefi) | 12.2.0 (Debian 12 bookworm, 32-bit) | `slax-32bit-debian-12.2.0.iso` | `03b85cd259883f6781b3a3f30ed409b0b6a542b8f510094594c7600bd94e546b` |
| 1.0.0 (slax-bottles) | 12.2.0 (Debian 12 bookworm, **64-bit**) | `slax-64bit-debian-12.2.0.iso` | `61d9fdcc006938d6fd6f231e22d8af926ae8f48fdf0487b8010e69f3bd17cf70` |

## How that pairing is enforced

Four places say it. **Two are checked**; the other two are the source and a derived value:

| where | checked by |
|---|---|
| `build.env` — the single source of truth | — *(it is what everything else is checked against)* |
| `vendor/slax-kitchen/compat/sources.yaml`, via the submodule pin | **checked** — `ci/checks/96-release-consistency.sh` cross-checks file, size and sha256 |
| `/etc/slax-wine-release` / `/etc/slax-bottles-release` inside the image | **checked** — the same gate matches the recipes' lines whole and literal |
| the ISO's application id | *not checked* — `build.sh` **sets** it from `build.env` with `kitchen pack --appid`, which is not the same as verifying it |

and `kitchen fetch --verify-only` re-checks the bytes on every build, so a base that does not match
fails before anything is unpacked.

slax-bottles has a third half as well: its Flatpak installation, which comes from Flathub, not
Debian. That is pinned ref-by-ref in `BOTTLES_LOCK` and checked by `build.sh` against the deployed
commits, and DXVK/VKD3D by sha256 in `BOTTLES_COMPONENTS`. Changing either is also a version bump.

## Upstream has not moved since 2023

Slax 12.2.0 was released 2023-10-10 and there has been no release since, so this table is expected to
stay short. slax-kitchen runs a weekly `upstream-watch` job that opens an issue if that changes.

**Debian bookworm is still live** — `oldstable`, security-supported into 2028 — which is what makes
the Wine packages reachable. When bookworm eventually moves to `archive.debian.org` a rebuild of
v1.0.0 will not be byte-identical; the published artifact and its sha256 are the authority, not the
recipe. `snapshot.debian.org` is the escape hatch.
