# `slax-wine-iso` — label the image, and stop `automount` grabbing every disk

**Status: boot-verified** — the volume id, application id and checksum are confirmed in the built
image, 21 structure assertions passed including the `--volid SLAX-WINE` check, and the image has now
been booted **through its own bootloader** to a full desktop. That is what raised this from
`artifact boot-verified`: the automated run (`kitchen test --kernel`) boots the kernel directly and
never reads `isolinux.cfg` or `syslinux.cfg` at all.

**Not `runtime-verified`, deliberately.** This recipe's only functional change is removing
`automount` from the boot line, and nobody has checked the *effect* — that `/proc/cmdline` lacks the
flag and `/etc/fstab` has no `/media/<dev>` entries for other disks. The edit is correct in the
artifact (2 entries changed in each config, matching `apply.log`). One command on a booted system
would settle it:

```sh
grep -c automount /proc/cmdline; grep /media /etc/fstab
```

Expect `0` and no output. UEFI is also still untested — see [INSTALL.md](../../INSTALL.md).

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
<this build's sha256>  slax-wine-1.0.0.iso
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
