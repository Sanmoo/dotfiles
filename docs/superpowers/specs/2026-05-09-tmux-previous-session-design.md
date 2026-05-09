# Tmux Previous Session Toggle

## Problem

No tmux, há atalho para voltar à janela anterior (`C-a C-a` → `last-window`), mas não há atalho análogo para voltar à sessão anterior. Isso dificulta a navegação entre múltiplas sessões.

## Solution

Adicionar uma keybinding no prefix map que executa `last-session`.

### Keybinding

| Key       | Action                                    |
| --------- | ----------------------------------------- |
| `C-a C-s` | `last-session` (toggle para sessão anterior) |

- **Padrão**: Mesmo do `C-a C-a` (prefix + letra), onde `s` = **s**ession.
- **Comando**: `switch-client -l` — comando built-in do tmux que alterna o cliente entre a sessão atual e a anteriormente ativa.
- **Escopo**: Apenas no prefix map — não interfere com `C-s` global do terminal (controle de fluxo).

### Implementation

Uma única linha no `tmux/.config/tmux/tmux.conf.local`:

```tmux
bind-key -T prefix C-s switch-client -l
```

### Trade-offs

- **Simplicidade**: Zero scripts, zero plugins, zero dependências. Uma linha de config.
- **Comportamento**: Toggle puro — não serve para navegação cíclica entre várias sessões. Se precisar disso no futuro, `C-a s` (já built-in) mostra o session picker interativo.

### Locais afetados

- `tmux/.config/tmux/tmux.conf.local` — adicionar a binding
- Deploy via stow (nenhuma alteração no fluxo de deploy)
