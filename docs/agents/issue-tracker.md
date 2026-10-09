# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` — never a single combined tickets file
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading
- A resolved spec or ticket is archive: it records what was decided and built at the time, and a later decision never rewrites it. The living record is the ADR and the README, which are updated when a decision changes.

## Where task management happens

Task management commits land on `main`, never on a task branch: creating or
editing a spec, a map, or a ticket; moving a ticket's `Status:`; ticking its
acceptance boxes; appending to `## Comments`; and ADRs or glossary terms that
came out of planning.

A branch and worktree exist only for implementation, created from `main` when
that implementation starts, and they carry only the implementation: code, tests,
and the documentation that ships with the behavior. Never edit `.scratch/**`
inside a worktree.

Move status at ticket boundaries: claim before the worktree exists, and mark the
ticket finished after its implementation is integrated into `main`. If an
implementation ticket also changes a `.scratch/` file (deleting a planning
draft, for example), make that change on `main` at the boundary like any other
task-management edit.

A task-management commit landing on `main` while an implementation branch is open
makes a plain `--ff-only` integration impossible. Rebase the implementation branch
onto `main` in its worktree, then fast-forward from the main checkout; that
recovery is the default, so the two do not have to be kept apart.

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` — the Notes / Decisions-so-far / Fog body.
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
