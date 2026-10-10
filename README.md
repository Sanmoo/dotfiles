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

## Run the tests

The Quality gateway runs from this checkout with `tests/run`, the single entry
point for the repository's tests:

```sh
tests/run          # Fast gate: fast-tier tests, cheap enough to re-run while working
tests/run --full   # Full gate: both tiers, ending with the FULL GATE: verdict line
```

A bare `tests/run` runs the Fast gate only: the fast-tier files from `tests/`,
`general/bin`, and the Bun suite under `pi/tests`. `tests/run --full` runs the
Full gate — the Fast gate's files plus the slow-tier tests — and its last line is
`FULL GATE: PASS` or `FULL GATE: FAIL`. A green Fast gate is necessary but never
sufficient: a task is not finished until `tests/run --full` reports
`FULL GATE: PASS`.

Every run also reports its duration budget: a per-unit ceiling for each tier
(fast 5s, slow 60s) and a total for the gate being run (Fast 5s, Full 75s). A
unit over its ceiling is marked `OVER BUDGET` as it finishes, and the summary
names every breach. A breach is reported and never changes the exit status — a
red suite means a broken assertion, not a slow machine — so the numbers are
there to be read rather than to fail the run. Why they exist, and why the Full
gate is allowed to cost tens of seconds, is in
`docs/adr/0006-duration-is-reported-not-enforced.md`.

Both commands work from any directory, bound every test with a timeout, and stop
with a runner error (exit 2) when a required tool such as `bun` or `timeout` is
missing. On macOS the gate needs two tools the stock system lacks — GNU coreutils
for `timeout` (used as `gtimeout`) and `flock` for the safe-pi entrypoint test.
Install them with `brew install coreutils flock`. The individual tests below
remain useful on their own; the runner is what makes them the Quality gateway.

## Agent skills

The shared `~/.agents` and `~/.agents/skills` directories are real directories
outside this checkout. Skill *content* installed from a third party stays
machine-local: the checkout distributes neither external skills nor the global
installation metadata (`.skill-lock.json`) that `skills update -g` maintains.
Editing a third-party skill does not make it your own: maintain adaptations in
the corresponding fork.

What the checkout does track is the **per-machine manifest**, `skills-lock.json`
— the file the Skills CLI reads and rewrites in project scope. Each machine
stows exactly one profile package, the same variant pattern used for `pi-linux`
and `pi-mac`:

| Package | Provides | Machine |
| --- | --- | --- |
| `skills-personal` | `~/skills-lock.json` | personal Linux laptop, upstream sources |
| `skills-corporate` | `~/skills-lock.json` | corporate macOS laptop, fork sources |

