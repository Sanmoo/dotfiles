# pi-auto-rename: alerta para modelo inválido

## Objetivo

Informar imediatamente quando `pi-auto-rename` estiver configurado com um modelo indisponível, apontando o arquivo de configuração que precisa ser corrigido.

## Comportamento

Durante `session_start`, a extensão valida o modelo configurado contra `ctx.modelRegistry` antes de tentar gerar nome de sessão.

Quando o modelo não existir:

- exibir notificação de nível `error` logo no início da sessão;
- incluir referência completa `provider/model` configurada;
- incluir caminho explícito `~/.pi/agent/extensions/pi-auto-rename.json`;
- não chamar modelo nem tentar renomear sessão automaticamente;
- manter comandos `/rename` disponíveis para corrigir ou resetar configuração.

Mensagem esperada:

```text
pi-auto-rename: modelo inválido: provider/model.
Corrija: ~/.pi/agent/extensions/pi-auto-rename.json
```

O valor real de `provider/model` substitui o placeholder.

## Implementação

Extrair validação reutilizável ou adaptar `resolveAuth` para separar existência do modelo de autenticação. A validação inicial deve detectar modelo ausente sem depender de chamada ao provedor. O caminho exibido deve ser derivado da mesma constante usada para leitura e escrita, evitando divergência.

`autoName` deve encerrar antes de marcar ou iniciar tentativa de nomenclatura quando modelo não existir. Com modelo existente, fluxo atual permanece inalterado.

## Testes

Adicionar teste unitário para a mensagem de configuração inválida, verificando que contém:

- prefixo `pi-auto-rename`;
- referência do modelo;
- caminho do arquivo de configuração.

Manter testes existentes de prompts locais e sanitização de nomes.

## Critérios de aceite

- Sessão inicia com erro visível para modelo inexistente.
- Mensagem aponta modelo e arquivo correto.
- Nenhuma requisição de geração é feita nesse caso.
- Configuração válida continua gerando nome normalmente.
- Testes passam.
