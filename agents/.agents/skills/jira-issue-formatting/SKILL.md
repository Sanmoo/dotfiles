---
name: jira-issue-formatting
description: Use when creating or updating Jira issue descriptions through MCP/API, especially with sections, bullets, inline paths, acceptance criteria, YAML/code blocks, or subtasks.
---

# Jira Issue Formatting

## Overview

Jira descriptions sent through MCP/API often accept a Markdown string but return Jira wiki markup. Format descriptions deliberately and verify the returned description after create/update.

Core principle: send readable Markdown, expect Jira to convert it, and fix rendering issues without deleting useful content.

## When to Use

Use this before creating or updating Jira issues when the description includes:

- structured sections;
- acceptance criteria;
- bullet lists;
- inline file paths, field names, or config keys;
- YAML, JSON, SQL, shell, or other code blocks;
- parent tasks with subtasks.

Do not use this for plain one-line issue descriptions.

## Expected Jira Conversion

When using tools such as `jira_jira_create_issue` or `jira_jira_update_issue` with a string `description`, Jira may return wiki markup:

| Send | Jira may return | Meaning |
| --- | --- | --- |
| `## Escopo` | `h2. Escopo` | OK; heading rendered |
| `- item` | `* item` | OK; bullet rendered |
| `` `path/file.yaml` `` | `{{path/file.yaml}}` | OK; inline code rendered |
| fenced code block | `{code:lang}...{code}` | OK if opening marker and content are on separate lines |

This conversion is expected. Do not “fix” it back unless rendering is broken.

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
