# Installing slax-wine

## First: which of the two images

| | boots on | pick it when |
|---|---|---|
| `slax-wine-bios-<ver>.iso` | BIOS | you know the machine boots BIOS/legacy and you want the stock loader |
| `slax-wine-uefi-<ver>.iso` | **BIOS *and* UEFI** | you want to boot the **ISO itself** on a UEFI machine — a DVD, or a virtual CD in a VM |

The uefi image is a **superset**: it keeps the BIOS boot entry and adds an EFI one, so it boots
everywhere the bios image does, for 6.2 MiB more. **If unsure, take it.**

> **It does not change anything about USB sticks.** Its GRUB loader lives in an El Torito ESP at
> `/boot/efi.img` — an *ISO* structure. A stick has no El Torito catalog, `bootinst.sh` never copies
> it, and the procedure below copies only `slax/`, which does not contain it. What `bootinst`
> relocates is `slax/boot/EFI/Boot/`, and that directory is **byte-for-byte identical in both
> images** (verified). So on a stick, both use the stock FAT-only `syslinux.efi`, and the FAT32
> decision below applies to both equally.
>
> The uefi image's value is booting the **ISO** on UEFI: optical media, or a virtual CD.

---

Three ways to run it. Only one of them keeps your Wine `C:` drive.

