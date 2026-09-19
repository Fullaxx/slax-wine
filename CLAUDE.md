# Notes for Claude

Pointers, not rules, in the same form as slax-kitchen's own `CLAUDE.md`. Everything here lives
somewhere else in the repo; this file only says **when to go and read it**. A rule copied into two
places is how the two drift.

## Before moving the slax-kitchen pin

Read [`docs/UPSTREAM.md`](docs/UPSTREAM.md) § *The lifecycle*, which says when a bump may land at
all, then § *Local workarounds* and the stated differences in every file headed *Adapted from
slax-kitchen*. Whatever upstream has since fixed is retired in the same bump, or kept with the
reason written on its row.

Gate 96 §10 refuses a bump while an *active* row's issue is closed at the new pin. It only knows
about workarounds that are marked and listed, which is what the next section is for; the headers
are read by hand, because a difference kept for a reason of our own has no issue to close.

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
