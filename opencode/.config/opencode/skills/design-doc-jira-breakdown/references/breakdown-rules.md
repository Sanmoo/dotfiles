# Breakdown Rules

Read this file before finalizing any breakdown that will be used as Jira input.

## Goal

Convert a design doc into technical work slices that are safe for trunk based development.

The breakdown is good only if each child slice is:

- understandable on its own
- small enough for one day of work or less
- safe to merge to `main`
- aligned to a real technical boundary

## How to find the right slices

Prefer these axes, roughly in this order:

1. Module boundary
2. Public API or contract boundary
3. Producer versus consumer split
4. Enabling foundation versus adoption
5. Operational capability such as replay, observability, or rollout support

Examples of healthy slices:

- `SmartConditions`: create internal configurable catalog
- `SmartConditions`: expose public use case in `api`
- `Entrypoint`: adapt `GET /finance-conditions`
- `Entrypoint`: filter `GET /customers` using new metadata
- `Documents`: validate end-to-end versioning flow with infrastructure enabled

Examples of weak slices:

- backend part 1
- backend part 2
- final tests
- technical adjustments
- finish integration

## One-day rule

If a subtask would likely require more than one focused working day, split it.

Signals that a slice is too large:

- it changes more than one module boundary without a strong reason
- it introduces a new internal model and also adapts multiple consumers
- it includes both the contract definition and all downstream migrations
- it requires a large manual coordination window before merge

When in doubt, split earlier and keep the dependency chain explicit.

## Mergeability rule

Ask this question for each proposed subtask:

"If this were merged to `main` today, would the branch remain healthy and the repository stay in a consistent state?"

If the answer is no, the slice is wrong.

Common fixes:

- add feature-flag or compatibility work to the same subtask
- split foundation from consumer adaptation
- split public contract exposure from endpoint adoption
- move tests or OpenAPI updates into the slice that owns the change

## Where tests and contracts belong

Do not automatically create a final testing subtask.

Instead:

- unit tests belong in the subtask that changes the logic
- mocks, fixtures, snapshots, and contract adjustments belong in the subtask that changes the contract or behavior
- OpenAPI changes belong in the same subtask as the endpoint behavior change
- integration or end-to-end validation may be a dedicated subtask only when it is a real mergeable capability after the enabling work already exists

## Discovery versus implementation

Use discovery when the design still leaves open questions that materially affect the implementation split.

Typical discovery signals:

- more than one viable architecture is still being considered
- storage model, ownership, or operational flow is unresolved
- replay, rollout, or compatibility strategy is not yet defined
- the design doc itself asks for a recommendation rather than implementation

Do not fake certainty. If the architecture is not closed, generate discovery work first.

## Parent task strategy

Use a parent `Tarefa` when multiple mergeable slices belong to one coherent technical stream.

A parent task is useful when:

- several subtasks implement a single design decision across boundaries
- sequencing matters but each child can still merge independently
- the parent helps explain the why of the decomposition

Avoid over-grouping. If the work naturally forms two unrelated technical streams, prefer two parent tasks.

## Jira link policy

The hierarchy alone is not enough. Model the non-hierarchical relationships explicitly.

### `Relates` to business stories

- When a related business story exists, each technical `Tarefa` should receive a `Relates` link to that story.
- Do not add `Relates` from every `Subtarefa` to the story by default. The parent technical task carries that traceability.
- If different technical tasks support different stories, link each task only to the story it actually serves.

### `Blocks` for technical sequencing

- Use Jira link type `Blocks` to represent real implementation dependency.
- Prefer the minimum dependency graph.
- Avoid redundant transitive edges.

Good examples:

- `Tarefa A blocks Tarefa B` when the entire downstream stream depends on the upstream stream
- `Subtarefa A1 blocks Subtarefa B2` when only that specific slice is a prerequisite

Weak examples:

- `A blocks B`, `B blocks C`, and `A blocks C` when `A -> C` is already implied
- using `Relates` when the relationship is actually sequencing or blocking
- adding the same blocking intent both between parent tasks and between all child subtasks without a distinct reason

### Choosing the right level

- Use task-level `Blocks` when the whole technical stream is gated by another stream.
- Use subtask-level `Blocks` when only one specific slice is gated.
- Do not duplicate the same dependency at both levels unless the two links communicate different real constraints.

### Link direction

Use one rule consistently:

- if `A` must complete before `B` can proceed safely, then `A blocks B`

## Naming guidance

Good titles reveal the dominant technical boundary and the value of the slice.

Prefer:

- `Discovery: DLQ para eventos internos do Spring Modulith`
- `SmartConditions: criar catalogo configuravel de metadata por produto`
- `Entrypoint: atualizar GET /finance-conditions para listar todas as finance conditions do produto`

Avoid:

- `Ajustes backend`
- `Implementacao inicial`
- `Refactor final`

## Final checklist

Before presenting the breakdown, verify all items below.

- every subtask has one dominant responsibility
- every subtask is one day or smaller
- every subtask is mergeable to `main`
- no generic cleanup or final testing ticket remains without strong reason
- unresolved design decisions were not hidden under implementation work
- task descriptions are in Portuguese using the standard section structure
- every technical `Tarefa` linked to a known business story has a planned `Relates`
- every real sequencing dependency is represented by the minimum necessary `Blocks` links
- the chosen `Blocks` links are at the right level: task or subtask
