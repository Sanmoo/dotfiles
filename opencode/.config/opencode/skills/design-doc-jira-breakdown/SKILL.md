---
name: design-doc-jira-breakdown
description: Break down technical design docs into Jira parent tasks and subtasks that are independently mergeable to main under trunk based development. Use when the user asks to "quebrar um design doc", "fazer breakdown para Jira", "gerar subtasks mergeaveis na main", "break down this TDD", "decompose this design doc into tasks", or wants technical task decomposition from a TDD or RFC. Do NOT use for writing the design doc itself, generic backlog grooming, business-only stories, or sprint estimation.
license: CC-BY-4.0
metadata:
  author: Samuel
  version: 1.0.0
---

# Design Doc Jira Breakdown

Use this skill to transform a technical design document into a Jira breakdown that is compatible with trunk based development. The output must produce technical parent tasks and subtasks where each subtask is independently mergeable to `main`, scoped to at most one day of work, and written in a standard format ready for Jira.

## Instructions

### Step 1: Confirm the source and objective

Start by identifying the design source and the expected output.

- Accept as input a design doc file, pasted markdown, Jira discovery task, RFC, or a direct link/reference to an existing design document.
- If the user asks only for the breakdown, do not rewrite the design doc.
- If the design is still incomplete or obviously undecided, prefer a discovery-oriented breakdown instead of inventing implementation details.
- Default to producing a draft in markdown first. Only create issues in Jira if the user explicitly asks for it.

Expected output: a clear understanding of whether the result should be a discovery task, an implementation task tree, or both.

### Step 2: Detect Jira context

Detect the Jira project, business-story context, and linking context before proposing issue creation.

1. Check workspace Jira context first if available.
2. Reuse a project key already established in the current conversation if one exists.
3. Inspect recent issues from the target Jira project before proposing or creating issues.
4. Confirm the exact issue type names accepted by that project, especially the parent and child issue types.
5. Observe the local conventions of the board, including title style, wording density, and description structure.
6. Identify whether there is a related business story, epic, or upstream Jira item that the technical work should reference.
7. If the Jira project or the related business story is still ambiguous, ask the user explicitly.
8. Never assume a fixed project key as global default.

When proposing or creating issues, use `Tarefa` as the default parent type and `Subtarefa` as the default child type only after confirming that these exact type names are accepted by the target project. If the project uses different names, reuse the names observed in that board.

When a related business story exists, the default policy is:

- each technical `Tarefa` must receive a Jira link of type `Relates` to the related business story
- `Subtarefas` do not receive `Relates` to the business story by default unless the user explicitly asks for it

Expected output: a confirmed Jira project context, confirmed issue type names and board conventions, a confirmed or explicitly missing related business story, or a clear follow-up question to the user.

### Step 3: Read the design as implementation input, not as prose

Extract the minimum set of decisions needed to drive decomposition.

- Identify all input sources that influence the breakdown, such as design docs, Jira issues, pull requests, runbooks, dashboards, or operational tickets.
- Classify each source as one of: `normative`, `contextual`, or `operational`.
- If multiple sources disagree in scope or level of detail, surface the conflict explicitly instead of silently merging them.
- Confirm with the user which source should drive the implementation scope when the answer is not obvious.
- Identify the technical problem being solved.
- Identify what is already decided versus what remains open.
- Identify impacted modules, bounded responsibilities, integrations, contracts, operational concerns, and migration constraints.
- Identify explicit dependencies, sequencing constraints, and rollout constraints.
- Identify whether the design already implies natural slices such as foundation, public API, consumer adaptation, infrastructure activation, observability, or replay/operations.

If the design doc references code architecture or repository conventions, read those references before decomposing. Only read additional references when they materially affect the breakdown.

If the user is adapting work already implemented by another team, do not expand the breakdown beyond the validated scope of the chosen sources unless the user explicitly asks for a broader proposal.

Expected output: a compact internal map of sources, responsibilities, dependencies, and unresolved decisions, with any scope conflict made explicit.

### Step 4: Choose the right breakdown mode

Select the breakdown mode that best matches the design maturity.

#### Mode A: Discovery technical task

Use this when the design is still selecting an approach or when critical architectural decisions remain open.

- Produce a parent `Tarefa` focused on technical discovery.
- The acceptance criteria must require a concrete decision, not just an inventory of options.
- Subtasks are optional. Use them only if the discovery itself has mergeable technical slices such as instrumentation, mapping of current flow, or preparation of a design artifact.

