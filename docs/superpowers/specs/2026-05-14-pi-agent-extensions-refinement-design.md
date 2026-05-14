# Pi Agent Extensions Refinement

**Date:** 2026-05-14
**Status:** Design Approved

## Problem

Two pi coding agent extensions are causing unwanted friction:

1. **protected-paths.ts** — Blocks write/edit operations on files the user wants to modify freely (`.env`, `.ssh/`, `.config/`, `Dockerfile`, etc.)
2. **permission-gate.ts** — The `/dev/` redirect regex is too broad: `2>/dev/null`, `>/dev/null`, and `>/dev/stdout` trigger a false positive because the pattern `/\b>\s*\/dev\//i` matches any redirect to `/dev/*`, including harmless pseudo-devices like `/dev/null`.

## Scope

Two independent changes to the pi agent extension files in `Sanmoo/dotfiles`:

1. Remove `protected-paths.ts` (source + symlink) entirely
2. Refine the `/dev/` regex in `permission-gate.ts` to only match block storage devices

---

## Part 1: Remove protected-paths.ts

### Motivation

The user wants full write/edit access to all files in their workspace, including configuration files, environment files, and system files. The protection list is too broad for their workflow.

### Changes

| File | Action |
|---|---|
| `~/dev/github.com/Sanmoo/dotfiles/pi/.pi/agent/extensions/protected-paths.ts` | Delete |
| `~/.pi/agent/extensions/protected-paths.ts` (symlink → source above) | Delete |

### Risks

- **None.** The user explicitly wants this freedom and is aware of the implications.

---

## Part 2: Refine /dev/ redirect regex in permission-gate.ts

### Motivation

The current regex `/\b>\s*\/dev\//i` incorrectly matches harmless redirects to pseudo-devices:
- `2>/dev/null` (stderr suppression)
- `>/dev/null` (stdout suppression)
- `> /dev/stdout` / `> /dev/stderr`

These are used constantly in shell commands and should never trigger a confirmation prompt.

### Change

Replace the single overly-broad regex pattern with a targeted one that only matches writes to block storage devices.

**Before:**
```javascript
/\b>\s*\/dev\//i
```

**After:**
```javascript
/\b>\s*\/dev\/(sd[a-z]|nvme[0-9]|vd[a-z]|mmcblk[0-9]|loop[0-9]|sr[0-9]|disk\/)/i
```

### Matches (correctly blocked)

| Command | Reason |
|---|---|
| `echo foo > /dev/sda` | SCSI/SATA disk |
| `echo foo > /dev/sda1` | SCSI/SATA partition |
| `echo foo > /dev/nvme0n1` | NVMe disk |
| `echo foo > /dev/nvme0n1p1` | NVMe partition |
| `echo foo > /dev/vda` | VirtIO disk |
| `echo foo > /dev/mmcblk0` | SD/MMC card |
| `echo foo > /dev/loop0` | Loop device |
| `echo foo > /dev/sr0` | Optical drive |
| `cat image > /dev/disk/by-id/ata-disk` | Disk-by-id path |

### Non-matches (passes through)

| Command | Reason |
|---|---|
| `git diff 2>/dev/null` | Stderr redirect to null — harmless |
| `ls >/dev/null` | Stdout redirect to null — harmless |
| `make > /dev/stdout` | Redirect to stdout — harmless |
| `echo error > /dev/stderr` | Redirect to stderr — harmless |
| `cmd > /dev/tty` | Redirect to terminal — harmless |

### Everything Else Unchanged

All other dangerous patterns (`sudo`, `rm -rf`, `chmod 777`, `dd`, `mkfs.*`, `fdisk`, `parted`, `curl|bash`, `wget|bash`, `chattr`, `> /etc/*`) remain exactly as they are.

---

## Files to Modify

1. Delete: `/home/sanmoo/dev/github.com/Sanmoo/dotfiles/pi/.pi/agent/extensions/protected-paths.ts`
2. Delete: `/home/sanmoo/.pi/agent/extensions/protected-paths.ts`
3. Edit: `/home/sanmoo/dev/github.com/Sanmoo/dotfiles/pi/.pi/agent/extensions/permission-gate.ts` — replace the `/dev/` regex pattern

## Verification

After changes:
- `git diff 2>/dev/null` should execute without confirmation
- `echo foo > /dev/sda` should still trigger confirmation
- `protected-paths.ts` should no longer exist in `~/.pi/agent/extensions/`
- Editing `.env` files should work without blockage
