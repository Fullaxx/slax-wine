# Notes for Claude

Pointers, not rules, in the same form as slax-kitchen's own `CLAUDE.md`. Everything here lives
somewhere else in the repo; this file only says **when to go and read it**. A rule copied into two
places is how the two drift. The exceptions are about the session rather than the tree: what the
user's words mean, and what a session may do on its own.

## Before committing or pushing anything

Don't, until the user has inspected the work and asked. Stop where the commit would go, with the
work uncommitted, and hand it over: what changed, what you verified and how, and the commit message
you would use. Approving a plan is not approving its commits, asking for one commit is not asking
for the next, and a request to commit is not a request to push.

The same rule as slax-kitchen's, from the same day: from 2026-09-19 the user inspects every change
before it is committed.

## When the user says "update the pin"

That means four steps, not one, and only the last moves anything:

1. review every new slax-kitchen commit
2. work out how each one affects this repo
3. retire any local workaround that an upstream fix has made redundant
4. then update the pin, stopping where the commit would go

Each is spelled out in [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *Moving the pin*. Read it before
starting, every time, including when the request is worded differently ("bump", "move the pin", "take
upstream").

## Before working around an upstream bug

Read [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *The lifecycle*: file the issue, mark the code
`WORKAROUND <issue URL>`, and add the row, all in the commit that adds the workaround. A workaround
nobody marked is invisible at the next bump — the one for slax-kitchen #23 was, until its header
was read.

## Where boot tests run

On `bacon`, since the `7f9c4f8` bump: this container has no `/dev/kvm`, that machine does, and
`vendor/slax-kitchen/boot-host.ini` sends every `kitchen test` there. The file is gitignored,
`chmod 600`, and lives inside the submodule because that is the only place the engine reads it
from. `kitchen boot-host check` says whether it is usable, and `KITCHEN_BOOT_HOST=local` boots
here instead — slowly, under TCG.

A boot host that cannot be reached **fails the command**; it never quietly boots here. So when
`kitchen test` says "boot host unavailable", read that before anything else.

The TCG era left measurements behind, and [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *When KVM
lands* is the checklist for retiring them — what to re-run, which timings were emulation
artefacts, and which pages retire themselves once it passes.

## Before reviewing anything

Read [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *Our own bar, which is higher* — read the code path end
to end, demonstrate, attack, reproduce — which applies to reviewing a change here as much as to
anything filed upstream. slax-kitchen's `CLAUDE.md` makes the same point about its own tree.

The one part with no home in the repo, because it is about this session and not about the tree:
**when the user says "self-review", that means you.** Read the diffs and report directly. Do not
invoke the code-review skill — being asked to review is not being asked to dispatch one.