#### Mode B: Implementation task tree

Use this when the design already defines a recommended approach with enough clarity to implement.

- Produce one or more parent `Tarefa` items grouped by coherent technical responsibility.
- Produce `Subtarefa` items that are independently mergeable into `main` and no larger than one working day.
- Prefer fewer, cleaner parents over artificial hierarchy.

#### Mode C: Mixed output

Use this when the design resolves part of the implementation but leaves a material area undecided.

- Separate discovery work from implementation work.
- Do not hide unresolved architecture under implementation subtasks.

Expected output: an explicit decomposition strategy with rationale.

### Step 5: Apply trunk based development slicing rules

This is the most important step. Every subtask must obey these rules.

#### Hard rules

- Each `Subtarefa` must be mergeable to `main` on its own.
- Each `Subtarefa` must be scoped to at most one day of work.
- Each `Subtarefa` must have one dominant technical responsibility.
- If a change requires tests, mocks, snapshots, OpenAPI, migration steps, feature flags, or compatibility adjustments to keep `main` healthy, include them in the same subtask when possible.
- If a subtask would only be safe after a future big-bang merge, split it further or move prerequisite work earlier.

#### Preferred slicing heuristics

- Slice by module or boundary, not by generic phase labels.
- Slice by contract ownership when API or public module boundaries are involved.
- Slice by producer versus consumer when contracts evolve incrementally.
- Slice by enabling foundation before consumer adaptation.
- Slice by operational capability when observability, replay, rollout, or support tooling are first-class concerns.

#### Anti-patterns

- Do not create a final generic subtask such as "ajustar testes" or "hardening final" if those updates belong to earlier subtasks.
- Do not create a single broad backend subtask that changes multiple modules when a clean boundary split exists.
- Do not create subtasks that are merely chronological placeholders such as "parte 1", "parte 2", or "ajustes finais".
- Do not create subtasks that depend on hidden manual coordination to become releasable.

Before finalizing the breakdown, validate each subtask with this question: "If this PR were merged today, would `main` remain healthy and the delivery still make sense?" If the answer is no, split or reshape it.

For detailed heuristics and failure cases, read `references/breakdown-rules.md` before finalizing the output.

Expected output: a set of candidate tasks that respect TBD constraints.

### Step 6: Write the Jira-ready parent task

Write each parent `Tarefa` in Portuguese using exactly this section structure and no `Estimate` section.

Use Portuguese with normal spelling and accents. Do not simplify Portuguese text to ASCII.

When drafting for Jira, prefer a simple structure that renders reliably in Jira issue descriptions: section headings plus bullet lists. Do not depend on visual checklist rendering.

```markdown
## Contexto
[Resumo do problema, do design doc e do recorte tecnico desta task.]

## Objetivo
[Resultado tecnico coeso que esta task organiza.]

## Requisitos Tecnicos
- Item 1
- Item 2
- Item 3

## Criterios de Aceitacao
- Criterio 1
- Criterio 2
- Criterio 3

## Notas Tecnicas
- Design doc relacionado: ...
- Dependencias relevantes: ...
- Fora de escopo: ...
```

Parent task guidance:

- The parent should represent a coherent technical stream, not the entire epic unless the scope is genuinely small.
- The parent must make the intended subtask split obvious.
- Reference the design doc and affected modules explicitly when useful.
- Keep the text technical and implementation-oriented.

For wording guidance and ready templates, read `references/templates.md` when drafting the final text.

Expected output: one or more Jira-ready parent tasks in the standard format.

### Step 7: Write Jira-ready subtasks

Write each `Subtarefa` in Portuguese using exactly this section structure and no `Estimate` section.

Use Portuguese with normal spelling and accents. Do not simplify Portuguese text to ASCII.

Keep the description Jira-friendly: section headings plus standard bullet lists. Do not depend on visual checklist rendering.

```markdown
## Contexto
[Recorte tecnico especifico derivado da task pai.]

## Objetivo
[Entrega unica, pequena e mergeavel.]

## Requisitos Tecnicos
- Mudanca principal
- Ajuste de contrato, teste, mock ou documentacao necessario para manter a main integra
- Restricao ou cuidado tecnico relevante, quando aplicavel

## Criterios de Aceitacao
- O comportamento ou contrato esperado fica implementado
- Os artefatos impactados ficam consistentes no mesmo PR
- A entrega deixa o repositorio e o fluxo afetado em estado consistente

## Notas Tecnicas
- Dependencia de: ...
- Referencia do design doc: ...
- Fora de escopo: ...
```

