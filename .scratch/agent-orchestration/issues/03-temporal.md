# Investigar Temporal para orquestrar harnesses externos

Type: research
Status: resolved
Blocked by: 01, 09

## Question

O que Temporal oferece e exige para coordenar ciclos externos de implementação em sandbox, localmente e num piloto empresarial, preservando substituição de harness?

Aplicar a pauta comum abaixo, com fontes primárias e versões/data. Entregar um relatório de evidência em branch de pesquisa; não decidir adoção nem implementar.

### Pauta comum das três pesquisas

- Runtime local persistente versus modo dev; self-hosting de produção, dependências, HA, upgrades, operação e cloud opcional.
- Estado/workflow, checkpoints, replay, versionamento de código/workflow, evolução de execuções vivas.
- Semântica de retries/entrega e efeitos externos: explicar risco de duplicar branch/PR/comentário/processo; não vender exactly-once como garantia universal.
- Workers e concorrência: limite N de tickets, fairness, recursos, quotas, isolamento de equipes; distinguir limite de tarefa de limite de subprocesso.
- Pausa por ajuda, sinal/evento externo correlacionado, respostas duplicadas/tardias, espera sem ocupar worker, timeout e autorização fora do motor.
- Integração com executor externo arbitrário (Pi agora; outros futuramente), jobs longos, heartbeat/cancelamento, processos-filhos, crash e reconciliação. Explicar o que a biblioteca NÃO persiste.
- Observabilidade: UI, histórico, logs, métricas, tracing/OTel, árvore de agentes, dados sensíveis e retenção; distinguir instrumentação automática de instrumentação própria.
- Sandbox: mecanismos integrados ou integrações necessárias; fronteiras de filesystem/Git, rede e credenciais; não presumir que worker container é sandbox segura.
- Edições, licença, recursos pagos/self-hosted e modelo de custo; sem preços inventados ou comparações de desempenho sem medições.
- Forças, limitações, perguntas abertas e experimentos discriminantes, usando os mesmos cenários dos demais.

### Cenários a analisar

Worker caiu após commit e antes de registrar sucesso; resposta humana chega dias depois e duas vezes; scheduler reinicia enquanto execução está bloqueada; subagente segue vivo quando pai termina; container destruído com dirty files; upgrade do workflow com pedidos pendentes.

## Comments

- Pesquisa documental terminada. Workflow: `93313e50-aec4-41f6-8845-2e90e96d7866`; child run: `de26476d-7889-434e-815e-745c0f81e98e`. Nenhum subagente deste ticket permanece ativo.
- Branch preservada: `research/agent-orchestration-temporal`; worktree limpa: `.worktrees/agent-orchestration-temporal/`.
- Commit local imutável: `bc5dd53e2d8fa275503269e3ce930596f24da509`. [Ler relatório no commit publicado](https://github.com/Sanmoo/dotfiles/blob/bc5dd53e2d8fa275503269e3ce930596f24da509/docs/research/agent-orchestration/temporal.md). Recuperação independente da worktree: `git show bc5dd53e2d8fa275503269e3ce930596f24da509:docs/research/agent-orchestration/temporal.md`.
- Validação do pesquisador: **FULL GATE: PASS**; 28/28 unidades; 14,88 s; orçamento dentro. O responsável conferiu commit exclusivo do relatório e worktree/index limpos; leu o relatório e handoff. Isso não é auditoria independente exaustiva de claims nem prova ponta a ponta.
- Achados documentais para futura comparação, sem adoção: Replay não preserva sessão/dirty files/filhos; Activities e efeitos externos exigem reconciliação; Signals/Updates fornecem espera durável, não autorização; versionamento e operação de produção diferem do modo dev.
- Publicação falhou: `git push -u origin research/agent-orchestration-temporal` → `Host key verification failed.` / `fatal: Could not read from remote repository.` Nenhuma mudança de SSH/credenciais nem fallback. Sem URL remota confirmada.
- Ticket continua `claimed` para entrega pendente, não porque exista pesquisa rodando. Não resolver nem limpar recursos até [Desbloquear a publicação das evidências com confiança SSH validada](09-research-publication.md), ou decisão humana explícita de aceitar evidências apenas locais. Não refazer a pesquisa.
- Não houve PoC, benchmark, implementação, escolha de motor, merge ou PR.
- Relatório esperado: `docs/research/agent-orchestration/temporal.md` nessa branch; sem merge/PR. Resultado só resolve o ticket após verificação pelo responsável do mapa.

- Fontes iniciais: https://docs.temporal.io/ ; https://docs.temporal.io/self-hosted-guide ; https://learn.temporal.io/tutorials/ai/building-durable-ai-applications/human-in-the-loop/
- Comparação inicial na conversa foi exploratória, não evidência suficiente de adoção.


## Answer

Pesquisa documental entregue e publicada após nova tentativa explicitamente autorizada pelo humano. `git push -u origin research/agent-orchestration-temporal` teve sucesso; `git ls-remote` confirmou o SHA `bc5dd53e2d8fa275503269e3ce930596f24da509` no remote. Nenhuma configuração SSH, known_hosts, remote ou mecanismo de autenticação foi alterado. A causa da diferença entre as tentativas não foi diagnosticada; não atribuir correção a uma mudança não observada.

- Evidência canônica: [relatório publicado por SHA](https://github.com/Sanmoo/dotfiles/blob/bc5dd53e2d8fa275503269e3ce930596f24da509/docs/research/agent-orchestration/temporal.md). O detalhe técnico vive no relatório, não duplicado no mapa.
- Síntese: Replay/Activities, ajuda durável, versionamento e operação investigados; recuperação do harness e reconciliação permanecem externas.
- Full gate do relatório: **FULL GATE: PASS**. Leitura/revisão documental pelo responsável já registrada nos Comments; auditoria independente exaustiva e prova de execução não realizadas.
- Sem vencedor, PoC, benchmark, integração em `main` ou PR. `/implement` continua sendo uma skill do fluxo Pi, não contrato universal.
- Branch remota de pesquisa preservada; worktree e branch local ainda presentes e limpas. Links não dependem mais da worktree. Limpeza local pode ser tratada separadamente, sem apagar evidência remota.

Os Comments anteriores registram o bloqueio histórico, agora resolvido; não descrevem mais o estado atual de entrega.