| | boots | persistence | Wine `C:` survives a reboot |
|---|---|---|---|
| **Copy to USB or disk + `bootinst`** | BIOS, and UEFI (see the table below) | yes | **yes** |
| Burn to CD/DVD | BIOS | no | no |
| `dd` the ISO to a stick | nothing — see [below](#why-dd-does-not-work) | no | no |

**Use the first one.** It is upstream Slax's supported route, and the only one that gives you
persistence — which is what makes a Wine prefix worth creating.

## One decision, made before you copy anything

The filesystem you put on the stick is the only format choice you make, and it is hard to change
later. Everything else follows from it.

| | **FAT32** | **ext4** |
|---|---|---|
| BIOS boot — either image | yes | yes |
| **UEFI**, `slax-wine-bios` image | **yes** | **no** — `bootinst` relocates `syslinux.efi`, which reads FAT only |
| **UEFI** from a stick — *either* image | **yes** | **no** — `bootinst` relocates `syslinux.efi`, which reads FAT only. The uefi image's GRUB is an ISO structure and never reaches the stick |
| **UEFI**, 32-bit firmware — either image | **no** — see below | **no** |
| Persistence | a sparse container file, **16 GB minimum** | a plain directory, **no limit** |
| Readable from Windows | yes | no |
| Your `C:` drive ends up in | `slax/changes/1/changes.dat` | `slax/changes/1/root/.wine` |

> **32-bit UEFI firmware cannot boot this image at all.** Slax ships only `bootx64.efi` — an
> x86-64 EFI application — and no `bootia32.efi`, on every one of its images including the 32-bit
> ones. A handful of older Atom tablets and netbooks have 32-bit UEFI with no legacy/CSM option, and
> those machines have no supported route: not FAT32, not ext4, not `dd`. Upstream documents this in
> [uefi-usb-hdd](https://github.com/Fullaxx/slax-kitchen/blob/8adfca6/docs/20-boot-sequence/uefi-usb-hdd.md).
> Everything below about "UEFI" means 64-bit UEFI firmware, which is what almost everything has.

> **Persistence on ext4 has now been observed.** Two boots of a slax-wine image on one ext4 perch
> disk: boot 1 wrote a marker into the union and `sync`ed it, boot 2 found it still there
> (`perch-marker: present, written 2026-09-18T11:12:00Z`), both reaching `Live Kit done`. That is the
> **native perch** path — the bind-mount into `slax/changes/N/` that the ext4 column describes.
>
> Its limits, stated so the row is not read as more than it is: a VM, a direct kernel boot, and a raw
> ext4 filesystem on a bare disk image. It did **not** exercise a partition table, `bootinst`, a
> bootloader, or **any** of the FAT32 route — no dynfilefs container, no XFS inside it, no
> `perchsize=`, no `xfs_growfs`. Everything in the FAT32 column is still read from `livekitlib`
> rather than measured.
>
> **What has actually been booted, and by whom.** A slax-wine image has now been UEFI-booted:
> measured 2026-09-18, GRUB under x86-64 OVMF loads `BOOTX64.EFI` and boots the 32-bit kernel to
> `Live Kit done`, in 6 seconds under KVM. That is the `slax-wine-uefi` image's own loader, on our
> own image — not an upstream result borrowed.
>
> It is **not** proof of the stick rows in the table above, and the distinction is the whole point of
> this note: that test boots the **ISO**, through its El Torito catalog. A `bootinst`-prepared stick
> has no such catalog and uses `syslinux.efi` instead — a different loader, unexercised.
> **Nobody has UEFI-booted a slax-wine image from a stick.** Those rows are read from the loaders'
> documented behaviour; treat them as well-founded expectations, not measurements.

Pick by the machine you are booting, not by the stick:

- **UEFI-only machine** (most laptops made after ~2012 with legacy/CSM disabled) → use the
  **`slax-wine-uefi` image**, and then the filesystem is a free choice: **ext4** for unlimited
  persistence, FAT32 if you also want the stick readable from Windows. With the `slax-wine-bios`
  image you would be forced onto FAT32 and its 16 GB container.
- **Machine that can boot BIOS/legacy** → **ext4**. Unlimited persistence, faster, and you can read
  the prefix directly from any Linux box. Either image works.
- **8 GB stick** → ext4 if the machine boots BIOS. On FAT32 the container's 16 GB minimum cannot be
  lowered, so it is always larger than the stick; you will hit the physical end of the stick rather
  than a clean "disk full".
- **32 GB or larger** → either works. On FAT32 you get a 16 GB prefix plus the rest as ordinary
  Windows-readable storage.

> **Where does XFS come from?** On the FAT32 route, Slax creates a container file and formats it XFS
> on first boot, because FAT32 cannot store symlinks or the executable bit and a Wine prefix needs
> both. You never choose or format it — it just appears inside `changes.dat`. On ext4 there is no
> container and no XFS at all.

## Install to a USB stick

Identify the stick and **check twice** — step 1 destroys everything on it.

```sh
lsblk -o NAME,SIZE,MODEL,TRAN
```

```sh
# 1. one bootable partition -- pick the fs-type that matches step 2
sudo parted /dev/sdX --script mklabel msdos mkpart primary fat32 1MiB 100% set 1 boot on   # FAT32
sudo parted /dev/sdX --script mklabel msdos mkpart primary ext4  1MiB 100% set 1 boot on   # ext4

# 2. format it -- the SAME one
sudo mkfs.vfat -F32 -n SLAXWINE /dev/sdX1     # UEFI + BIOS, 16 GB prefix floor
sudo mkfs.ext4  -L SLAXWINE /dev/sdX1         # BIOS only, unlimited prefix

# 3. copy the slax/ directory across
sudo mkdir -p /mnt/iso /mnt/usb
sudo mount -o loop,ro slax-wine-uefi-1.0.0.iso /mnt/iso   # or -bios-, whichever you built
sudo mount /dev/sdX1 /mnt/usb
sudo cp -a /mnt/iso/slax /mnt/usb/
sudo sync

# 4. make it bootable
cd /mnt/usb/slax/boot && sudo ./bootinst.sh

# 5. done
cd / && sudo umount /mnt/usb /mnt/iso
```

`bootinst.sh` installs `extlinux` on the partition, writes a master boot record to the **whole
disk**, and moves `slax/boot/EFI/Boot/` up to `/EFI/Boot/` at the root of the stick — which is why
`slax/boot/EFI/` looks empty afterwards, and how UEFI boot works on FAT32.

On Windows, run `slax\boot\bootinst.bat` instead. It asks for admin rights and refuses to run if the
target is on the same physical disk as Windows.

## Install to a hard disk

The same three steps, onto a partition instead of a stick. Two differences worth knowing.

**`bootinst.sh` takes over the disk.** It writes the MBR of the whole drive and marks the partition
active, so a disk that already boots something else will boot only Slax afterwards. It warns first.
On a machine you care about, use the chainload route instead: copy `slax/` onto any partition, do
**not** run `bootinst.sh`, and add an entry to the bootloader you already have:

```
menuentry "slax-wine" {
    search --no-floppy --file --set=root /slax/boot/vmlinuz
    linux  /slax/boot/vmlinuz vga=normal rw printk.time=0 consoleblank=0 perchdir=resume
    initrd /slax/boot/initrfs.img
}
```

`search --file` locates whichever partition holds Slax, so the entry survives repartitioning. This
route also gets you UEFI on ext4, because your existing GRUB can read ext4 even though
`syslinux.efi` cannot.

**Prefer ext4 here.** A fixed disk has no reason to be FAT32.

## First boot, and the session menu

Let the default entry run. The USB and hard-disk boot menu offers:

| entry | what it does |
|---|---|
| **Resume previous session** | the default — continues where you left off. **This is the one you want.** |
| Start a new session | a fresh, empty writable layer, keeping the old one on disk |
| Choose session during startup | lists existing sessions with their age and size |
| Run Slax from RAM | copies everything to RAM and **unmounts the stick — nothing is saved** |

The CD menu greys the session entries out, because optical media cannot be written to.

## Check that persistence is actually on

**Do this before you install anything into Wine.** Persistence failing is quiet — there is no error
dialog, nothing is marked read-only, and the desktop looks identical. You find out at the next boot.

During early boot, a working persistent start prints these three lines:

```
* Waiting for persistent changes on /dev/sda ...
* Testing persistent changes for posix compatibility
* Activating native persistent changes for session #1
```

They scroll past before the desktop appears, so the reliable check is from a terminal once you are
up:

```sh
mount | grep memory
```

If it names a real device or a loop device, you are persistent.

**If it prints nothing, you are not.** That is the normal negative result, and it is easy to
misread as "the command did not work": on a non-persistent boot Slax simply creates
`/memory/changes` as an ordinary directory inside the ramfs root and never mounts anything there, so
there is no line to find. Everything you do will be lost at shutdown. (Grep for `memory`, not
`memory/changes` — the latter misses the `/memory/data/...` line the FAT32 route produces.)

### The near-miss that costs you the session

`perch` is matched as a **substring** of the whole kernel command line, not as a whole word. So
`perch=`, `perchh=`, `perchdirr=` — any typo that still contains the letters `perch` — **switches
persistence on**, and then, having no `perchdir=` to name a device, falls back to the boot medium's
own `slax/changes`. On a CD that is read-only, so `livekitlib` gives up with one line:

```
* Persistent changes not writable or not used
```

…and carries on in RAM. That line is the only warning, and X covers it within seconds. *(Quoted from
`persistent_changes` in `livekitlib`, not from a boot we captured — the three success lines above
are from a real serial log, this one is read from the source.)*

The parameter that works is spelled exactly:

```
perchdir=/dev/sda/slax/changes
```

`livekitlib` splits that at the fourth `/`: device `/dev/sda`, subdirectory `slax/changes`.

**You must type it on every boot** when booting the ISO this way. The menu's *Restore previous
session* entry is `MENU DISABLED` on optical media, so nothing remembers it for you — which is
exactly the difference between booting an ISO with a disk attached and a proper `bootinst` stick,
where that entry is live and you type nothing at all.

## Where your Wine C: drive lives

`WINEPREFIX` defaults to `/root/.wine`, which sits in the writable layer — so persistence covers it
with no special setup. On the stick it ends up at:

| stick | path on the medium |
|---|---|
| ext4 | `slax/changes/1/root/.wine` — browsable from any Linux machine |
| FAT32 | inside `slax/changes/1/changes.dat` — only readable from a booted Slax |

To give a FAT32 prefix more than the default 16 GB, press `Esc` at the boot menu, `Tab` to edit, and
add `perchsize=48G`. **Do this before the first persistent boot** — the size is fixed when the
container is created and can only ever be raised, never lowered.

## Why `dd` does not work

A stock Slax ISO has no master boot record at all — bytes 0–511 are zero — so
`dd if=slax-wine-uefi-1.0.0.iso of=/dev/sdX` produces a stick that boots on nothing. slax-wine does not
ship the `isohybrid` fix, deliberately: even when it works, a `dd`'d image is a read-only ISO9660
filesystem, so there is nowhere for changes to be written and **persistence is impossible**. Ventoy
and Rufus carry the same limitation.

## Things that will bite you

| symptom | cause |
|---|---|
| "My changes disappeared" | booted from CD, or picked **Run Slax from RAM**, or `dd`'d the ISO, or no `perchdir=` on the command line |
| Changes disappeared *and* you did type a perch parameter | Check the spelling. `perch` is a **substring** match, so a near-miss like `perch=` enables persistence with nowhere to store it and silently runs in RAM — see [the near-miss above](#the-near-miss-that-costs-you-the-session). It is spelled `perchdir=/dev/sda/slax/changes` |
| Prefix fills up at 16 GB | FAT32 container at its default size. **Reboot once with a larger `perchsize=`** — Slax runs `xfs_growfs` for you and your prefix is kept. Only if you want to start clean: delete `changes.dat*` in the session directory, or reformat ext4 |
| Stick boots on one machine, not another | UEFI-only firmware and an ext4 stick. Reformat FAT32 |
| `bootinst.sh` cannot execute `extlinux` | the stick is mounted `noexec`; the script tries to remount and then falls back to `extlinux.exe` |

## Advanced

slax-kitchen documents the underlying machinery in far more depth. These links are absolute and
pinned to the submodule commit this release was built against: `vendor/slax-kitchen` is a git
submodule, so a relative link into it renders as a 404 on github.com even though the file is right
there in your clone.

| you want | read |
|---|---|
| every persistence option, session handling, container internals | [persistence-perch](https://github.com/Fullaxx/slax-kitchen/blob/8adfca6/docs/05-using-slax/persistence-perch.md) |
| all three USB routes and what `bootinst` does | [install-to-usb](https://github.com/Fullaxx/slax-kitchen/blob/8adfca6/docs/05-using-slax/install-to-usb.md) |
| disk installs, chainloading, booting an ISO file directly | [install-to-harddisk](https://github.com/Fullaxx/slax-kitchen/blob/8adfca6/docs/05-using-slax/install-to-harddisk.md) |
| boot parameters you can type at the menu | [boot-parameters](https://github.com/Fullaxx/slax-kitchen/blob/8adfca6/docs/20-boot-sequence/boot-parameters.md) |
| what is in this image, and Wine's first run | [using-wine](docs/using-wine.md) |
