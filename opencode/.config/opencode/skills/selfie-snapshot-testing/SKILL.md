---
name: selfie-snapshot-testing
description: Write and maintain Selfie snapshot tests for JVM projects (Java/Kotlin) with JUnit 5. Use when creating snapshot tests, updating snapshots, using toMatchDisk or toBe, fixing Selfie assertion failures, or when user says "snapshot test", "selfie", "toMatchDisk", "_TODO snapshot", "update snapshot", or "snapshot mismatch". Do NOT use for non-snapshot unit tests, integration test setup, or test framework configuration unrelated to Selfie.
metadata:
  author: Samuel Santos
  version: 1.0.0
---

# Selfie Snapshot Testing for JVM

Guide the agent through creating and maintaining snapshot tests using the Selfie library (by DiffPlug) in JVM projects with JUnit 5. Selfie rewrites your test source code automatically -- never create or edit `.ss` snapshot files by hand.

## Critical Rules

These rules exist because violating them wastes significant time. They are non-negotiable.

1. **NEVER create or edit `.ss` files manually.** Selfie generates and manages them. If you need a new snapshot, use `_TODO` variants. If you need to update one, use `_TODO`, `//selfieonce`, or `//SELFIEWRITE`.
2. **NEVER assume a Gradle plugin is needed.** Selfie works with only the `selfie-runner-junit5` dependency. There is no `com.diffplug.selfie` Gradle plugin. Do not search for one, suggest adding one, or troubleshoot its absence.
3. **NEVER put `_TODO` in test method names.** The `_TODO` suffix is part of the Selfie API method calls (`toMatchDisk_TODO()`, `toBe_TODO()`), not the test method name. Selfie rewrites the method call in source code; it does not touch method names.

## How Selfie Works

Selfie has three modes controlled by the `selfie` or `SELFIE` environment variable or system property:

| Mode | When active | Behavior |
|---|---|---|
| `interactive` | Default (local dev) | `_TODO` calls write snapshots and rewrite your source to remove `_TODO`. Non-`_TODO` calls assert normally. |
| `readonly` | Default when `CI=true` | No snapshots written. Build fails if `_TODO`, `//selfieonce`, or `//SELFIEWRITE` are present in source. |
| `overwrite` | When `selfie=overwrite` | Every snapshot is rewritten, regardless of `_TODO`. |

You almost never need to set the mode explicitly. The defaults handle it.

### Snapshot rewrite mechanism

When you run a test containing `toMatchDisk_TODO()`:

1. Selfie captures the actual value
2. Writes it to the `.ss` file (creating the file if needed)
3. Rewrites `toMatchDisk_TODO()` to `toMatchDisk()` in your Java/Kotlin source file
4. The test passes

This means after running the test, your source file has been modified on disk. This is expected and correct behavior.

## Workflow 1: Create a New Snapshot Test

### Step 1: Write the test with `_TODO`

Write the test assertion using the `_TODO` variant:

```java
// Disk snapshot (stored in .ss file alongside the test class)
Selfie.expectSelfie(jsonResponse).toMatchDisk_TODO();

// Disk snapshot with a named key (for multiple snapshots in one test)
Selfie.expectSelfie(jsonResponse).toMatchDisk_TODO("descriptive-key");

// Inline literal snapshot (stored directly in source code)
Selfie.expectSelfie(someString).toBe_TODO();
```

### Step 2: Run the tests

Run the test suite normally (e.g., `./gradlew test`). Selfie will:

- Generate the `.ss` file with the snapshot content (for disk snapshots)
- Rewrite the source code to replace `_TODO` variants with their final form
- For `toBe_TODO()`, the actual value is written inline: `toBe("actual value")`

### Step 3: Verify

After running, check that:

- The `.ss` file was created (for disk snapshots)
- The `_TODO` was removed from your source code
- The test passes on a second run (without `_TODO`)