Subtask guidance:

- Start the title with the dominant technical boundary when useful, such as `SmartConditions:`, `Entrypoint:`, `Documents:`, or `Discovery:`.
- Prefer naming that reveals the mergeable unit of value.
- Mention dependent issue keys only when the dependency is real and useful.
- If OpenAPI, snapshots, mocks, or tests are required by the change, keep them in the same subtask instead of creating a generic cleanup subtask.
- Do not use acceptance criteria that merely restate structural rules of the process, such as "gera um PR mergeavel" or "segue trunk based development". Those are quality constraints of the breakdown, not acceptance criteria for the Jira text.

Expected output: a full child breakdown where each subtask can be executed and merged independently.

### Step 8: Plan Jira links explicitly

Do not stop at parent-child structure. Every non-trivial breakdown must include an explicit Jira linking plan.

#### Business-story links

- If a related business story exists, plan a `Relates` link from each technical `Tarefa` to that story.
- Do not add the same `Relates` link to every `Subtarefa` by default.
- If there are multiple business stories, link each technical `Tarefa` only to the story it actually supports.

#### Dependency links

- Model technical sequencing using Jira link type `Blocks`.
- Use a minimum dependency graph: create only the links strictly necessary to represent real precedence.
- Avoid redundant transitive links. If `A blocks B` and `B blocks C`, do not also add `A blocks C` unless it expresses an additional real operational constraint.
- Prefer the smallest level that represents the real dependency:
  - use `Blocks` between `Tarefa` items when an entire technical stream depends on another
  - use `Blocks` between `Subtarefas` when only specific slices depend on each other
  - avoid duplicating the same dependency at both task and subtask level unless they represent different constraints

Use the direction consistently: if `A` must finish before `B` can proceed safely, then `A blocks B`.

For detailed rules and examples, read `references/breakdown-rules.md` before finalizing the link plan.

Expected output: an explicit plan of `Relates` and `Blocks` links that matches the proposed decomposition.

### Step 9: Run the breakdown quality gate

Before presenting the result, verify all of the following.

1. Every subtask is one-day sized or smaller.
2. Every subtask is independently mergeable to `main`.
3. The split follows technical boundaries from the design, not generic execution phases.
4. Open questions that block implementation were not hidden under implementation tasks.
5. Cross-cutting updates were attached to the owning subtask whenever possible.
6. No generic final hardening or testing subtask remains unless there is a strong reason.
7. The parent/child structure is minimal and clear.
8. Every real dependency is represented either in the hierarchy or in the explicit `Blocks` plan.
9. The dependency graph uses the minimum number of `Blocks` links necessary to preserve execution constraints.
10. Every technical `Tarefa` that supports a known business story has a planned `Relates` link to that story.

If any check fails, revise the breakdown before showing it to the user.

Expected output: a validated breakdown that the user can review or send to Jira.

### Step 10: Present the result and optionally create Jira issues

When returning the breakdown:

- Present parent tasks first, then subtasks grouped under each parent.
- Briefly explain the slicing rationale in 2 to 4 bullets when the breakdown is non-trivial.
- Call out any assumptions or unresolved decisions.
- Present the Jira linking plan explicitly:
  - `Relates` links from technical tasks to the related business story
  - `Blocks` links that represent the minimum dependency graph
- If the user asked for Jira creation, create only after the draft is complete and the project context is known.

For Jira creation:

1. Create the parent `Tarefa` first.
2. Create each `Subtarefa` with the parent relationship.
3. Create `Relates` links from each technical `Tarefa` to the related business story when applicable.
4. Create `Blocks` links using the planned minimum dependency graph.
5. Preserve the exact text structure used in the draft, adapting only what is necessary to match the rendering and issue-type conventions of the target Jira project.
6. Read back the created issues before declaring success.
7. Verify at minimum: issue type, parent-child relationship, Jira links, and visible description structure.
8. If the rendered description lost headings, bullets, or other essential structure, fix the issue before concluding.
9. If the user asked only for a draft, stop before creation.

Expected output: a markdown draft, or a created Jira hierarchy when explicitly requested.

## Troubleshooting

### Problem: The design doc is too vague to support implementation subtasks

Cause: Core architectural choices are still unresolved.

Solution:

