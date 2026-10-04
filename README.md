# How to

## Global agent instructions

`general/AGENTS.md` is the shared source of default agent instructions. Install
with `stow general pi` from this repository after integrating changes into the
main checkout:

- `general` installs `~/AGENTS.md` for agents that discover instructions in parent
  directories (repositories under the home directory).
- `pi` installs `~/.pi/agent/AGENTS.md`, linked to the same source, so Pi also loads
  the defaults for repositories outside the home directory.

Restart the agent session after installation (or run `/reload` in Pi). Agents
with a different instruction-loading mechanism need their own configuration;
`AGENTS.md` is guidance, not a Git enforcement hook.

The defaults require a dedicated branch and a worktree under the target
repository's gitignored `.worktrees/` directory for new development. On successful
completion, the agent commits the task's changes, integrates them into the
original branch with `git merge --ff-only`, and removes the task's worktree and
branch. If integration or cleanup is blocked, it preserves the remaining work
and asks how to proceed. Explicit user instructions or workflow rules in a
repository-specific `AGENTS.md` take precedence.

## Agent skills

`agents/.agents/skills/` contains only skills authored in this repository. When
applying the package, use Stow's `--no-folding` option so it links owned files
into the real `~/.agents` directory without taking ownership of that shared
directory. Skills installed from external sources and their lockfiles stay in
`~/.agents` and are managed separately.

Apply the configuration with `stow --no-folding agents`. Install or update external skills
using the tool and source you choose for that machine. The bootstrap does not
download, update, or select external skills.

If `~/.agents` is still a symlink to this checkout, migrate it before removing
the old tracked files:

```sh
migrate-agent-skills ~/.agents
```

The command moves the linked directory before replacing the link with a real
directory. It preserves regular files, untracked files, lockfiles, symlinks, and
symlink destinations. It refuses an existing destination, treats an already-real
directory as a safe no-op, and keeps the old state recoverable if an operation
fails.

A skill with `disable-model-invocation: true` in its frontmatter is kept out of
the model's context and starts only when explicitly asked for with
`/skill:<name>`. `gh-address-comments` uses this so it never fires on its own.

## For `Omarchy`

`stow general git hypr nvim tasks tmux zsh pi pi-linux`

### Disable automatic suspend

The Hypridle config in `hypr/.config/hypr/hypridle.conf` intentionally does not
run `systemctl suspend` or `loginctl suspend`. It only locks the session and turns
the display off after inactivity.

Apply it with:

```sh
stow hypr
pkill hypridle
hypridle &
```

If the notebook still suspends when the lid is closed, configure systemd-logind
outside this repo in `/etc/systemd/logind.conf`:

```conf
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
IdleAction=ignore
```

Then run:

```sh
sudo systemctl restart systemd-logind
```

## For MacOS

`stow aerospace general ghostty git nvim tasks tmux zsh pi pi-mac`
