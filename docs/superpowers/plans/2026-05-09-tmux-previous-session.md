# Tmux Previous Session Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `C-a C-s` keybinding to toggle back to the previous tmux session.

**Architecture:** One-line addition to `tmux.conf.local` using tmux's built-in `switch-client -l` command, bound to prefix map.

**Tech Stack:** tmux, Oh My Tmux! framework

---

### Task 1: Add `switch-client -l` keybinding

**Files:**
- Modify: `tmux/.config/tmux/tmux.conf.local:553` (end of file)

- [ ] **Step 1: Add the binding**

Edit `tmux/.config/tmux/tmux.conf.local` and append at the end of file:

```tmux
bind-key -T prefix C-s switch-client -l
```

- [ ] **Step 2: Verify syntax**

Run: `tmux source-file ~/.config/tmux/tmux.conf.local`
Expected: no output (success). If errors appear, check the line.

- [ ] **Step 3: Commit**

```bash
git add tmux/.config/tmux/tmux.conf.local
git commit -m "feat: add C-a C-s to toggle previous session"
```