Both packages provide the same path, so exactly one is stowed per machine; never
both. `general/bin/skills-sync` replays that manifest through the CLI and
reapplies the patches tracked in `skills-patches/`. See
[Manage external skills from the manifest](#manage-external-skills-from-the-manifest)
and `skills-sync --help`.

`agents/.agents/skills/` is reserved for skills authored by the user, maintained
independently, and containing no company-specific content. Currently that is
`jira-issue-formatting`. Add your own skills there and commit them; Stow links
their files individually, without owning the shared directory or replacing
local entries.

### Apply configuration on a new or migrated machine

With GNU Stow and Python 3 available, run from this checkout:

```sh
general/bin/apply-agent-config "$PWD"
```

This command refuses symlinked shared directories, checks for conflicts first,
and applies `stow --no-folding agents`. It publishes only content tracked by the
checkout: machine-local entries under the package — external skill installs,
their source links, and installation metadata — are left out, so applying works
even when such installs exist. The checkout must be a Git work tree, and an
authored skill must be committed before it is applied; use `stow agents` by hand
to link work in progress. The command does not download, update, select, or
install dependencies. Use this guarded command for the agents package; ordinary
`stow agents` can fold the directory into a checkout link on a fresh home.
Apply other packages separately using the platform commands below.

### Manage external skills from the manifest

Dependencies are managed separately from the bootstrap, on the machine that owns
the choice of source. With the profile package stowed:

```sh
skills-sync                  # reinstall and repair everything the manifest declares
skills-sync update           # refresh only what changed upstream
skills-sync add tech-leads-club/agent-skills -s harness-eval
skills-sync remove harness-eval
skills-sync diff             # compare this profile with the other one
```

Run the CLI without `-g`. A global install is recorded in the machine-local
`~/.agents/.skill-lock.json`, not in the tracked manifest, so the machine would
not be reproducible from this checkout; `skills-sync add` refuses `-g` for that
reason. Other public sources such as `anthropics/skills`, `vercel-labs/skills`
and `openai/skills` work the same way.

Because the CLI rewrites the manifest through the Stow symlink, the tracked copy
changes as skills are added or updated. Review it with `git diff` and commit it
like a lockfile. The two profiles drift independently by design — a skill added
on one machine is not added to the other — and `skills-sync diff` is how the gap
is spotted; the command exits 1 when the profiles differ.

Local tweaks that the CLI would otherwise drop live in `skills-patches/`, one
frontmatter line per line, keyed by skill name; `skills-sync` reapplies them after
every install. Today that is only `harness-eval`, whose 836-character description
would otherwise enter the system prompt of every session. The patches are read
from the checkout, not from `$HOME`, so they need no package of their own.

An alternative for a dependency that ships no usable manifest is an individual
link under `~/.agents/skills` to a separately maintained checkout. Updates belong
to the chosen tool or source, not to Stow or the bootstrap. The bootstrap never
installs, updates or selects a dependency, and applying configuration leaves
existing installations untouched.

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

## Run Pi in the sandbox (`safe-pi`)

`safe-pi` runs Pi in a throwaway Docker container that sees the repository you
are in, your Pi configuration and credentials, and the declared environment
installed inside the container from the repository's tracked mise
configuration — and nothing else in your home directory. `stow pi` installs it
beside `pi` itself.

### First run

```sh
cd ~/dev/github.com/you/some-repo
safe-pi
```

The first run builds the image — about a minute when its layers are cold — and
installs the declared environment into the per-user toolchain volume
`safe-pi-toolchain-u<uid>`: about 13 seconds inside mise, 17 seconds of wall
clock for the whole run. The volume is shared by every repository, so the
download happens once per user. Later runs start in about three seconds, almost
all of it container startup. The first start also compiles the TypeScript
extensions Pi loads — about ten seconds, once — and keeps the result in the
sandbox's own cache, so later starts reuse it instead of compiling again.

The declared environment is converged on every start, so `latest` pins follow
new releases the way they do on the host. Two tools are the exception:
`erlang` (`29.0.4`) and `elixir` (`1.20.2-otp-29`) are pinned, and the sandbox
installs them from a precompiled Ubuntu 22.04 OTP build instead of compiling
OTP. Bump those two pins by hand; the rest keep moving with `latest`.

### Everyday recipes

| What you want | Command |
| --- | --- |
| Continue the last conversation in this directory | `safe-pi -c` |
| Resume a specific session | `safe-pi --session <id-or-path>` |
| A one-shot prompt | `safe-pi -p "explain this file"` |
| A specific model | `safe-pi --model opencode-go/deepseek-v4-flash` |
| Skip the lens analyzers for this session | `safe-pi --no-lens` |
| A shell inside the sandbox | `safe-pi --shell` |
| Install the declared environment and exit | `safe-pi --prepare` |
| Refresh Pi inside the image to the latest release | `safe-pi --update` |
| Anything else Pi accepts | `safe-pi <any pi flag>` |

### safe-pi's own flags

| Flag | Effect |
| --- | --- |
| `--rebuild` | rebuild the image with the version it already has |
| `--update` | refresh the image with the latest Pi release |
| `--shell` | start a shell instead of Pi, with the same mounts |
| `--prepare` | converge the declared environment into the toolchain volume, do not start Pi |
| `--dry-run` | print the Docker command and exit |
| `help` | safe-pi's own usage |

`-h`, `--help`, and `--version` are passed to Pi, not consumed by `safe-pi`.

### What the sandbox sees

- Your repository, read-write, at the same absolute path — writes land on the
  host.
- Your Pi configuration, credentials, sessions, skills, prompts, agents, and
  extensions, shared with the host Pi. Extensions are read-only inside the
  sandbox.
- Pi's git-installed packages (`pi install git:...`, cloned under
  `~/.pi/agent/git`), shared with the host Pi and read-only inside the sandbox.
  Installing, updating or removing a git package must be done from the host
  Pi: inside the sandbox those commands fail with a read-only file system error.
  A git package whose clone or dependencies are missing fails to install in the
  sandbox, and the host Pi installs it on its next start.
