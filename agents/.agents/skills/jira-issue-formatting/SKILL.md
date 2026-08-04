---
name: jira-issue-formatting
description: Use when creating or updating Jira issue descriptions or links through MCP/API, especially with sections, bullets, inline paths, acceptance criteria, YAML/code blocks, subtasks, or issue dependencies.
---

# Jira Issue Formatting

## Overview

Jira descriptions sent through MCP/API often accept a Markdown string but return Jira wiki markup. Format descriptions deliberately and verify the returned description after create/update.

This skill also covers safe Jira MCP/API mutations: discover the exact tool contract before calling it, preserve approved content during updates, create hierarchy and dependency links with verified semantics, and reconcile the final Jira state instead of trusting a successful mutation response.

Core principle: send readable Markdown, expect Jira to convert it, and fix rendering issues without deleting useful content.

## When to Use

Use this before creating or updating Jira issues when the description includes:

- structured sections;
- acceptance criteria;
- bullet lists;
- inline file paths, field names, or config keys;
- YAML, JSON, SQL, shell, or other code blocks;
- parent tasks with subtasks;
- an Epic association or direct dependency links;
- bulk creation or bulk updates;
- approved source material whose wording and structure must be preserved.

Do not use this for plain one-line descriptions with no Jira mutation.

## Expected Jira Conversion

When using tools such as `jira_jira_create_issue` or `jira_jira_update_issue` with a string `description`, Jira may return wiki markup:

| Send | Jira may return | Meaning |
| --- | --- | --- |
| `## Escopo` | `h2. Escopo` | OK; heading rendered |
| `- item` | `* item` | OK; bullet rendered |
| `` `path/file.yaml` `` | `{{path/file.yaml}}` | OK; inline code rendered |
| fenced code block | `{code:lang}...{code}` | OK if opening marker and content are on separate lines |

This conversion is expected. Do not “fix” it back unless rendering is broken.

## Safe Jira MCP/API Operations

### Discover before mutating

Before the first create, update, delete, Epic association, or issue-link call:

1. Confirm the Jira server is connected and the target project/issue exists.
2. Discover the exact tool name and schema with the MCP gateway. Do not infer parameters from another Jira connector or from REST terminology.
3. Confirm the project issue type, required fields, supported Epic field/parent mechanism, and configured link types.
4. Record the discovered tool path, server, required fields, optional fields, and relationship semantics in the run plan. Treat stale or incomplete metadata as unresolved, not as permission to guess.
5. Run a minimal non-mutating validation call when the tool supports `validate_only`.
6. A disposable create test is allowed only when the user authorized mutations and no non-mutating validation can resolve the ambiguity. Use a clearly disposable payload, verify it, and delete only that artifact. Never use a production issue as a probe.

Treat strict schema errors, missing relationship semantics, or an unverified target Epic as stop conditions. Do not continue with guessed fields, guessed custom-field IDs, or a different nesting shape.

### Create safely

Use this order for a planned set of issues:

1. Build an immutable plan and durable local key ledger containing one explicit source identifier, summary, description, issue type, Epic association, and intended direct dependencies per issue.
2. Check for existing matching issues before creating anything. Do not assume issue keys are sequential or that a failed/timeout call created nothing.
3. Prefer an API/tool path that can assign the verified Epic relationship at creation time. If that is not supported, create the issue, capture the returned key, verify the issue, then assign the Epic.
4. Record every returned Jira key in the ledger immediately. Never map results by guessed numbering or by unverified array position.
5. Use batch creation only when its atomicity, result mapping, and relationship-field behavior are verified. Otherwise create with checkpoints per issue. A partial batch is not automatically rolled back.
6. Stop dependent creation when a prerequisite mutation fails; preserve successful independent results in the ledger and report them separately.
7. Retry only confirmed transient failures: honor `Retry-After` when present, use a bounded retry count with backoff/jitter, and reconcile the ledger against Jira before retrying an ambiguous timeout. Never retry validation, permission, or relationship errors.

### Model dependencies as links

Keep dependencies in Jira issue links when that is the requested source of truth; do not duplicate them in the description unless explicitly requested.

For a direct relation where `A blocks B`, use the configured `Blocks` link with:

```json
{
  "link_type": "Blocks",
  "inward_issue_key": "A",
  "outward_issue_key": "B"
}
```

The predecessor/blocker is `inward_issue_key`; the dependent issue is `outward_issue_key`. Create only direct dependencies, after both issue keys are known. Do not assume `blocks`, `is blocked by`, `depends on`, `parent`, and Epic association are interchangeable. Before creating a link, verify both issues exist in the intended project and issue type; after creating it, verify the displayed direction and that no duplicate link was added.

### Preserve descriptions during updates

For an existing issue update:

1. Fetch the current issue and confirm the exact key, summary, and description before editing.
2. Derive the new description from the approved source or current description; do not summarize or reconstruct from memory.
3. Apply only the requested transformation (for example, remove one title prefix or one bounded section).
4. Preserve all other headings, paragraphs, lists, inline code, links, and code blocks.
5. Use Markdown only when the MCP tool explicitly accepts a Markdown string. Use Atlassian Document Format (ADF) when the REST/API schema requires a document object; do not send a plain string to an ADF field.
6. Update one pilot issue first and fetch it again. Inspect the returned representation before updating the remaining issues.
7. For a bulk update, keep a durable key-to-source mapping and an audit record of before/after hashes or canonical content.
8. Define the canonical comparison before mutating: compare the intended source with the fetched result after allowing only documented Jira conversions (for example, Markdown headings/lists/inline code to wiki markup or ADF). Do not treat a length check alone as fidelity verification.
9. Update one pilot issue first. If its canonical content, summary, issue type, Epic relationship, or links differ unexpectedly, stop and do not update the remaining issues. Do not auto-rollback or delete without explicit authorization.

