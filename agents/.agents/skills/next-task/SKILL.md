---
name: next-task
description: Report the next available task in this repository's issue tracker, ranked, with the work already in progress excluded. Use when the user asks what to work on next, what is ready, or invokes /next-task. Read-only — it never claims or writes.
disable-model-invocation: true
---

# Next Task

Report what is takeable now in **this repository's** issue tracker, in the tracker's own
order, and name what is already in progress. Only this repository is read: no other
checkout, and no other repository's tracker.

**Read-only.** This skill never claims, labels, comments, assigns, or edits anything. The
claim belongs to `/implement`, made before implementation starts. The output is the report
and nothing else.

## 1. Resolve the tracker

Read these from the current repository, in order:

- **`docs/agents/issue-tracker.md`** — the contract: where issues live, and the commands
  that query them. **If it does not exist, stop.** Say the repository has no issue tracker
  declared and point the user at `/setup-matt-pocock-skills`. Do not fall back to
  `.scratch/`, and do not guess a tracker.
- **`docs/agents/triage-labels.md`** — the label string this tracker uses for each
  canonical triage role. This skill speaks in roles; the tracker speaks in strings. When it
  is missing, say the strings are undeclared and use the canonical role names, which the
  setup skill writes by default.
- The tracker doc's **"Wayfinding operations"** section, when it has one: it defines the
  map, the child ticket, blocking, and the frontier for this tracker.

Never hard-code a tracker, a label string, or a command that the tracker doc contradicts.
The recipes in step 6 are worked examples of what the doc can say, not a fixed list.

## 2. Collect the candidates

A **candidate** is a ticket the tracker declares available to an agent and that no one has
claimed. Two kinds, in this order:

1. **Build work** — the ticket carries the `ready-for-agent` role, under whatever label
   string `triage-labels.md` maps it to.
2. **Decisions** — when the tracker doc defines Wayfinding operations, the **frontier**:
   the open, unblocked, unclaimed child tickets of a map, first by number. A map is an
   effort directory that carries a `map.md`.

In the local tracker two vocabularies share the `Status:` line. When it holds a triage
role string, the file is a triage ticket, and only `ready-for-agent` makes it a candidate.
Otherwise — absent, or a wayfinder state such as `claimed` or `resolved` — it is read with
the wayfinding rules when its effort has a `map.md`. Read the value, not the file's name.

Not candidates, and not listed as available:

- a ticket with no state recorded and no map above it — never guess one; an absent
  `Status:` on a wayfinder child means open, which is not a guess;
- a ticket whose blockers are not resolved;
- a ticket in the `ready-for-human` role — it is not agent work;
- a ticket in the `needs-triage`, `needs-info`, or `wontfix` roles.

## 3. Find the work already in progress

Two kinds of signal, with different authority:

- **A tracker-native claim excludes the candidate.** A claim is whatever this tracker's own
  notion of "someone is on it" is: an assignee, a `claimed` state, an in-progress label.
  That state is shared, so it is authoritative.
- **A local git trace is advisory.** A worktree, a branch, or uncommitted changes that
  name the ticket — its number, its slug — mean work has begun. Report it as a warning and
  keep the candidate listed; never drop it silently. Say that the match is a heuristic.

Match traces against the ticket's number and slug, in `git worktree list`, `git branch
--list`, and `git status --porcelain`:

```sh
git worktree list && git branch --list && git status --porcelain
```

**Not checked, and said so in the report:** live agent sessions. Another Pi session, a
Herdr pane, or a running subagent is out of scope, and the report states that explicitly —
implementation here already requires a branch and a worktree, so a session actually
working leaves a git trace, and a session that only reads or plans does not conflict.

**`--include-busy`** keeps the candidates a claim or a git trace would exclude in the
list, each marked with the signal that would have excluded it.

## 4. Order, and pick the recommendation

Use the tracker's own order when the tracker doc defines one — the local tracker's frontier
is "first by number wins". Otherwise order by number ascending, oldest first. An explicit
priority the tracker exposes comes first only when the tracker exposes one.

The recommendation is the first candidate in that order. Do not re-rank by opinion about
value or about what unblocks the most.

## 5. Report

Name every ticket by its title, with its reference beside it. The reference is the
tracker's own: a file path for the local markdown tracker, `#42` for GitHub.

```markdown
## Recommended

**<title>** — `<ref>` — <why it is first: its state, and its place in the tracker's order>
`/implement <ref>`

## Also available

2. **<title>** — `<ref>` — <state>
3. **<title>** — `<ref>` — <state>

## Set aside

- **<title>** — `<ref>` — claimed by <who>
- **<title>** — `<ref>` — branch `<name>` already exists (git trace, heuristic)
- **<title>** — `<ref>` — blocked by **<blocking title>**
- **<title>** — `<ref>` — no state recorded

Live agent sessions were not checked: only the tracker and this checkout's git state were read.
```

List every candidate, in order, with no cap. With no candidate at all, say so, name the
set-aside entries, and stop — do not invent work.

## 6. Recipes

### Local markdown tracker

Tickets are one file per ticket under `.scratch/<feature>/issues/`. Read the head of each
file for its `Status:`, `Type:`, and `Blocked by:` lines. The label is bolded in most files
here (`**Status:**`) and plain in a few, so match either form:

```sh
ls .scratch/*/issues/*.md 2>/dev/null
grep -nE '^\*{0,2}(Status|Type|Blocked by):\*{0,2}' .scratch/*/issues/*.md
```

- **Build work**: the `Status:` value is `ready-for-agent`.
- **Wayfinder child**: its effort directory carries a `map.md`. It is on the frontier when
  its `Status:` value is neither `claimed` nor `resolved`.
- **Blocked**: a `Blocked by:` value opens with the number of another ticket in the same
  `issues/` directory (the rest of the line is a title and sometimes an annotation). The
  candidate counts only when every number named there resolves to a file whose `Status:`
  value is `resolved`.
- **Claim**: the `Status:` value is `claimed`.
- **Order**: number ascending within an effort, effort directory name ascending across
  efforts — the tracker doc defines no cross-effort order.
- **Reference**: the file path, e.g. `.scratch/safe-pi/issues/09-release-pane-on-exit.md`.

### GitHub tracker

```sh
gh issue list --state open --limit 200 \
  --json number,title,labels,assignees,createdAt \
  --jq 'sort_by(.number) | .[] | {number, title, labels: [.labels[].name], assignees: [.assignees[].login], createdAt}'
```

- **Build work**: the labels carry the string `triage-labels.md` maps to `ready-for-agent`.
- **Claim**: a non-empty `assignees`.
- **Blocked**: only per whatever the tracker doc's convention is. GitHub has no native
  blocking, so if the doc says nothing, there is no blocking to evaluate.
- **Reference**: `#<number>`.

### Any other tracker

Follow the commands in `docs/agents/issue-tracker.md` and map the same three notions onto
it: the role that means ready for an agent, the state that means claimed, and how blocking
and the frontier are expressed. If the doc leaves one of those undefined, say so in the
report instead of guessing.