- Pi's npm packages, as the sandbox's own **sandbox package tree**, installed
  inside the sandbox from your host's `package.json` and `package-lock.json` so
  their native parts match the sandbox's platform. It lives in
  `~/.cache/safe-pi/npm` on the host; your host's own `~/.pi/agent/npm` is not
  reachable from the sandbox.
- Your shell's SSH agent and Herdr's socket, plus a sandbox reporter that
  reports the pane as `working`
  and `idle`. On macOS both sockets arrive through a socket relay over the
  Colima VM's SSH (see below). Herdr's own Pi integration is disabled inside the
  sandbox,
  because Herdr ignores it for a pane whose foreground process is `docker`.
  The `permission-gate` extension registers nothing inside the sandbox — the
  container is the boundary there, so dangerous commands run without a prompt,
  and the pane never reports `blocked`.
- The declared environment installed inside the container from the repository's
  tracked mise configuration, kept in the toolchain volume.
- Not your host toolchain, not other repositories, not the rest of your home
  directory, not the Docker socket.

### On macOS (Colima only)

`safe-pi` runs on macOS against [Colima](https://github.com/abiosoft/colima)
(`brew install colima docker`). The Docker daemon lives in a VM that cannot see
your shell's SSH agent socket or Herdr's, and a unix socket does not cross the
shared filesystem anyway, so each start opens a **socket relay**: its own SSH
connection to the Colima VM, with one forward per socket into a directory private
to that start. The forwarded sockets are mounted where the sandbox expects them,
and the connection and directory are removed when the sandbox exits.

- The relay follows the invoking shell's `$SSH_AUTH_SOCK`, so `ssh-add` in the
  shell you start `safe-pi` from decides which keys the sandbox can sign with.
  Herdr's socket is relayed when the Herdr variables are set.
- It opens while the image checks run, and adds about 0.9 seconds to a start
  that has to wait for it.
- A relay that cannot be opened is a warning, per socket
  (`safe-pi: SSH agent unavailable in the sandbox: <reason>`), and the sandbox
  starts without that socket.
- `--prepare` opens no relay; `--dry-run` prints the relay commands before the
  Docker command and runs neither.
- Any other daemon on macOS (Docker Desktop, OrbStack, plain Lima) is refused with
  `safe-pi on macOS supports Colima only`. For a Colima profile other than the
  default, `safe-pi` uses the `colima-<profile>` host alias in
  `~/.colima/ssh_config`.
- The sandbox user's home is your `$HOME` (`/Users/<you>`), so every path matches
  the host's. An image built for another home is rebuilt on the next start.

### Things worth knowing

- If the network is unavailable when convergence has something to install,
  `safe-pi` warns and opens Pi anyway; `--prepare` reports the failure instead.
- A repository's own `.mise.toml` pins are installed on first use and stay in the
  toolchain volume, so switching repositories does not re-download them.
- After a Herdr server restart, a sandboxed pane comes back inside the sandbox:
  the reporter has declared `safe-pi --session <id>` as the pane's self-reported
  resume command, naming the session that was running rather than the newest
  one in the directory, and Herdr types it into the restored pane's shell in
  the saved working directory.
- Extensions and git-installed packages are read-only in the sandbox, but Pi's
  npm packages are not the host's: the sandbox keeps its own package tree, because packages with native
  parts carry one binding per platform and the host's tree holds only the
  host's (on macOS, `darwin` bindings a Linux sandbox cannot load). On every
  start the sandbox installs the tree from the host's `package.json` and
  `package-lock.json` with `npm ci`, when those changed or the image's Node ABI
  did; an unchanged start installs nothing and prints nothing. The first start
  after the change installs it, about seven seconds. If the install fails,
  `safe-pi` warns and starts with the tree it has (`--prepare` fails instead).
  Install a package on the host and the next start picks it up. `pi install`
  inside the sandbox works against the sandbox package tree and lasts only until
  that tree is next converged.
- Pi compiles its TypeScript extensions on first use and caches the compiled
  modules under `/tmp`, which the sandbox discards with the container. `safe-pi`
  therefore binds a persistent directory there — the sandbox's own, not the one
  the host Pi uses, because a cache entry is a module the host would execute. An
  extension you install on the host is the only thing compiled on the next
  start.
- The sandbox is a filesystem boundary, not a credential boundary: it can read
  the credentials Pi uses.
- `safe-pi` runs under your host locale. The image ships `en_US.UTF-8`, and a
  host forwarding a locale the image does not ship — or one without a UTF-8
  codeset, like `C` — gets glibc's `C.UTF-8` instead of a silent POSIX fallback,
  so tools and the Erlang VM are always UTF-8. Another locale means regenerating
  it in the image.
- Herdr's native `agent_session` reference is stored only for official
  `herdr:*` sources — by design, not by version — so the sandbox reporter
  declares its own resume command, which Herdr has accepted from a custom
  source since 0.9.2. If no report reaches Herdr before a restart, the pane
  returns as a plain shell and `safe-pi -c` resumes it by hand.
- A warning that the image's Pi differs from the host's Pi is expected until you
  run `safe-pi --update`.

### Where things live

- Image: `safe-pi:current-u<uid>`, plus one tag per baked Pi version.
- Toolchain volume: `safe-pi-toolchain-u<uid>`.
- Extension transpile cache: `~/.cache/safe-pi/jiti` on the host, mounted at
  `/tmp/jiti` inside the sandbox.
- Sandbox package tree: `~/.cache/safe-pi/npm` on the host, mounted at
  `~/.pi/agent/npm` inside the sandbox. The host's own `~/.pi/agent/npm` is not
  reachable from the sandbox; only its `package.json` and `package-lock.json`
  are mounted, read-only.
- Starting over: remove the volume to reinstall the declared environment, remove
  the image tags to rebuild the image; the next run recreates what is missing.
  Removing the transpile cache costs one recompilation and nothing else.
  Removing the sandbox package tree costs one reinstall (about seven seconds).

### Troubleshooting

| Symptom | Cause |
| --- | --- |
| Docker not found, or the daemon refuses to answer | Docker is not installed or not reachable by your user |
| Refuses to run | You are root; file-ownership parity needs your own uid |
| Cannot find the build context | The script was copied instead of installed by stow; point the override at the Dockerfile |
| The first run is slower than described above | The image build or the convergence is running; it reports which one |
| A start is about ten seconds slower than usual | The extension transpile cache is cold: the first run after it was removed, or after extensions changed |
| A start installs the Pi packages | The host's package lock, or the image's Node ABI, changed since the sandbox package tree was last installed |
| `package tree convergence failed at 'npm ci --legacy-peer-deps'` | The install failed (usually the network); the sandbox started with whatever the tree held, and the next start retries |
| Pi fails with a Node engine error | The declared Node version does not satisfy Pi's requirement; adjust the declaration |
| `safe-pi on macOS supports Colima only` | The Docker daemon is not a Colima one (Docker Desktop, OrbStack, plain Lima); start Colima and point the Docker context at it |
| `SSH agent unavailable in the sandbox: ...` (macOS) | The relay to the Colima VM could not be opened or forwarded; the sandbox started without the agent. Check `colima status` and that `~/.colima/ssh_config` exists |
| Herdr shows the pane as a plain terminal | You are not running inside a Herdr pane, or Herdr's socket is not reachable from the container, so the sandbox reporter cannot attribute the pane |
| A restored pane comes back as a plain shell | No report reached Herdr before the restart, so the pane has no stored resume command; run `safe-pi -c` |
| Dangerous commands run without a prompt | Expected inside the sandbox: the `permission-gate` extension registers nothing there, because the container is the boundary |
| Warning about differing Pi versions | The image's Pi is older than the host's; run `safe-pi --update` |
| `setlocale: LC_ALL: cannot change locale (...)` on every start | Your shell exports an `LC_ALL` the image does not ship; the sandbox runs `C.UTF-8` instead, and the notice comes from the shell that reads the locale before the sandbox can replace it |

## Use a second GitHub Copilot account (`pi-deere`)

`pi-deere` runs Pi with a second profile whose GitHub Copilot login is separate
from `pi`. Use it to spend the franchise of a second subscription. `stow pi`
installs it at `~/.local/bin/pi-deere`, next to `pi` and `safe-pi`. `pi` keeps
its logins and behaviour; `pi-deere` is the only command that uses the second
account. You choose the account by the command you start: there is no switching
inside one running instance and no balancing between accounts.

### What is shared and what is private

- **Private** (`~/.pi-deere/agent`): `auth.json`, so the second account's
  login never touches the original's. Nothing is copied from `~/.pi/agent`
  except the shared resources below, and no other provider is logged in. Trust
  decisions and run history are also private.
- **Shared** (symlinks into `~/.pi/agent`, which stays the maintained source):
  `extensions/`, `skills/`, `prompts/`, `themes/`, `agents/`, `tools/`, `bin/`,
  `npm/` and `git/` (installed packages and their dependencies), `AGENTS.md`,
  `keybindings.json`, `models.json`, `models-store.json`, `mcp-adapter.json`,
  and `sessions/`. Edit these in the original; the next run of either command
  uses the change.
- **Preferences** (`settings.json`) are copied from the original on every
  launch, never linked. Pi writes model and thinking choices into its settings
  file, and a link would carry them into `~/.pi/agent`. Changes made inside
  `pi-deere` therefore last for that run; to change a shared preference, edit
  the original `settings.json`.
- **Sessions** are the same store as `pi`, with the native layout grouped by
  project. Sessions are not copied or migrated.
- **New conversations** start on GitHub Copilot. `pi-deere` passes
  `--models github-copilot/*` unless you pass `--models` yourself, so the
  original default provider in `settings.json` is not changed.
- **Environment**: `COPILOT_GITHUB_TOKEN` is removed for `pi-deere`, so a
  token inherited from the shell never becomes the second account.

### First login (a manual step)

1. Run `pi-deere`. If the second profile has no Copilot login, it prints
   `GitHub Copilot is not logged in for this profile` and still opens Pi.
2. Inside Pi, run `/login`, choose GitHub Copilot, and sign in with the
   second GitHub account.
3. Confirm the profile: `PI_CODING_AGENT_DIR=~/.pi-deere/agent pi auth check --provider github-copilot`
   prints `"status":"ready"`.

Pi's subcommands work through `pi-deere` too (`pi-deere update`, `install`,
`remove`, `list`, `auth`). They act on the shared `npm/` installation, so a
package installed or updated there also changes what `pi` loads: that is the
point of one installation.

