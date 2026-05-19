# Pi Settings Platform Split Design

**Date:** 2026-05-19  
**Status:** Approved design; awaiting written spec review  
**Scope:** Split only Pi's `settings.json` into macOS and Linux-specific Stow packages while keeping shared Pi configuration in the existing `pi` package.

---

## Problem Statement

The dotfiles repo currently stores Pi configuration under the shared `pi` Stow package. That package includes `pi/.pi/agent/settings.json`, but this file should differ between this macOS machine and the user's Linux machine.

Because the repo uses GNU Stow-style top-level package directories, the cleanest solution is to keep common Pi assets in `pi` and move only the platform-specific `settings.json` into separate Stow packages.

---

## Goals

- Keep Pi extensions, prompts, agents, keybindings, and web-search configuration shared in `pi`.
- Move Pi's `settings.json` out of the shared `pi` package.
- Add a `pi-mac` package that owns the macOS `~/.pi/agent/settings.json`.
- Add a `pi-linux` package that owns the Linux `~/.pi/agent/settings.json`.
- Update README Stow commands so each platform stows `pi` plus exactly one platform-specific Pi settings package.

---

## Non-Goals

- Do not duplicate the full Pi package for each platform.
- Do not introduce scripts to generate or copy settings files.
- Do not change Pi extensions, prompts, agents, keybindings, or web-search configuration.
- Do not resolve unrelated local changes outside this settings split.

---

## Proposed Structure

```text
pi/
  .pi/
    agent/
      agents/
      extensions/
      keybindings.json
    prompts/
    web-search.json

pi-mac/
  .pi/
    agent/
      settings.json

pi-linux/
  .pi/
    agent/
      settings.json
```

The shared `pi` package remains the owner of reusable Pi assets. The new platform packages own only the platform-specific `settings.json` file.

---

## Initial File Contents

### `pi-mac/.pi/agent/settings.json`

Seed from the current local working tree version of:

```text
pi/.pi/agent/settings.json
```

This captures the macOS-specific settings currently present on this machine.

### `pi-linux/.pi/agent/settings.json`

Seed from the currently committed git version of:

```text
pi/.pi/agent/settings.json
```

This preserves the Linux/default settings as they existed before the current local macOS edits.

---

## Stow Usage

Update `README.md` to include platform-specific Pi packages.

### Linux / Omarchy

```bash
stow general git hypr nvim tasks tmux zsh pi pi-linux
```

### macOS

```bash
stow aerospace general ghostty git nvim tasks tmux zsh pi pi-mac
```

The important rule is that `pi` should always be paired with exactly one of:

- `pi-mac`
- `pi-linux`

---

## Migration Behavior

The implementation should:

1. create `pi-mac/.pi/agent/settings.json` from the local working copy
2. create `pi-linux/.pi/agent/settings.json` from the committed version
3. remove `pi/.pi/agent/settings.json` from the shared package
4. update README platform Stow commands

After this change, existing symlinks may need to be restowed manually on each machine. The repo structure itself should not include a script for this.

---

## Validation

Validate with:

- `git status --short` to confirm only intended files changed
- `git show HEAD:pi/.pi/agent/settings.json` or equivalent while implementing to seed Linux settings correctly
- `diff`/`cmp` checks confirming:
  - `pi-mac/.pi/agent/settings.json` matches the pre-move local file
  - `pi-linux/.pi/agent/settings.json` matches the committed version
- optional dry-run Stow commands if available:
  - `stow -n -v pi pi-mac`
  - `stow -n -v pi pi-linux`

---

## Success Criteria

- The shared `pi` package no longer contains `.pi/agent/settings.json`.
- `pi-mac` contains only `.pi/agent/settings.json` for macOS.
- `pi-linux` contains only `.pi/agent/settings.json` for Linux.
- README documents the new platform-specific Stow commands.
- Shared Pi assets remain in `pi` and are not duplicated.
