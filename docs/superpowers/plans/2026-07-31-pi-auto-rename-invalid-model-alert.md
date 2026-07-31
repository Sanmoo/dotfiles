# pi-auto-rename Invalid Model Alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `pi-auto-rename` show an immediate, prominent configuration error when its configured model is absent from Pi's model registry.

**Architecture:** Keep model configuration and registry lookup in `index.ts`. Add a small pure message formatter in `utils.ts` so exact error copy is unit-testable without starting Pi. Derive a user-facing `~` config path from the existing absolute `CONFIG_PATH`, avoiding duplicated path definitions. Validate registry presence during session startup before automatic naming; invalid configuration blocks automatic model calls while leaving `/rename model`, `/rename reset`, and other commands available.

**Tech Stack:** TypeScript, Bun test, Pi Extension API, `@earendil-works/pi-ai`, `@earendil-works/pi-coding-agent`.

## Global Constraints

- Error notification level must be `error`.
- Error must include configured `provider/model` and `~/.pi/agent/extensions/pi-auto-rename.json`.
- Missing model must not trigger a generation request or automatic rename attempt.
- Valid-model behavior and existing tests must remain unchanged.
- Use TDD: observe each new test fail before implementation.

---

### Task 1: Add failing coverage for invalid-model error copy

**Files:**

- Modify: `pi/tests/pi-agent/pi-auto-rename.test.ts`
- Modify: `pi/.pi/agent/extensions/pi-auto-rename/utils.ts`

**Interfaces:**

- Produce exported `formatInvalidModelMessage(provider: string, id: string, configPath: string): string` returning the complete two-line error message.

- [ ] **Step 1: Write the failing test**

Add this import and test to `pi/tests/pi-agent/pi-auto-rename.test.ts`:

```ts
import {
 formatInvalidModelMessage,
 sanitizeSessionName,
} from "../../.pi/agent/extensions/pi-auto-rename/utils";
```

Replace the existing single-name import with the grouped import above, then add:

```ts
describe("invalid model configuration message", () => {
 it("identifies model and config file to fix", () => {
  const message = formatInvalidModelMessage(
   "github-copilot",
   "gpt-4.1",
   "~/.pi/agent/extensions/pi-auto-rename.json",
  );

  expect(message).toBe(
   "pi-auto-rename: modelo inválido: github-copilot/gpt-4.1.\n" +
    "Corrija: ~/.pi/agent/extensions/pi-auto-rename.json",
  );
 });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bun test pi/tests/pi-agent/pi-auto-rename.test.ts
```

Expected: FAIL because `formatInvalidModelMessage` is not exported or defined yet.

- [ ] **Step 3: Implement the pure formatter**

Add to `pi/.pi/agent/extensions/pi-auto-rename/utils.ts`:

```ts
export function formatInvalidModelMessage(
 provider: string,
 id: string,
 configPath: string,
): string {
 return (
  `pi-auto-rename: modelo inválido: ${provider}/${id}.\n` +
  `Corrija: ${configPath}`
 );
}
```

- [ ] **Step 4: Run focused test to verify it passes**

Run:

```bash
bun test pi/tests/pi-agent/pi-auto-rename.test.ts
```

Expected: all tests pass, including `invalid model configuration message > identifies model and config file to fix`.

- [ ] **Step 5: Commit the tested formatter**

```bash
git add pi/.pi/agent/extensions/pi-auto-rename/utils.ts pi/tests/pi-agent/pi-auto-rename.test.ts
git commit -m "test: cover invalid rename model message"
```

### Task 2: Validate configured model at session startup

**Files:**

- Modify: `pi/.pi/agent/extensions/pi-auto-rename/index.ts`
- Modify: `pi/tests/pi-agent/pi-auto-rename.test.ts`

**Interfaces:**

- Consume `formatInvalidModelMessage` from `utils.ts`.
- Use existing `ctx.modelRegistry.find(provider, id)` lookup.
- Preserve existing `resolveAuth` behavior for manual generation and authentication errors.

- [ ] **Step 1: Add source-level regression assertions**

Add this test to `pi/tests/pi-agent/pi-auto-rename.test.ts`:

```ts
describe("invalid model startup handling", () => {
 it("formats and reports invalid config before auto naming", () => {
  expect(extensionSource).toContain("formatInvalidModelMessage");
  expect(extensionSource).toContain('notify(ctx, message, "error")');
  expect(extensionSource).toContain(
   '"~/.pi/agent/extensions/pi-auto-rename.json"',
  );
  expect(extensionSource).toContain("function validateConfiguredModel");
  expect(extensionSource).toContain("return false;");
 });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bun test pi/tests/pi-agent/pi-auto-rename.test.ts
```

