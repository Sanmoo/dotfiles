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

The shared `~/.agents` and `~/.agents/skills` directories are real directories
outside this checkout. External skills, third-party adaptations, their source
links, and installation metadata such as `.skill-lock.json` are machine-local.
They are not distributed by these dotfiles. Editing a third-party skill does
not make it your own: maintain adaptations in the corresponding fork.

`agents/.agents/skills/` is reserved for skills authored by the user, maintained
independently, and containing no company-specific content. Currently that is
`jira-issue-formatting`. Add your own skills there; Stow links their files
individually, without owning the shared directory or replacing local entries.

### Apply configuration on a new or migrated machine

With GNU Stow and Python 3 available, run from this checkout:

```sh
general/bin/apply-agent-config "$PWD"
```

This command refuses symlinked shared directories, checks for conflicts first,
and applies `stow --no-folding agents`. It does not download, update, select, or
install dependencies. Use this guarded command for the agents package; ordinary
`stow agents` can fold the directory into a checkout link on a fresh home.
Apply other packages separately using the platform commands below.

### Install external dependencies separately

Choose the source and installation tool locally for each machine. For example,
on a personal machine using the existing Skills CLI:

```sh
cd "$HOME"
npx skills add mattpocock/skills -g
```

Other public sources can be installed the same way, such as `anthropics/skills`,
`vercel-labs/skills`, and `openai/skills`. Review the selection before installing.
An alternative is an individual link under `~/.agents/skills` to a separately
maintained checkout. Keep non-public sources and source selections local; there
is no employer profile or fork configuration in this repository. Updates belong
to the chosen tool/source, not to Stow or the bootstrap. Existing dependencies
remain untouched when applying configuration.

### Migrate a legacy checkout before integrating removals

Do not update a legacy checkout to the removal commit while `~/.agents` still
points into it: doing so can delete the only installed copy. Obtain the new
scripts in a separate worktree first, keeping the old checkout untouched. From
the old checkout, run the script from that worktree:

```sh
# migration_checkout is the worktree containing the new scripts.
"$migration_checkout/general/bin/migrate-agent-skills" "$PWD"
```

The command accepts an optional home agent path and `--backup NEW_DIRECTORY`.
If skills were also installed inside another Stow package, preserve those local
files in the same transition by explicitly supplying their directory. For the
legacy OpenCode package in this repository:

```sh
"$migration_checkout/general/bin/migrate-agent-skills" "$PWD" \
  --extra-skills "$PWD/opencode/.config/opencode/skills"
```

`--extra-skills` is repeatable and only copies existing local installations; it
does not download or choose an upstream. Name collisions between sources fail
before the link exchange, without overwriting either installation. All supplied
sources get verified recovery snapshots. On an already-migrated home the command
is a no-op and does not import newly supplied directories; manage subsequent
installations independently.

Without `--backup`, it creates a private `.agents-backup-*` directory beside
`~/.agents` and prints its path. It validates the legacy link against the
explicit checkout, copies the entire local directory without following links,
verifies contents and file modes, then installs an independent copy. The
checkout is not modified. Existing backup paths and unexpected states are
errors; an already-real external directory is a no-op.

Absolute external links, including unavailable targets, stay unchanged. Relative
links are rebased when needed, resolving intermediate symlinks before `..` and
retaining unavailable path suffixes. Links into the old directories are rebased
to the new directory, including paths that leave and re-enter a source. Recovery
snapshots keep every original link text. No external link target is copied or
modified; only path metadata is consulted when resolving a relative route.

Before integrating the removal, verify that the skills and metadata are present
under the real `~/.agents`. Keep the printed backup path. If local edits or links
in the old package block a fast-forward, preserve that exact package before
restoring **only that package's** tracked working-tree files:

```sh
# backup is the printed recovery directory; NEW_REF is the validated task ref.
mv agents/.agents "$backup/checkout-original"
git restore --source=HEAD --worktree -- agents/.agents
git merge --ff-only NEW_REF
```

If local changes in another supplied source also block integration, archive
that exact source in the same backup and restore only its affected tracked
paths before merging. Do not remove any source until the independent copy and
its snapshot have been verified. The removed OpenCode dependencies include
`docx`, `ppt-master`, `coding-guidelines`, `skill-architect`, and the externally
linked `article-summarizer`; their local copies belong outside the checkout.

This step requires an unchanged index for the package. Stop if staged edits or
other unexpected changes exist; do not stash, reset, or commit machine-local
links. Other configuration and other worktrees must remain untouched. Existing
Git history is preserved.

Then apply configuration with `general/bin/apply-agent-config "$PWD"`. A
preserved local file with the same name as an owned file is a Stow conflict,
not permission to overwrite it. Compare it first; if identical, archive the
local file in the backup before linking the owned version. If different, keep
it in place and decide how to reconcile it. Keep recovery backups until you
have verified the installation; they may contain private machine-local data.

### Recover an interrupted migration

Before the link exchange, the original checkout and link are unchanged. During
exchange, the original link is saved as `BACKUP/legacy-link`; `snapshot` keeps
the verified contents and `recovery.json` records the original paths. Ordinary
errors and handled interruptions restore the link when possible. Even an
unrecoverable process kill leaves both the original checkout and snapshot.

If `~/.agents` is missing and `BACKUP/legacy-link` exists, restore it with
`mv BACKUP/legacy-link "$HOME/.agents"` before retrying. Never overwrite an
existing entry: inspect it first. Do not remove the legacy package after a
failed migration. If its files were already archived for integration, restore
that archive to its original checkout path before restoring the legacy link.

### Validate without touching real installations

```sh
bash tests/external-skills-local-installation-test.sh
```

The shell integration test uses temporary homes, fictitious skills, real Stow,
and a local Git fixture. It exercises conflicts, backup-copy failure via an OS
write limit, repeatability, link relocation, the complete removal/integration
order, and installation of a new dependency without checkout changes.

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