Never replace an existing description with a shorter version merely because the requested change sounds small. Never send `null` or an omitted field unless the tool's update semantics are known.

### Verify after every mutation set

After creates, updates, Epic associations, or dependency links:

- fetch the affected issue(s) or use a verified batch read, and assert that every requested key is present exactly once;
- poll after writes when Jira indexing/read-after-write is eventually consistent;
- confirm project, issue type, key, summary, description sections, Epic association, and link direction as separate assertions;
- confirm no unintended parent, Epic field, or issue link was added;
- distinguish a summarized response from a full field response;
- check for truncation and unexpected formatting conversion using the precomputed canonical comparison;
- reconcile partial failures before retrying;
- report created/updated keys, pre-existing matches, failed operations, retries, and unresolved mismatches separately.

A successful tool response proves only that the request was accepted; it does not prove every requested field was persisted.

## Description Template

For parent tasks, prefer this structure:

```markdown
## Referência técnica

Documento: <stable reference or N/A>

## Contexto

<Why this work exists.>

## Problema / Por que isso importa

<Operational or architectural consequence of not doing it.>

## Pontos endereçados

- <Guideline/blueprint/requirement>
- <Guideline/blueprint/requirement>

## Objetivo

<Outcome expected from the task.>

## Escopo

- <Included work>
- <Included work>

## Fora de escopo

- <Excluded work>
- <Excluded work>

## Critérios de Aceitação

- <Observable acceptance criterion>
- <Observable acceptance criterion>
```

For subtasks, prefer a shorter structure:

```markdown
## Escopo

<Specific work for this subtask.>

## Local sugerido

`path/to/file.ext`

## Formato mínimo sugerido

```yaml

key:
  - value: example
```

## Critérios de Aceitação

- <Observable acceptance criterion>
- <Observable acceptance criterion>
```

## Code Blocks

### YAML/code block rule

Always include a blank line after the fenced language marker.

Good:

````markdown
```yaml

tables:
  - name: credit_instruments
    module: contracting
```
````

Bad:

````markdown
```yaml
tables:
  - name: credit_instruments
```
````

Why: some Jira conversions produce `{code:yaml}tables:` when there is no blank line, which renders poorly. The blank line forces `{code:yaml}` onto its own line.

### Keep code examples fenced

Do not replace structured examples with prose just because the first Jira render is poor. Fix the markup and preserve useful examples.

## Inline Code

Use backticks for:

- file paths: `docs/data-governance/table-classification.yaml`;
- field names: `audit_policy`;
- enum values: `technical_framework`;
- commands or config keys.

Jira may return these as `{{...}}`. That is acceptable.

## Verification After Create/Update

After creating or updating an issue, inspect the returned description.

Check:

1. Headings became `h2.` or equivalent.
2. Lists became `*` bullets or equivalent.
3. Inline code became `{{...}}` or equivalent.
4. Code blocks became `{code:yaml}` or equivalent.
5. The code-block opener is on its own line, not joined with content.
6. Useful examples were not removed.

If a code block returns like this:

```text
{code:yaml}tables:
```

Update the description by adding a blank line after the opening fenced marker:

````markdown
```yaml

tables:
```
````

## MCP/API Notes

- If the MCP tool schema says `description` is a Markdown string, send Markdown string, not Atlassian Document Format JSON.
- Use ADF only when the tool explicitly requires ADF or raw Jira REST v3 document objects.
- For Jira projects localized in Portuguese, issue types may also be localized, e.g. `Tarefa` and `Subtarefa`.

## Issue Links and Dependencies

For `jira_jira_create_issue_link` with `link_type: "Blocks"`, set the issue that **blocks** as `inward_issue_key` and the issue that **is blocked by it** as `outward_issue_key`.

Example dependency chain: `VAN-962` must finish before `VAN-963`.

```json
{
  "link_type": "Blocks",
  "inward_issue_key": "VAN-962",
  "outward_issue_key": "VAN-963"
}
```

Expected Jira wording:

- `VAN-962` **blocks** `VAN-963`.
- `VAN-963` **is blocked by** `VAN-962`.

Do not invert these fields. If the intended blocked issue shows the predecessor as `outward_issue`, remove the link and recreate it with the predecessor as `inward_issue_key`.

## Common Mistakes

| Mistake | Fix |
| --- | --- |
| Sending a long YAML example without a code fence | Wrap it in a fenced block with a blank line after language marker |
| Removing a YAML example because Jira rendered it badly | Preserve the example and fix the code block formatting |
| Treating `h2.` in returned description as an error | Accept it; Jira converted Markdown heading to wiki markup |
| Treating `{{path}}` as an error | Accept it; Jira converted inline code to wiki markup |
| Sending ADF JSON to a tool expecting a string | Send Markdown string unless the tool explicitly requests ADF |
| Creating all issues before checking render | Create/update one, inspect returned description, then continue |

## Quick Checklist

Before calling Jira create/update:

- [ ] Sections use `##` headings.
- [ ] Lists use `-` bullets.
- [ ] Paths and fields use backticks.
- [ ] Code/YAML examples use fenced code blocks.
- [ ] Fenced code blocks have a blank line after the language marker.
- [ ] Description was reviewed as the exact string that will be sent.

After Jira returns:

- [ ] Heading/list/inline-code conversion is acceptable.
- [ ] Code blocks are not glued to their content.
- [ ] No useful content was dropped.
