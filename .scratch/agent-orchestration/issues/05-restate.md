# Investigar Restate para orquestrar harnesses externos

Type: research
Status: resolved
Blocked by: 01, 09

## Question

O que Restate oferece e exige para coordenar ciclos externos de implementação em sandbox, localmente e num piloto empresarial, preservando substituição de harness?

Aplicar integralmente a mesma pauta e os mesmos cenários de [Investigar Temporal para orquestrar harnesses externos](03-temporal.md). Distinguir services, virtual objects e workflows; journal/replay de estado real do subprocesso; implantação local, self-hosted, HA e restrições de licença/edição.

Entregar relatório de evidência em branch de pesquisa. Interesse do humano em Restate não autoriza recomendação sem trade-offs e evidência. Não decidir adoção, atribuir pesos ou implementar.

## Comments

- Pesquisa documental terminada. Workflow: `93313e50-aec4-41f6-8845-2e90e96d7866`; child run: `37c1a27a-80c0-4f33-b71c-7ae8f286c7d9`. Nenhum subagente deste ticket permanece ativo.
- Branch preservada: `research/agent-orchestration-restate`; worktree limpa: `.worktrees/agent-orchestration-restate/`.
- Commit local imutável: `e67e1fc28039c7cdda4c9379235ed0fcf21bb6ab`. [Ler relatório no commit publicado](https://github.com/Sanmoo/dotfiles/blob/e67e1fc28039c7cdda4c9379235ed0fcf21bb6ab/docs/research/agent-orchestration/restate.md). Recuperação independente da worktree: `git show e67e1fc28039c7cdda4c9379235ed0fcf21bb6ab:docs/research/agent-orchestration/restate.md`.
- Validação do pesquisador: **FULL GATE: PASS**; 28/28 unidades; 13,56 s; orçamento dentro. O responsável conferiu commit exclusivo do relatório e worktree/index limpos; leu o relatório e handoff. Isso não é auditoria independente exaustiva de claims nem prova ponta a ponta.
- Achados documentais para futura comparação, sem adoção: Journal não salva harness/filesystem; exclusividade por chave não é limite global N; deployments antigos precisam continuar para execuções vivas; servidor BSL 1.1 e SDK TypeScript MIT são licenças distintas; flow control exige atenção a APIs experimentais.
- Publicação falhou: `git push -u origin research/agent-orchestration-restate` → `Host key verification failed.` / `fatal: Could not read from remote repository.` Nenhuma mudança de SSH/credenciais nem fallback. Sem URL remota confirmada.
- Ticket continua `claimed` para entrega pendente, não porque exista pesquisa rodando. Não resolver nem limpar recursos até [Desbloquear a publicação das evidências com confiança SSH validada](09-research-publication.md), ou decisão humana explícita de aceitar evidências apenas locais. Não refazer a pesquisa.
- Não houve PoC, benchmark, implementação, escolha de motor, merge ou PR.
- Relatório esperado: `docs/research/agent-orchestration/restate.md` nessa branch; sem merge/PR. Resultado só resolve o ticket após verificação pelo responsável do mapa.

- Fontes iniciais: https://docs.restate.dev/ ; https://docs.restate.dev/services/introspection ; https://github.com/restatedev/restate


## Answer

Pesquisa documental entregue e publicada após nova tentativa explicitamente autorizada pelo humano. `git push -u origin research/agent-orchestration-restate` teve sucesso; `git ls-remote` confirmou o SHA `e67e1fc28039c7cdda4c9379235ed0fcf21bb6ab` no remote. Nenhuma configuração SSH, known_hosts, remote ou mecanismo de autenticação foi alterado. A causa da diferença entre as tentativas não foi diagnosticada; não atribuir correção a uma mudança não observada.

- Evidência canônica: [relatório publicado por SHA](https://github.com/Sanmoo/dotfiles/blob/e67e1fc28039c7cdda4c9379235ed0fcf21bb6ab/docs/research/agent-orchestration/restate.md). O detalhe técnico vive no relatório, não duplicado no mapa.
- Síntese: Journal, objetos/workflows, espera e operação investigados; licença BSL do servidor, MIT do SDK e flow control experimental explicitados.
- Full gate do relatório: **FULL GATE: PASS**. Leitura/revisão documental pelo responsável já registrada nos Comments; auditoria independente exaustiva e prova de execução não realizadas.
- Sem vencedor, PoC, benchmark, integração em `main` ou PR. `/implement` continua sendo uma skill do fluxo Pi, não contrato universal.
- Branch remota de pesquisa preservada; worktree e branch local ainda presentes e limpas. Links não dependem mais da worktree. Limpeza local pode ser tratada separadamente, sem apagar evidência remota.

Os Comments anteriores registram o bloqueio histórico, agora resolvido; não descrevem mais o estado atual de entrega.
