---
name: arrow-to-ctx-params
description: "Migration guide for Arrow-kt: replacing Either/bind patterns with Kotlin context parameters (Raise<E>). USE FOR: planning migration from Either monad + bind() to context(Raise<E>) style, converting suspend functions returning Either to context-parameter-based functions. This targets Kotlin 2.4.0+, where context parameters are available as a preview feature. DO NOT USE FOR: writing new code on Kotlin 2.3.x (use arrow-effects skill instead)."
license: Apache-2.0
compatibility: opencode
metadata:
  target-kotlin: "2.4.0"
  current-kotlin: "2.3.0"
  current-arrow: "2.2.1.1"
  target-arrow: "2.2.3"
  required-kotlin-feature: context-parameters
  feature-status: preview
---

# Migration Guide: Arrow Either → Context Parameters

## Overview

Kotlin 2.4.0 introduces **context parameters**, which subsume the earlier experimental
_context receivers_ feature. This enables Arrow's `Raise<E>` to be passed implicitly,
eliminating the need for `either { }` blocks and `.bind()` calls in many cases.

This skill documents the migration path from the current codebase patterns
(Kotlin 2.3.0 + Arrow 2.2.1.1) to context-parameter style (targeting Kotlin 2.4.0+).

**Status:** Context parameters are in preview in Kotlin 2.4.0. Do NOT apply this
migration in production code yet. The content here is for planning and experimentation.

## Prerequisites

### Arrow Upgrade

Bump to the latest stable Arrow release (check https://github.com/arrow-kt/arrow/releases
for the most recent version). As of this writing, **2.2.3** is the latest.

Update `gradle/libs.versions.toml`:

```toml
arrow = "2.2.3"         # from "2.2.1.1"
```

Arrow 2.2.2 includes context-parameter-related fixes and expanded APIs that improve
compatibility with Kotlin 2.4.0's context parameters. This upgrade is safe to apply
**before** the Kotlin upgrade — it is backward-compatible with Kotlin 2.3.x.

### Kotlin Upgrade

Upgrade `gradle/libs.versions.toml`:

```toml
kotlin = "2.4.0"      # from "2.3.0"
```

Enable the feature in `build.gradle.kts`:

```kotlin
kotlin {
    compilerOptions {
        freeCompilerArgs.add("-Xcontext-parameters")
    }
}
```

### Recommended Upgrade Order

1. Upgrade Arrow first (`arrow = "2.2.3"`), run `./gradlew build test` — green at current Kotlin
2. Upgrade Kotlin (`kotlin = "2.4.0"`), add `-Xcontext-parameters`, run `./gradlew build test` — green before starting migration
3. Now begin migrating functions to `context(Raise<E>)`

## Core Conversion Rule

| Before (Kotlin 2.3.x)        | After (Kotlin 2.4.0+)                   |
| ---------------------------- | --------------------------------------- |
| `fun foo(...): Either<E, A>` | `context(Raise<E>) fun foo(...): A`     |
| Callers use `.bind()`        | Callers just call the function directly |

The `context(Raise<E>)` annotation means the function requires a `Raise<E>` instance
in its calling context — supplied by any enclosing `either { }` block.

## Migration Steps

### Step 1: Identify Leaf Functions

Functions that return `Either<E, A>` and do not call other `Either`-returning
functions are the easiest to migrate. These functions typically:

- Use `ensure()` / `ensureNotNull()` / `raise()` for validation
- Construct a result value directly
- Do not call `.bind()` themselves

### Step 2: Convert the Signature

```kotlin
// Before
private fun getWalletResponseMethod(
    initTransactionTO: InitTransactionTO,
): Either<ValidationError, GetWalletResponseMethod> = either {
    initTransactionTO.redirectUriTemplate
        ?.let { template ->
            with(createQueryWalletResponseRedirectUri) {
                ensure(template.validTemplate()) {
                    ValidationError.InvalidWalletResponseTemplate
                }
            }
            GetWalletResponseMethod.Redirect(template)
        } ?: GetWalletResponseMethod.Poll
}

// After
context(Raise<ValidationError>)
private fun getWalletResponseMethod(
    initTransactionTO: InitTransactionTO,
): GetWalletResponseMethod {
    return initTransactionTO.redirectUriTemplate
        ?.let { template ->
            with(createQueryWalletResponseRedirectUri) {
                ensure(template.validTemplate()) {
                    ValidationError.InvalidWalletResponseTemplate
                }
            }
            GetWalletResponseMethod.Redirect(template)
        } ?: GetWalletResponseMethod.Poll
}
```

Key changes:

- Return type `Either<E, A>` → `A`
- Remove `either { }` wrapper
- Add `context(Raise<E>)` receiver
- `ensure()` / `raise()` / `ensureNotNull()` still work — they're extension functions
  on `Raise<E>`

### Step 3: Update Call Sites

```kotlin
// Before
val getWalletResponseMethod = getWalletResponseMethod(initTransactionTO).bind()

// After — no .bind() needed, error propagation is implicit
val getWalletResponseMethod = getWalletResponseMethod(initTransactionTO)
```

### Step 4: Convert Non-Leaf Functions Bottom-Up

Once all callees are converted, convert the caller:

