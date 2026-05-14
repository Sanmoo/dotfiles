# Pi Agent Extensions Refinement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the overly-restrictive protected-paths.ts extension and fix the false-positive /dev/ redirect regex in permission-gate.ts.

**Architecture:** Two independent changes to pi agent extension files in the user's dotfiles repo. No dependencies between tasks.

**Tech Stack:** TypeScript, pi-coding-agent ExtensionAPI, regex

---

### Task 1: Remove protected-paths.ts

**Files:**
- Delete: `pi/.pi/agent/extensions/protected-paths.ts`
- Delete: `/home/sanmoo/.pi/agent/extensions/protected-paths.ts` (symlink)

- [ ] **Step 1: Delete the source file**

```bash
rm ~/dev/github.com/Sanmoo/dotfiles/pi/.pi/agent/extensions/protected-paths.ts
```

- [ ] **Step 2: Delete the symlink**

```bash
rm ~/.pi/agent/extensions/protected-paths.ts
```

- [ ] **Step 3: Verify removals**

```bash
ls -la ~/.pi/agent/extensions/protected-paths.ts 2>&1 || echo "Symlink removed OK"
ls -la ~/dev/github.com/Sanmoo/dotfiles/pi/.pi/agent/extensions/protected-paths.ts 2>&1 || echo "Source removed OK"
```

Expected: both commands output `No such file or directory`.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/github.com/Sanmoo/dotfiles
git add pi/.pi/agent/extensions/protected-paths.ts
git rm --cached pi/.pi/agent/extensions/protected-paths.ts 2>/dev/null || true
git commit -m "feat: remove protected-paths extension

User wants full write/edit access to all files without restrictions."
```

---

### Task 2: Fix /dev/ redirect regex in permission-gate.ts

**Files:**
- Modify: `pi/.pi/agent/extensions/permission-gate.ts` (lines containing the `/dev/` regex)

- [ ] **Step 1: Replace the overly-broad /dev/ regex**

In `~/dev/github.com/Sanmoo/dotfiles/pi/.pi/agent/extensions/permission-gate.ts`, find the line:

```javascript
/\b>\s*\/dev\//i,
```

Replace it with:

```javascript
/\b>\s*\/dev\/(sd[a-z]|nvme[0-9]|vd[a-z]|mmcblk[0-9]|loop[0-9]|sr[0-9]|disk\/)/i,
```

- [ ] **Step 2: Verify the file is syntactically correct**

```bash
cd ~/dev/github.com/Sanmoo/dotfiles && node -e "
const fs = require('fs');
const code = fs.readFileSync('pi/.pi/agent/extensions/permission-gate.ts', 'utf8');
// Basic syntax check: find all dangerousPatterns entries
const lines = code.split('\n');
const devLine = lines.findIndex(l => l.includes('/dev/'));
console.log('Dev regex line:', lines[devLine]?.trim());
// Confirm no syntax errors by trying to parse as JS (strip types)
const stripped = code.replace(/: \w+/g, '').replace(/import.*/, '');
try {
  new Function(stripped);
  console.log('Syntax: OK');
} catch(e) {
  console.log('Syntax error:', e.message);
}
"
```

Expected: Shows the new regex line and "Syntax: OK".

- [ ] **Step 3: Test the regex against real-world commands**

```bash
cd ~/dev/github.com/Sanmoo/dotfiles && node -e "
const pattern = /\b>\s*\/dev\/(sd[a-z]|nvme[0-9]|vd[a-z]|mmcblk[0-9]|loop[0-9]|sr[0-9]|disk\/)/i;

const shouldBlock = [
  'echo foo > /dev/sda',
  'echo bar > /dev/nvme0n1',
  'cat img > /dev/sda1',
  'dd if=x > /dev/vda',
  'echo > /dev/mmcblk0',
  'mkfs > /dev/loop0',
  'write > /dev/sr0',
  'cp a > /dev/disk/by-id/ata-disk',
];

const shouldPass = [
  'git diff 2>/dev/null',
  'ls >/dev/null',
  'echo > /dev/stdout',
  'echo err > /dev/stderr',
  'cmd > /dev/tty',
  'make 2>&1 > /dev/null',
  'curl -s example.com > /dev/null',
];

console.log('=== SHOULD BLOCK ===');
shouldBlock.forEach(cmd => {
  const matched = pattern.test(cmd);
  console.log(matched ? '✓ BLOCKED' : '✗ MISSED', cmd);
});

console.log('\n=== SHOULD PASS ===');
shouldPass.forEach(cmd => {
  const matched = pattern.test(cmd);
  console.log(!matched ? '✓ PASSED' : '✗ BLOCKED', cmd);
});
"
```

Expected: All "SHOULD BLOCK" show ✓ BLOCKED, all "SHOULD PASS" show ✓ PASSED.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/github.com/Sanmoo/dotfiles
git add pi/.pi/agent/extensions/permission-gate.ts
git commit -m "fix: refine /dev/ redirect regex in permission-gate extension

Only match block storage devices (/dev/sda, /dev/nvme0n1, etc.)
instead of any /dev/ path (/dev/null, /dev/stdout, etc.)
Fixes false positives on common patterns like 2>/dev/null."
```