Expected: FAIL because startup validation, error-level notification, and early return do not exist in `index.ts`.

- [ ] **Step 3: Import formatter and add validation helper**

Extend the `./utils.ts` import in `index.ts` with `formatInvalidModelMessage`.

Add this display-path constant after `CONFIG_PATH`:

```ts
const CONFIG_DISPLAY_PATH = CONFIG_PATH.replace(homedir(), "~");
```

Add this helper after `notify`:

```ts
function validateConfiguredModel(ctx: ExtensionContext, ref: ModelRef): boolean {
 if (ctx.modelRegistry.find(ref.provider, ref.id)) return true;

 const message = formatInvalidModelMessage(
  ref.provider,
  ref.id,
  CONFIG_DISPLAY_PATH,
 );
 notify(ctx, message, "error");
 return false;
}
```

- [ ] **Step 4: Block automatic naming when model is missing**

At the start of `autoName`, before reading the first user message or setting `namingAttempted`, add:

```ts
if (!validateConfiguredModel(ctx, modelRef)) return;
```

Update `session_start` so validation happens immediately on startup, before `autoName`:

```ts
pi.on("session_start", async (event, ctx) => {
 onSessionEvent(event, ctx);
 validateConfiguredModel(ctx, modelRef);
 await autoName(ctx);
});
```

To avoid duplicate startup notifications from the validation in `autoName`, make the helper stateful within the extension instance:

```ts
let invalidModelNotified = false;
```

Reset it inside `resetNaming`:

```ts
invalidModelNotified = false;
```

Then guard notification in `validateConfiguredModel`:

```ts
if (ctx.modelRegistry.find(ref.provider, ref.id)) {
 invalidModelNotified = false;
 return true;
}
if (!invalidModelNotified) {
 const message = formatInvalidModelMessage(
  ref.provider,
  ref.id,
  CONFIG_DISPLAY_PATH,
 );
 notify(ctx, message, "error");
 invalidModelNotified = true;
}
return false;
```

This emits one visible error per session/configuration state, while repeated `message_end` and `agent_end` callbacks remain quiet. `/rename model ...` and `/rename reset` continue to work; a subsequent automatic naming callback revalidates the new model.

- [ ] **Step 5: Run focused tests**

Run:

```bash
bun test pi/tests/pi-agent/pi-auto-rename.test.ts
```

Expected: all tests pass.

- [ ] **Step 6: Run TypeScript diagnostics**

Run the Pi LSP diagnostics for:

```text
pi/.pi/agent/extensions/pi-auto-rename/index.ts
pi/.pi/agent/extensions/pi-auto-rename/utils.ts
pi/tests/pi-agent/pi-auto-rename.test.ts
```

Expected: no TypeScript errors.

- [ ] **Step 7: Commit implementation**

```bash
git add pi/.pi/agent/extensions/pi-auto-rename/index.ts pi/.pi/agent/extensions/pi-auto-rename/utils.ts pi/tests/pi-agent/pi-auto-rename.test.ts
git commit -m "feat: alert on invalid auto-rename model"
```

### Task 3: Verify complete behavior

**Files:**

- Verify: `pi/.pi/agent/extensions/pi-auto-rename/index.ts`
- Verify: `pi/.pi/agent/extensions/pi-auto-rename/utils.ts`
- Verify: `pi/tests/pi-agent/pi-auto-rename.test.ts`

- [ ] **Step 1: Run the complete extension test**

```bash
bun test pi/tests/pi-agent/pi-auto-rename.test.ts
```

Expected: zero failures.

- [ ] **Step 2: Verify active model config remains valid**

```bash
python3 -m json.tool "$HOME/.pi/agent/extensions/pi-auto-rename.json"
pi --list-models | grep -F 'bifrost         bedrock/openai.gpt-5.6-terra'
```

Expected: valid JSON and matching model catalog entry.

- [ ] **Step 3: Inspect final diff and diagnostics**

```bash
git diff HEAD~1 -- pi/.pi/agent/extensions/pi-auto-rename pi/tests/pi-agent/pi-auto-rename.test.ts
git status --short
```

Expected: only intended extension/test changes; no unexpected generated files.