The login is stored once in the profile; later runs reuse it. Logging out or
replacing the login in one profile does not change the other.

### Switch accounts in a conversation

A session must have one writer at a time. To continue a conversation with the
other account:

1. Exit the running instance (`/quit`, or Ctrl+C) so it stops writing.
2. Open the same session with the other command:
   - `pi-deere --session <id-or-path>` for the exact session (a unique id prefix
     also works);
   - `pi-deere --resume` for Pi's session picker;
   - `pi --session <id-or-path>` to return to the original account.
3. Messages added in either profile appear in the other when you reopen the
   session there.

Two instances can run at the same time only when they use different sessions.
No lock coordinates two instances on the same session; keep that rule yourself.

An unknown reference fails with `No session found matching '<ref>'` and creates
nothing. `pi-deere` does not use `--session-id`, which creates a missing session.

### Recover from a conflict

If the profile has a file or link that is not the shared one, `pi-deere` stops
before changing anything and prints `conflict: <path> ...`. Move that path aside
(for example a `models-store.json` Pi wrote before the link existed), then run
`pi-deere` again. Removing a file you do not recognise is never automatic. If the
original agent directory is missing, set `PI_CODING_AGENT_DIR` to it.

### Limits

- Separate accounts are a selection and persistence boundary, not a security
  sandbox: shared extensions run with your user permissions.
