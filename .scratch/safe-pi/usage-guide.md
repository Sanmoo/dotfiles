# safe-pi usage guide (draft)

Planning artifact. When the command exists, this text becomes a `## safe-pi`
section of the repository README (following its style); the draft is then
deleted. Nothing here is implemented yet.

---

## safe-pi

Run Pi in a throwaway Docker container that sees the repository you are in, your
Pi configuration and credentials, and a toolchain installed inside the container
from this repository's declared mise configuration — and nothing else in your
home directory.

### First run

```sh
cd ~/dev/github.com/you/some-repo
safe-pi
```

The first run builds the image (about a minute) and installs the declared
toolchain into its volume (several minutes; once per machine). Later runs start
in about a second.

### Everyday recipes

| What you want | Command |
| --- | --- |
| Continue the last conversation in this directory | `safe-pi -c` |
| Resume a specific session | `safe-pi --session <id-or-path>` |
| A one-shot prompt | `safe-pi -p "explain this file"` |
| A specific model | `safe-pi --model opencode-go/deepseek-v4-flash` |
| Skip the lens analyzers for this session | `safe-pi --no-lens` |
| A shell inside the sandbox | `safe-pi --shell` |
| Install the declared toolchain and exit | `safe-pi --prepare` |
| Refresh Pi inside the image to the latest release | `safe-pi --update` |
| Anything else Pi accepts | `safe-pi <any pi flag>` |

### safe-pi's own flags

| Flag | Effect |
| --- | --- |
| `--prepare` | converge the declared toolchain into the volume, do not start Pi |
| `--update` | rebuild the image with the latest Pi release |
| `--rebuild` | rebuild the image with the version it already has |
| `--shell` | start a shell instead of Pi, with the same mounts |
| `--dry-run` | print the Docker command and exit |
| `help` | safe-pi's own usage |

`-h`, `--help`, and `--version` are passed to Pi, not consumed by `safe-pi`.

### What the sandbox sees

- Your repository, read-write, at the same absolute path — writes land on the host.
- Your Pi configuration, credentials, sessions, skills, prompts, agents,
  extensions, and packages, shared with the host Pi. Extensions and packages are
  read-only inside the sandbox.
- Herdr's socket, so the pane still reports `working`, `blocked`, and `idle`.
- A toolchain installed inside the container from the declared mise
  configuration, kept in a named volume.
- Not your host toolchain, not other repositories, not the rest of your home
  directory, not the Docker socket.

### Things worth knowing

- The toolchain is converged on every start from the declared configuration, so
  `latest` pins follow new releases the way they do on the host. If the network
  is unavailable, `safe-pi` warns and opens Pi anyway; `--prepare` reports the
  failure instead.
- A repository's own `.mise.toml` pins are installed on first use and stay in the
  toolchain volume, so switching repositories does not re-download them.
- After a Herdr server restart, a sandboxed pane comes back as a plain shell on
  purpose: Herdr's automatic resume would otherwise start an unsandboxed Pi.
  Re-enter the conversation with `safe-pi -c`.
- `pi install` inside the sandbox fails on purpose, because extensions and
  packages are read-only. Install on the host; the sandbox picks it up
  immediately.
- The sandbox is a filesystem boundary, not a credential boundary: it can read
  the credentials Pi uses.
- A warning that the image's Pi differs from the host's Pi is expected until you
  run `safe-pi --update`.

### Where things live

- Image: `safe-pi:current-u<uid>`, plus one tag per baked Pi version.
- Toolchain volume: `safe-pi-mise`.
- Starting over: remove the volume to reinstall the toolchain, remove the image
  tags to rebuild the image; the next run recreates what is missing.

### Troubleshooting

| Symptom | Cause |
| --- | --- |
| Docker not found, or the daemon refuses to answer | Docker is not installed or not reachable by your user |
| Refuses to run | You are root; file-ownership parity needs your own uid |
| Cannot find the build context | The script was copied instead of installed by stow; point the override at the Dockerfile |
| The first run takes minutes | The image build or the toolchain convergence is running; it reports which one |
| Pi fails with a Node engine error | The declared Node version does not satisfy Pi's requirement; adjust the declaration |
| Herdr shows the pane as a plain terminal | Herdr's socket is not reachable from the container, or the integration extension is missing |
| Blocked prompts never appear in Herdr | The approval extension is missing from the mounted configuration |
| Warning about differing Pi versions | The image's Pi is older than the host's; run `safe-pi --update` |
