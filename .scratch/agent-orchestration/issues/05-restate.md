# Investigar Restate para orquestrar harnesses externos

Type: research
Status: claimed
Blocked by: 01, 09

## Question

O que Restate oferece e exige para coordenar ciclos externos de implementação em sandbox, localmente e num piloto empresarial, preservando substituição de harness?

Aplicar integralmente a mesma pauta e os mesmos cenários de [Investigar Temporal para orquestrar harnesses externos](03-temporal.md). Distinguir services, virtual objects e workflows; journal/replay de estado real do subprocesso; implantação local, self-hosted, HA e restrições de licença/edição.

Entregar relatório de evidência em branch de pesquisa. Interesse do humano em Restate não autoriza recomendação sem trade-offs e evidência. Não decidir adoção, atribuir pesos ou implementar.

## Comments

- Pesquisa documental terminada. Workflow: `93313e50-aec4-41f6-8845-2e90e96d7866`; child run: `37c1a27a-80c0-4f33-b71c-7ae8f286c7d9`. Nenhum subagente deste ticket permanece ativo.
- Branch preservada: `research/agent-orchestration-restate`; worktree limpa: `.worktrees/agent-orchestration-restate/`.
- Commit local imutável: `e67e1fc28039c7cdda4c9379235ed0fcf21bb6ab`. [Ler relatório local](../../../.worktrees/agent-orchestration-restate/docs/research/agent-orchestration/restate.md). Recuperação independente da worktree: `git show e67e1fc28039c7cdda4c9379235ed0fcf21bb6ab:docs/research/agent-orchestration/restate.md`.
- Validação do pesquisador: **FULL GATE: PASS**; 28/28 unidades; 13,56 s; orçamento dentro. O responsável conferiu commit exclusivo do relatório e worktree/index limpos; leu o relatório e handoff. Isso não é auditoria independente exaustiva de claims nem prova ponta a ponta.
- Achados documentais para futura comparação, sem adoção: Journal não salva harness/filesystem; exclusividade por chave não é limite global N; deployments antigos precisam continuar para execuções vivas; servidor BSL 1.1 e SDK TypeScript MIT são licenças distintas; flow control exige atenção a APIs experimentais.
- Publicação falhou: `git push -u origin research/agent-orchestration-restate` → `Host key verification failed.` / `fatal: Could not read from remote repository.` Nenhuma mudança de SSH/credenciais nem fallback. Sem URL remota confirmada.
- Ticket continua `claimed` para entrega pendente, não porque exista pesquisa rodando. Não resolver nem limpar recursos até [Desbloquear a publicação das evidências com confiança SSH validada](09-research-publication.md), ou decisão humana explícita de aceitar evidências apenas locais. Não refazer a pesquisa.
- Não houve PoC, benchmark, implementação, escolha de motor, merge ou PR.
- Relatório esperado: `docs/research/agent-orchestration/restate.md` nessa branch; sem merge/PR. Resultado só resolve o ticket após verificação pelo responsável do mapa.

- Fontes iniciais: https://docs.restate.dev/ ; https://docs.restate.dev/services/introspection ; https://github.com/restatedev/restate
