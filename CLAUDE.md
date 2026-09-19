# Notes for Claude

Pointers, not rules, in the same form as slax-kitchen's own `CLAUDE.md`. Everything here lives
somewhere else in the repo; this file only says **when to go and read it**. A rule copied into two
places is how the two drift.

## When the user says "update the pin"

That means four steps, not one, and only the last moves anything:

1. review every new slax-kitchen commit
2. work out how each one affects this repo
3. retire any local workaround that an upstream fix has made redundant
4. then update the pin

Each is spelled out in [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *Moving the pin*. Read it before
starting, every time, including when the request is worded differently ("bump", "move the pin", "take
upstream").

## Before working around an upstream bug

Read [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *The lifecycle*: file the issue, mark the code
`WORKAROUND <issue URL>`, and add the row, all in the commit that adds the workaround. A workaround
nobody marked is invisible at the next bump — the one for slax-kitchen #23 was, until its header
was read.

## Before reviewing anything

Read [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *Our own bar, which is higher* — read the code path end
to end, demonstrate, attack, reproduce — which applies to reviewing a change here as much as to
anything filed upstream. slax-kitchen's `CLAUDE.md` makes the same point about its own tree.

The one part with no home in the repo, because it is about this session and not about the tree:
**when the user says "self-review", that means you.** Read the diffs and report directly. Do not
invoke the code-review skill — being asked to review is not being asked to dispatch one.
