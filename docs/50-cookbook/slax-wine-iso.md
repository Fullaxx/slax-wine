# `slax-wine-iso` — label the image, and stop `automount` grabbing every disk

**Status: runtime-verified** — the volume id, application id and checksum are confirmed in the built
image and 21 structure assertions pass including `--volid SLAX-WINE`; and this recipe's only
functional change, removing `automount` from the boot line, has now been **observed taking effect
through both bootloaders**.

## How the `automount` removal was proven

Measured 2026-09-18 on a KVM host, against `slax-wine-test` (this image plus `serial-console` and
`testkit`). The observable is the kernel's own `Kernel command line:` line in the serial log:

| boot route | cmdline comes from | `automount` | reached `Live Kit done` |
|---|---|---|---|
| `kitchen test --kernel` | the **harness**, which adds it | **present** | yes |
| `kitchen test --bios` | `isolinux.cfg`, serial entry | **absent** | yes |
| `kitchen test --uefi` | GRUB, generated from `isolinux.cfg` | **absent** | yes |

**The first row is the point.** A check that only ever reports "absent" proves nothing; the
`--kernel` route boots with a cmdline that *does* carry the flag, so the same grep on the same log
format demonstrably detects it. Without that control the other two rows would be indistinguishable
from a broken test.

Both bootloader rows selected the **serial entry** — which is how there is any userspace output to
read at all, since only that entry routes `/dev/console` to `ttyS0`.

Two traps worth writing down, both hit while doing this:

- **`grep -c automount <log>` is wrong.** systemd logs `Set up automount … Automount Point` later in
  every boot. Grep the `^Kernel command line:` line specifically.
- **`/media` is not a usable probe**, though it looks like one. `fstab_create` returns before its
  `mkdir -p /media/<dev>` when the flag is absent, and `/media` ships in no bundle — but it only
  creates a mountpoint for a device that is *not* the boot device, and a plain boot has only the CD.
  Measured: the `--kernel` route, **with** `automount`, still reported `file /media: absent`. It
  reads "absent" either way. `profiles/slax-wine-test.yaml` records this so nobody re-adds it.

Reproducing it, which matters more than the logs — `out/` is gitignored, so a fresh clone has no
evidence files, only the means to regenerate them:

```sh
./build.sh --test                      # profiles/slax-wine-test.yaml: + serial-console, + testkit
K=vendor/slax-kitchen/kitchen; I="$PWD/out/slax-wine-test-1.0.0.iso"
$K test "$I" --kernel                  # the control: its cmdline HAS automount
$K test "$I" --bios
$K test "$I" --uefi
grep -a '^Kernel command line:' out/boot-tests/slax-wine-test-1.0.0-*.serial.log
```

Expect `automount` on the `-kernel` line and on neither of the others. **A UEFI run needs KVM**: at
the shipped `menu_timeout` of 5 the harness gets a 2-second keystroke lead, which is correct under
KVM and misses the menu under TCG — and a missed menu boots the *default* entry, so the test would
assert against a boot it never selected. These runs were made on a KVM host for that reason.

**What this does not cover:** the shipped images byte-for-byte — the tested image adds
`serial-console` and `testkit`. The boot configs are otherwise identical, and the removal is applied
to *every* `APPEND` line in both files, so it transfers.

```sh
./build.sh
```

Three small steps that make the output a release artifact rather than an anonymous ISO.

## `automount` has to be removed, not negated

`noautomount` does not work, and the reason is a substring:

```sh
$ echo 'vga=normal rw noautomount' > /tmp/c
$ grep -vq automount /tmp/c && echo skip || echo "proceed  <-- noautomount ignored"
proceed  <-- noautomount ignored
```

`fstab_create` tests `grep -vq automount /proc/cmdline`, and `noautomount` *contains* `automount`, so
the test never short-circuits. This is upstream Slax issue 12, not a slax-kitchen bug. The flag has
to be absent, which is what `boot.cmdline remove:` does.

Worth doing deliberately on a machine that will see game files and foreign sticks: with `automount`,
every other disk gets a `/media/<dev>` line in `/etc/fstab` at boot.

## There is deliberately no `perchsize`

An earlier draft baked `perchsize=32G` into the boot line. That was wrong three ways, and the reasons
are worth keeping:

- the FAT32 perch container has a **16 GB floor that cannot be lowered**;
- its size is **fixed at creation** and can only ever be raised;
- the right value depends on a stick this ISO knows nothing about.

And a fourth, which is the sharp one: persistence is enabled by a bare **substring** match on
`perch`, so an unscoped `perchsize=` would switch persistence on for the `toram` entry — which
unmounts the medium and has nowhere to write.

