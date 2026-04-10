# Templates

Use these templates when drafting Jira-ready items from a design doc.

## Parent Task Template

Use this ticket body for the Jira description. Keep Jira links outside the description as explicit draft metadata.

```markdown
Contexto
[Resumo do problema, da decisao do design doc e do recorte tecnico desta task.]

Objetivo
[Resultado tecnico coeso que esta task organiza.]

Requisitos Tecnicos
[ ] Entrega tecnica 1
[ ] Entrega tecnica 2
[ ] Entrega tecnica 3

Criterios de Aceitacao
[ ] O objetivo tecnico da task fica claramente coberto pelas subtarefas
[ ] Cada subtask proposta gera um PR mergeavel na main
[ ] O recorte respeita as fronteiras tecnicas definidas no design doc

Notas Tecnicas
- Design doc relacionado: ...
- Dependencias relevantes: ...
- Fora de escopo: ...
```

## Subtask Template

Use this ticket body for the Jira description. Keep Jira links outside the description as explicit draft metadata.

```markdown
Contexto
[Recorte tecnico especifico derivado da task pai.]

Objetivo
[Entrega unica, pequena e mergeavel.]

Requisitos Tecnicos
[ ] Mudanca principal
[ ] Ajuste de teste, mock, snapshot, OpenAPI ou documentacao necessario para manter a main integra
[ ] Restricao ou cuidado tecnico relevante, quando aplicavel

Criterios de Aceitacao
[ ] O comportamento ou contrato esperado fica implementado
[ ] Os artefatos impactados ficam consistentes no mesmo PR
[ ] A subtask gera um PR mergeavel na main

Notas Tecnicas
- Dependencia de: ...
- Referencia do design doc: ...
- Fora de escopo: ...
```

## Suggested Parent Titles

- `Discovery: [capacidade ou decisao tecnica]`
- `[Modulo]: [fundacao ou capacidade principal]`
- `[Fluxo]: [adaptacao principal alinhada ao design doc]`

## Draft Presentation Wrapper

When presenting a draft breakdown before Jira creation, wrap each item with explicit Jira metadata outside the ticket body.

Example for a technical parent task:

```markdown
Tipo: Tarefa
Titulo: SmartConditions: implementar metadata de Finance Condition por produto
Vinculos Jira:
- Relates to: VAN-256
- Blocks: VAN-382

Descricao:
[usar o template da task pai abaixo]
```

Example for a subtask:

```markdown
Tipo: Subtarefa
Parent: VAN-381
Titulo: SmartConditions: expor ListFinanceConditionMetadataByProductUseCase na API do modulo
Vinculos Jira:
- Blocks: VAN-387

Descricao:
[usar o template da subtask abaixo]
```

If there is no confirmed business story yet, write:

```markdown
Vinculos Jira:
- Relates to: pendente de confirmacao
```

## Suggested Subtask Title Patterns

- `[Modulo]: criar [fundacao tecnica]`
- `[Modulo]: expor [contrato ou use case]`
- `[Modulo consumidor]: adaptar [endpoint, fluxo ou integracao]`
- `[Operacao]: validar [capacidade fim a fim]`

## Wording Guidance

- Use Portuguese for headings and prose.
- Keep the text technical, not managerial.
- Keep `Objetivo` focused on the result, not on a vague action.
- Write `Requisitos Tecnicos` as concrete implementation work.
- Write `Criterios de Aceitacao` as observable outcomes.
- Use `Notas Tecnicas` for dependencies, references, assumptions, and explicit out-of-scope notes.

## Common Rewrites

Prefer these rewrites when the text starts too generic.

- Instead of `Realizar ajustes necessarios`, write `Adaptar o endpoint para consumir a nova metadata do modulo`.
- Instead of `Atualizar testes`, write `Atualizar os testes impactados pelo novo contrato do endpoint no mesmo PR`.
- Instead of `Finalizar implementacao`, write `Concluir a exposicao da API publica do modulo sem acesso direto do use case ao adapter de configuracao`.
