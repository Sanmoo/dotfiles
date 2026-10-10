# Investigar Hatchet para orquestrar harnesses externos

Type: research
Status: claimed
Blocked by: 01

## Question

O que Hatchet oferece e exige para coordenar ciclos externos de implementação em sandbox, localmente e num piloto empresarial, preservando substituição de harness?

Aplicar integralmente a mesma pauta e os mesmos cenários de [Investigar Temporal para orquestrar harnesses externos](03-temporal.md), sem assumir equivalência entre task queue e workflow durável. Verificar recursos efetivos da versão/edição, concorrência por slots, waits/eventos, checkpoint e limitações de tarefas longas.

Entregar relatório de evidência em branch de pesquisa. Não decidir adoção, atribuir pesos ou implementar.

## Comments

- Identidade Git local fornecida pelo humano; pesquisa reservada pelo responsável do mapa para lançamento em background. Branch: `research/agent-orchestration-hatchet`, worktree: `.worktrees/agent-orchestration-hatchet/`. O responsável registra o identificador da execução após lançamento.
- Relatório esperado: `docs/research/agent-orchestration/hatchet.md` nessa branch; sem merge/PR. Resultado só resolve o ticket após verificação pelo responsável do mapa.

- Fontes iniciais: https://docs.hatchet.run/v1 ; https://docs.hatchet.run/v1/durable-execution ; https://github.com/hatchet-dev/hatchet