```kotlin
// Before
override suspend fun invoke(
    initTransactionTO: InitTransactionTO,
): Either<ValidationError, InitTransactionResponse> = either {
    val (nonce, type) = initTransactionTO.toDomain(...).bind()
    val getWalletResponseMethod = getWalletResponseMethod(initTransactionTO)  // already converted
    // ...
}

// After
context(Raise<ValidationError>)
override suspend fun invoke(
    initTransactionTO: InitTransactionTO,
): InitTransactionResponse {
    val (nonce, type) = initTransactionTO.toDomain(...)  // no .bind()
    val getWalletResponseMethod = getWalletResponseMethod(initTransactionTO)
    // ...
}
```

## Root-Level Entry Point

At the outermost level, wrap the call in `either { }` to produce an `Either`:

```kotlin
// adapter/input/web/VerifierApi.kt
fun handle(request: Request): Either<ValidationError, Response> = either {
    val result = initTransaction(input)   // no .bind() — error propagates automatically
    mapToHttpResponse(result)
}
```

The `either { }` block provides the `Raise<ValidationError>` context, and every
`.bind()` call becomes unnecessary — errors propagate implicitly through the call graph.

## Migration Order: Bottom-Up

1. **Leaf functions** — no callees return `Either`, only use `ensure()`/`raise()`
2. **Mid-level functions** — call only already-converted leaf functions
3. **Root use cases** — the outermost `either { }` blocks

For each function:

1. Verify test coverage exists
2. Convert signature + remove `either { }` wrapper
3. Remove `.bind()` at call sites
4. Run tests: `./gradlew test --continue`
5. Commit

## What Stays the Same

These Arrow constructs remain unchanged — context parameters only replace `either { }` / `.bind()`:

| Construct                            | Usage                               |
| ------------------------------------ | ----------------------------------- |
| `Either<E, A>`                       | Still the return type at boundaries |
| `Raise<E>.ensure()`                  | Guard clauses — unchanged           |
| `Raise<E>.ensureNotNull()`           | Null guards — unchanged             |
| `Raise<E>.raise()`                   | Explicit error raising — unchanged  |
| `mapOrAccumulate`                    | Batch validation — unchanged        |
| `NonEmptyList`, `Option`, `Ior`      | Domain types — unchanged            |
| `fold()` / `mapLeft()` / `recover()` | Boundary mapping — unchanged        |

## RailGuards: Verifying Nothing Broke

After each migration step (or before committing), run the full pipeline to catch
regressions early. The compiler and existing test suite are the safety net — a type-level
change like replacing `Either<E, A>` with `context(Raise<E>)` should result in zero
behavioral changes if done correctly.

### Compilation Check

```bash
./gradlew build
```

`build` covers compilation, resource processing, and basic validation. If any call site
still expects an `Either` return type (stale `.bind()` calls, missing context receivers,
or type mismatches), this fails fast with a compilation error.

### Test Suite

```bash
./gradlew test
```

All existing tests must continue to pass without modification. The public API at the
port level (`fun interface` returning `Either<...>`) should remain unchanged
throughout the migration — only internal wiring changes.

To target a specific area:

```bash
./gradlew test --tests "*ClassName*"
./gradlew test --tests "*ClassName*" --continue  # run all, report all failures
```

### Runtime Smoke Test

```bash
./gradlew bootRun
```

Starts the application with the Spring Boot runner. After a successful start, verify
the health endpoint or trigger a minimal flow (e.g., an `/initTransaction` call) to
confirm the wiring resolves correctly at runtime. Context parameter resolution is a
compile-time mechanism, so if `build` passes, `bootRun` should succeed — but a smoke
test catches misconfiguration, missing beans, or wiring issues that only surface at
startup.

### Red Flags

These indicate the migration step was incomplete or incorrect:

| Symptom                                         | Likely Cause                                                                                 | Fix                                                               |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Compilation error: `.bind()` on non-Either type | A caller was not updated after converting a callee                                           | Remove the `.bind()` call                                         |
| Compilation error: "context receiver not found" | A `context(Raise<E>)` function is called outside an `either { }` block or a matching context | Wrap the call in `either { }` or propagate `context(Raise<E>)` up |
| Test failure: wrong error type                  | Error propagation changed (e.g., `raise()` is now called earlier/later)                      | Verify the conversion matches the original short-circuit behavior |
| `bootRun` crash at startup                      | Missing Spring bean or miswired dependency (unrelated to the conversion itself)              | Check the adapter wiring in the Spring configuration              |
| Dead code warning                               | A `.bind()` after conversion may leave an unused import or unreachable branch                | Clean up unused imports and unreachable code                      |

## Anti-Patterns to Avoid During Migration

| Anti-Pattern                                                      | Why Wrong                                                            | Better Approach                                      |
| ----------------------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------- |
| Converting root functions first                                   | Breaks all callers that use `.bind()`                                | Convert leaves first, work upward                    |
| Keeping stray `.bind()` calls                                     | Won't compile — not returning Either                                 | Remove all `.bind()` on converted functions          |
| Mixing `context(Raise<E>)` with `either { }` on the same function | Redundant — context parameter eliminates the need for `either` block | Pick one style per function                          |
| Using `Either.catch { }` inside context-parameter functions       | Can't use `.bind()` on it                                            | Extract to a separate function, call at the boundary |
