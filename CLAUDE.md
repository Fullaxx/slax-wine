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

## Before cutting a release

Read [`docs/build.md`](docs/build.md) § *Cutting a release*. A tag push starts
`.github/workflows/release.yml`, which builds into a draft release. Pushing a tag, dispatching a
rehearsal and publishing a draft are each the user's, and each is its own request, like a commit.

## Before working around an upstream bug

Read [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *The lifecycle*: file the issue, mark the code
`WORKAROUND <issue URL>`, and add the row, all in the commit that adds the workaround. A workaround
nobody marked is invisible at the next bump — the one for slax-kitchen #23 was, until its header
was read.

## Where boot tests run

On the machine `boot-host.ini` at this repository's root names: this container has no `/dev/kvm`,
that machine does, and the file sends every `kitchen test` there. It is gitignored and `chmod 600`.
The vendored engine reads it there, before its own checkout, since the `4a10303` bump; until then
it had to be copied into `vendor/slax-kitchen/`. Which machine that is, the file says and this
repository does not. `kitchen boot-host check` says whether it is usable, and
`KITCHEN_BOOT_HOST=local` boots here instead — slowly, under TCG.

A boot host that cannot be reached **fails the command**; it never quietly boots here. So when
`kitchen test` says "boot host unavailable", read that before anything else.

The boot routes have been re-run there already. [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *When
KVM lands* is the dated record of what that changed; the timings themselves, KVM and TCG, are rows
in [`docs/measurements.md`](docs/measurements.md).

## Before quoting or re-measuring a number

Read [`docs/measurements.md`](docs/measurements.md) § *The rules*. Every measured number lives on
that page and nowhere else: another page links to its row rather than repeating it, and a
placeholder, `TBD-MEASURED`, is written only there. After a local build, `ci/measure-check.sh out/`
says which rows moved.

## Before reviewing anything

Read [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *Our own bar, which is higher* — read the code path end
to end, demonstrate, attack, reproduce — which applies to reviewing a change here as much as to
anything filed upstream. slax-kitchen's `CLAUDE.md` makes the same point about its own tree.

The one part with no home in the repo, because it is about this session and not about the tree:
**when the user says "self-review", that means you.** Read the diffs and report directly. Do not
invoke the code-review skill — being asked to review is not being asked to dispatch one.