1. Switch to discovery mode.
2. State which decisions remain open.
3. Produce a discovery-oriented parent task instead of speculative implementation slices.

### Problem: A subtask only becomes safe after later work lands

Cause: The slice is too large or cut on the wrong boundary.

Solution:

1. Split enabling work earlier.
2. Move compatibility, contract, or feature-flag work into the owning subtask.
3. Re-test the slice against the rule "mergeable to main today".

### Problem: The breakdown ends with a generic testing subtask

Cause: Cross-cutting validation was detached from the owning changes.

Solution:

1. Push tests, mocks, snapshots, and contract updates back into the subtasks that require them.
2. Keep a dedicated testing subtask only when it is itself a real mergeable technical slice, such as end-to-end validation behind already-landed infrastructure.

### Problem: Jira project is not clear

Cause: The workspace or conversation does not establish a single project key.

Solution:

1. Ask the user explicitly which Jira project to use.
2. Produce the markdown draft first.
3. Delay Jira creation until the project is confirmed.

### Problem: The reference sources imply different scopes

Cause: A PR, Jira issue, design doc, or operational ticket is being treated as if they all describe the same implementation scope.

Solution:

1. Classify each source as normative, contextual, or operational.
2. Call out the mismatch explicitly.
3. Ask the user which source should drive the breakdown before decomposing.

### Problem: The Jira issue renders with poor formatting

Cause: The draft used generic markdown assumptions instead of a structure that the current Jira flow renders reliably.

Solution:

1. Use headings and standard bullet lists instead of relying on visual checklists.
2. Re-read the created issue after creation.
3. If the structure renders poorly, edit the issue immediately before reporting success.

### Problem: The related business story is unclear

Cause: The design doc or conversation does not identify which business story the technical work supports.

Solution:

1. Ask the user which story or business ticket should be linked.
2. If the user only wants a draft, keep the breakdown and mark the `Relates` link as pending confirmation.
3. Do not guess the business story from loose similarity alone.

### Problem: The dependency graph is too dense or redundant

Cause: The breakdown mixes real sequencing constraints with redundant transitive links.

Solution:

1. Remove `Blocks` links that are already implied transitively.
2. Keep only the smallest set of links required to preserve ordering.
3. Prefer task-level links for whole-stream dependency and subtask-level links for slice-specific dependency.

## Examples

### Example 1: Breakdown from an implementation design doc

User says: "Quero quebrar o design doc `docs/design/004-finance-condition-metadata-by-product.md` em tasks tecnicas para Jira, com subtasks mergeaveis na main."

Actions:

1. Read the design doc and identify the owning module, public API, and consumers.
2. Detect the Jira project from workspace context or ask if ambiguous.
3. Identify the related business story and plan `Relates` links from each technical `Tarefa` to that story.
4. Produce a parent task for the backend foundation.
5. Produce subtasks such as catalog/config foundation, public API exposure, endpoint adaptation, and consumer filtering.
6. Keep OpenAPI and test updates in the owning subtasks.
7. Plan only the minimum `Blocks` links needed between the resulting technical slices.

Result: a Jira-ready breakdown where each subtask maps to a single technical boundary, each technical task is linked to the related business story, and dependencies are represented by a minimal `Blocks` graph.

### Example 2: Discovery-first design

User says: "Faca o breakdown no Jira para este design de DLQ, mas ainda estamos decidindo se a DLQ sera estrutura propria ou derivacao da event_publication."

Actions:

1. Recognize that implementation decisions remain open.
2. Produce a discovery-oriented parent task instead of speculative implementation subtasks.
3. Require explicit outputs such as recommended MVP, replay strategy, and operational requirements.
4. Optionally add narrow discovery subtasks only if they are real mergeable technical slices.

Result: a discovery task that resolves architecture first, without inventing implementation tickets prematurely.

### Example 3: Optional Jira creation after draft

User says: "Gere o breakdown e depois crie as tasks no Jira."

Actions:

1. Produce the markdown draft first.
2. Confirm or detect the Jira project context.
3. Create the parent `Tarefa`.
4. Create each `Subtarefa` linked to the parent.
5. Create `Relates` links from each technical `Tarefa` to the related business story.
6. Create the planned minimum `Blocks` links.
7. Return the created issue keys and a compact summary of the structure and links.

Result: a reviewed breakdown becomes a Jira hierarchy with parent-child relationships, business-story links, and the minimum dependency graph represented in Jira.