- When a resumed session used a model the second profile cannot use, Pi falls
  back to a Copilot model and shows a warning in the interactive UI. Choose the
  model you want with `/model`.
- Model or thinking changes you make in `pi-deere` are written to the profile's
  `settings.json` copy and do not reach `pi`. The copy is regenerated on the next
  launch, so those choices are not kept as preferences.
- Pi reads `COPILOT_GITHUB_TOKEN` for GitHub Copilot and no other token variable,
  so that is the only inherited credential removed for `pi-deere`.
- Only GitHub Copilot is logged in for the second profile. Use `pi` for other
  providers.

### Verify

- `bash tests/pi-deere-test.sh` checks the launcher's contract with a stubbed `pi`.
- `bash tests/pi-deere-real-pi-profile-test.sh`,
  `-sessions-test.sh` and `-defaults-test.sh` run the real `pi` offline, with
  fake credentials: shared resources, the Copilot default, exact session resume,
  the two-way session round trip, and credential isolation. Each is its own gate
  unit, and all three share `tests/lib/pi-deere-real-pi-harness.sh`.
- Both run in `tests/run` and `tests/run --full`.

A smoke test with the two real accounts is a manual step and is not automated:
it needs your GitHub logins, and this repository never stores tokens.

## For `Omarchy`

