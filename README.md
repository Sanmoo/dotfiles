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

`agents/.agents/skills/` installs to `~/.agents/skills/`, the shared skills
location that Pi discovers in every session. `~/.agents` is a symlink into this
repository, so a new skill directory takes effect immediately; `stow agents` is
only needed on a fresh machine.

Skills are vendored and tracked in Git, so adding one needs no `git add -f`. The
exceptions are the machine-local symlinks that point outside the repository
(`omarchy`, `orchestrated-work-companion`), which `agents/.agents/.gitignore`
excludes.

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
