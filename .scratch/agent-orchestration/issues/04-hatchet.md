# Investigar Hatchet para orquestrar harnesses externos

Type: research
Status: claimed
Blocked by: 01, 09

## Question

O que Hatchet oferece e exige para coordenar ciclos externos de implementação em sandbox, localmente e num piloto empresarial, preservando substituição de harness?

Aplicar integralmente a mesma pauta e os mesmos cenários de [Investigar Temporal para orquestrar harnesses externos](03-temporal.md), sem assumir equivalência entre task queue e workflow durável. Verificar recursos efetivos da versão/edição, concorrência por slots, waits/eventos, checkpoint e limitações de tarefas longas.

Entregar relatório de evidência em branch de pesquisa. Não decidir adoção, atribuir pesos ou implementar.

## Comments

- Pesquisa documental terminada. Workflow: `93313e50-aec4-41f6-8845-2e90e96d7866`; child run: `5c4c2dd3-6b1a-4282-82aa-e7cad386832a`. Nenhum subagente deste ticket permanece ativo.
- Branch preservada: `research/agent-orchestration-hatchet`; worktree limpa: `.worktrees/agent-orchestration-hatchet/`.
- Commit local imutável: `b29b47f4e498aa6a010411d37d0714acc5bc8ac3`. [Ler relatório local](../../../.worktrees/agent-orchestration-hatchet/docs/research/agent-orchestration/hatchet.md). Recuperação independente da worktree: `git show b29b47f4e498aa6a010411d37d0714acc5bc8ac3:docs/research/agent-orchestration/hatchet.md`.
- Validação do pesquisador: **FULL GATE: PASS**; 28/28 unidades; aviso não fatal de orçamento na execução final (focus-next-actionable-agent, 6,06 s versus teto de 5 s). O responsável conferiu commit exclusivo do relatório e worktree/index limpos; leu o relatório e handoff. Isso não é auditoria independente exaustiva de claims nem prova ponta a ponta.
- Achados documentais para futura comparação, sem adoção: Ordinary tasks são at-least-once; durable waits/eviction liberam slots, não demonstram N de tickets; versão de definição não comprova pinning do código; disponibilidade comercial de RBAC/SSO/audit exige confirmação.
- Publicação falhou: `git push -u origin research/agent-orchestration-hatchet` → `Host key verification failed.` / `fatal: Could not read from remote repository.` Nenhuma mudança de SSH/credenciais nem fallback. Sem URL remota confirmada.
- Ticket continua `claimed` para entrega pendente, não porque exista pesquisa rodando. Não resolver nem limpar recursos até [Desbloquear a publicação das evidências com confiança SSH validada](09-research-publication.md), ou decisão humana explícita de aceitar evidências apenas locais. Não refazer a pesquisa.
- Não houve PoC, benchmark, implementação, escolha de motor, merge ou PR.
- Relatório esperado: `docs/research/agent-orchestration/hatchet.md` nessa branch; sem merge/PR. Resultado só resolve o ticket após verificação pelo responsável do mapa.

- Fontes iniciais: https://docs.hatchet.run/v1 ; https://docs.hatchet.run/v1/durable-execution ; https://github.com/hatchet-dev/hatchet