`stow general git hypr nvim tasks tmux zsh pi pi-linux skills-personal`

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

## For `Herdr`

`stow herdr` links the Herdr configuration, its helper scripts, and the
`herdr-recent-navigator` plugin settings. Runtime files are not tracked:
`~/.config/herdr/.plugins.lock` and
`~/.local/share/herdr-recent-navigator/herdr-plugin.toml` are regenerated by
Herdr and by the plugin installer, so tracking them only produced Stow
conflicts on every upgrade. The package-local `herdr/.stow-local-ignore` also
leaves Herdr's other runtime state out of Stow, including logs, session data,
and the live socket symlink; this keeps `stow herdr` safe while Herdr is
running.

A sandboxed Pi started with `safe-pi` keeps reporting state to Herdr through a
sandbox reporter instead of Herdr's own Pi integration. See
[Run Pi in the sandbox](#run-pi-in-the-sandbox-safe-pi) for the mounts, the
recipes, and how a server restart restores the sandboxed pane.

The navigator bindings live in
`~/.config/herdr/plugins/config/beyondlex.herdr-recent-navigator/config.toml`
(`Ctrl+K` up, `Ctrl+J` down). It is tracked, so edit the repo copy — never the
`$HOME` one.

Reinstalling the plugin seeds a template into that path when the file is
missing. If the link is ever replaced by a regular file, restore it with:

```sh
rm ~/.config/herdr/plugins/config/beyondlex.herdr-recent-navigator/config.toml
stow herdr
```

The package contract is covered by `bash tests/herdr-stow-package-test.sh`.

## For MacOS

`stow aerospace general ghostty git nvim tasks tmux zsh pi pi-mac skills-corporate`