If the `.ss` file was NOT created and the `_TODO` was NOT removed, check:

- The test actually executed (wasn't skipped or filtered out)
- The test passed (Selfie only writes snapshots for passing tests)
- You're not running in `readonly` mode (check for `CI=true` environment variable)

## Workflow 2: Update an Existing Snapshot

When the output format changes and snapshots need updating, you have three options:

### Option A: Update a single snapshot

Change the specific assertion from `toMatchDisk()` back to `toMatchDisk_TODO()` (or `toBe()` to `toBe_TODO()`), then run the tests. Selfie rewrites the snapshot and removes `_TODO`.

### Option B: Update all snapshots in a file

Add the comment `//selfieonce` anywhere in the test file. Run the tests. Selfie updates every snapshot in the file and removes the `//selfieonce` comment automatically.

### Option C: Continuous rewrite mode

Add the comment `//SELFIEWRITE` anywhere in the test file. Every test run rewrites all snapshots. **You must remove `//SELFIEWRITE` manually when done** -- Selfie will not remove it for you. This is useful during active development when the output changes frequently.

**WARNING:** With `//SELFIEWRITE`, all tests always pass regardless of actual content. Do not forget to remove it, or CI will reject the build.

## Workflow 3: Fix Snapshot Failures in CI

If CI fails with a message like:

```
Snapshot mismatch
- update this snapshot by adding `_TODO` to the function name
- update all snapshots in this file by adding `//selfieonce` or `//SELFIEWRITE`
```

This means the actual output differs from the stored snapshot. To fix:

1. Run the failing test locally
2. Add `_TODO` to the failing assertion (or `//selfieonce` to the file)
3. Run the test -- Selfie updates the snapshot
4. Review the diff in the `.ss` file to confirm the change is intentional
5. Commit both the updated `.ss` file and the source file (with `_TODO` removed)

If CI fails because `_TODO`, `//selfieonce`, or `//SELFIEWRITE` are present in source:

- Someone forgot to run the tests locally before pushing
- Run the tests locally, let Selfie rewrite the source, then push again

## API Quick Reference

### Disk snapshots (stored in `.ss` files)

```java
Selfie.expectSelfie(string).toMatchDisk();           // assert against stored snapshot
Selfie.expectSelfie(string).toMatchDisk("key");      // assert with named key
Selfie.expectSelfie(string).toMatchDisk_TODO();      // generate/update snapshot
Selfie.expectSelfie(string).toMatchDisk_TODO("key"); // generate/update with named key
```

### Inline literal snapshots (stored in source code)

```java
Selfie.expectSelfie(string).toBe("expected");        // assert inline
Selfie.expectSelfie(string).toBe_TODO();             // generate inline value
Selfie.expectSelfie(string).toBe_TODO("ignored");    // argument is ignored, will be replaced

// Also works with primitives
Selfie.expectSelfie(10 / 4).toBe(2);
Selfie.expectSelfie(true).toBe(true);
```

### File-wide modifiers (add as a comment anywhere in the file)

```java
//selfieonce    // update all snapshots in this file, then remove this comment
//SELFIEWRITE   // continuously update all snapshots (must be removed manually)
```

## Project Setup

### Required dependency (Gradle Kotlin DSL)

```kotlin
dependencies {
    testImplementation("com.diffplug.selfie:selfie-runner-junit5:$selfieVersion")
}
```

That is the only required dependency. No plugin. No agent. No additional configuration.

### Optional: enable `overwrite` mode via Gradle property

To allow `./gradlew test -Pselfie=overwrite` to work, add to the test task:

```kotlin
tasks.withType<Test>().configureEach {
    environment(properties.filter { it.key == "selfie" })
}
```

### Optional: custom snapshot folder

By default, `.ss` files are created next to the test class. To customize, create a `SelfieSettings` class in the `selfie` package:

```java
package selfie;

import com.diffplug.selfie.junit5.SelfieSettingsAPI;

public class SelfieSettings extends SelfieSettingsAPI {
    @Override
    public String getSnapshotFolderName() {
        return "snapshots"; // .ss files go in a snapshots/ subdirectory
    }
}
```

## Examples

### Example 1: Creating a new snapshot test for a REST controller

User says: "Add a snapshot test for the GET /customers endpoint"

Actions:

1. Write the test method with mock setup and perform the HTTP call
2. Assert with `Selfie.expectSelfie(responseBody).toMatchDisk_TODO("get-customer")`
3. Run `./gradlew test` (or the project's test command)
4. Verify that the `.ss` file was created with the captured response body
5. Verify that `toMatchDisk_TODO("get-customer")` was rewritten to `toMatchDisk("get-customer")` in the source

Result: A new test with a disk snapshot. The `.ss` file contains the JSON response. The source file has `toMatchDisk("get-customer")` (no `_TODO`). A second test run passes without changes.

### Example 2: Updating snapshots after a response format change

User says: "The customer response now includes a new field, update the snapshots"

Actions:

1. Add `//selfieonce` as a comment anywhere in the affected test file
2. Run the tests
3. Verify that all `.ss` entries for that file were updated with the new field
4. Verify that the `//selfieonce` comment was removed from the source automatically
5. Review the `.ss` diff to confirm the change is intentional

Result: All snapshots in the file are updated. The `//selfieonce` comment is gone. The diff clearly shows the new field added to each snapshot.

### Example 3: CI fails with "snapshot mismatch"

User says: "CI is failing with a Selfie snapshot mismatch, how do I fix it?"

Actions:

1. Identify the failing test from the CI log
2. Explain that CI runs in `readonly` mode and cannot update snapshots
3. Instruct the user to run the failing test locally
4. Add `_TODO` to the failing assertion, run the test, review the updated snapshot
5. Commit both the updated `.ss` file and the rewritten source file

Result: The user understands the CI/local workflow. Snapshots are updated locally, committed, and CI passes on the next push.

## Common Mistakes

### Mistake: Creating `.ss` files manually

**Symptom:** You write the `.ss` file by hand, copy-pasting expected output.

**Why it's wrong:** The snapshot content may not match what Selfie would produce (formatting, ordering, whitespace). The snapshot is also not validated against the actual output.

**Fix:** Always use `_TODO` to let Selfie generate the file.

### Mistake: Thinking a Gradle plugin is needed

**Symptom:** Build fails when adding `id("com.diffplug.selfie")` to plugins block.

**Why it's wrong:** No such plugin exists. Selfie works entirely through the JUnit 5 runner.

**Fix:** Remove the plugin declaration. Only the `testImplementation` dependency is needed.

### Mistake: Putting `_TODO` in the test method name

**Symptom:** Test method named `myTest_TODO()`, expecting Selfie to auto-generate something.

**Why it's wrong:** `_TODO` is a suffix on Selfie API methods (`toMatchDisk_TODO()`), not on test method names. Selfie does not inspect method names.

**Fix:** Use `_TODO` on the assertion call: `Selfie.expectSelfie(value).toMatchDisk_TODO()`.

### Mistake: Committing `//SELFIEWRITE` to version control

**Symptom:** CI fails because `//SELFIEWRITE` is present in test source.

**Why it's wrong:** `//SELFIEWRITE` makes all snapshots always pass. CI runs in `readonly` mode and rejects this as a safety measure.

**Fix:** Remove `//SELFIEWRITE` before committing. Use `//selfieonce` instead if you want a one-time update that auto-cleans.

### Mistake: Running tests in CI with `selfie=overwrite`

**Symptom:** CI never catches snapshot regressions.

**Why it's wrong:** `overwrite` mode rewrites all snapshots silently. Snapshot tests become no-ops.

**Fix:** Never set `selfie=overwrite` in CI. The default `readonly` mode (activated by `CI=true`) is correct.