It belongs at the boot prompt, per stick. [INSTALL.md](../../INSTALL.md) has the table.

**The same substring rule bites the person typing at that prompt**, and it cost a real session here
before it was written down. `perch` is matched anywhere in the command line, so `perch=` — or any
other near-miss containing those letters — enables persistence, finds no `perchdir=` naming a device,
falls back to the boot medium's own `slax/changes`, discovers that a CD is read-only, prints
`* Persistent changes not writable or not used`, and runs in RAM. One line, gone the moment X starts.

Worth holding onto because this recipe is the reason the boot line is hand-edited at all: it keeps
the menu minimal and per-machine rather than baking in a `perchsize=` or a `perchdir=`. That is still
the right call, but it means the person at the prompt carries the risk, so
[INSTALL.md](../../INSTALL.md#the-near-miss-that-costs-you-the-session) now names the three lines a
good persistent boot prints and the one line a near-miss prints.

Note also that the parameter is needed on **every** boot when booting the ISO with a disk attached:
the menu's *Restore previous session* entry is `MENU DISABLED` on optical media. A `bootinst` stick
has that entry live and needs no typing — which is the real argument for the stick route over
booting an ISO with a scratch disk.

## The version is not in any YAML

`iso.metadata` sets a version-free `appid`; `build.sh` passes the real one with
`kitchen pack --appid`, where a command-line flag beats a recipe hint. So no version string exists in
a recipe where it could drift from the git tag — and someone running `kitchen apply` and
`kitchen pack` by hand still gets an image that identifies itself honestly.

`volid` is the one people see: it becomes the filesystem label when the image is mounted or written
to a stick. It is also why this project does not use `kitchen build` — that runs
`tests/structure/iso_assert.py` with no `--volid`, and the argument *defaults* to `slax`
(`iso_assert.py:49`), so every build would fail its own test. The default is an argparse default, not
a hardcoded constant; what makes it unavoidable is that `lib/build.sh` never passes the flag.

## No signature, for now

`iso.checksums` takes a `sign:` key holding a GPG key id. It **used to be unusable** — the step
schema had been closed to `{"type": "boolean"}`, so the documented `sign: "your-key-id"` was a
validation error and the only schema-legal truthy value failed inside `gpg`. We reported that as
[UPSTREAM.md](../UPSTREAM.md) issue 3 and it was fixed in `7971eb5`: at the pinned commit the schema
types the field `["string", "boolean"]` and `lib/pack.sh` quote-strips the key id before calling
`gpg --detach-sign`.

So the omission is now **a choice, not a limitation**: this project has no signing key. Adopting one
means deciding whose key signs a release and how a downloader is expected to obtain and trust it,
which is a bigger question than a YAML line. A signed release is a post-v1.0.0 want.

## Verified

```
21 passed, 0 failed
  ok   volume id is SLAX-WINE
  ok   /slax/modules/98-dpkg-db.sb present
  ok   size <= 532 MiB
```

The checksum is written from the output directory, so the filename inside it is **relative** and
`sha256sum -c` works wherever the pair is downloaded to. Note the hash is per *build*, not per
version — `genisoimage` stamps PVD timestamps it cannot pin, so a rebuild of the same tree produces
the same bytes everywhere except those fields. See [sizing.md](../sizing.md):

```
<this build's sha256>  slax-wine-bios-1.0.0.iso
```

## What `kitchen probe` says, and why that is right

```
verdict    : MODIFIED (4 unexplained differences)
explained by recipes:
  bundles.05-chromium.sb      <- remove-chromium
  iso.preparer_id             <- iso-identity
  iso.publisher_id            <- iso-identity
  iso.volume_id               <- iso-identity
unexplained:
  bundles.20-wine.sb          expected 'absent', got 'ADDED'
  bundles.21-wine-desktop.sb  expected 'absent', got 'ADDED'
  bundles.30-notepadpp.sb     expected 'absent', got 'ADDED'
  bundles.98-dpkg-db.sb       expected 'absent', got 'ADDED'
```

**"Unexplained" is the expected result for a fork.** `probe` attributes differences to recipes it
ships, and it has never heard of ours. The four it cannot place are exactly our four bundles, and the
four it can place are exactly the changes we made with its own recipes' verbs. Nothing is
unaccounted for — a difference appearing here that is *not* one of those eight would be the signal.

| you want | use |
|---|---|
| to install the result | [INSTALL.md](../../INSTALL.md) |
| the size ledger | [sizing.md](../sizing.md) |
| what a release promises | [NOTICE.md](../../NOTICE.md) |
