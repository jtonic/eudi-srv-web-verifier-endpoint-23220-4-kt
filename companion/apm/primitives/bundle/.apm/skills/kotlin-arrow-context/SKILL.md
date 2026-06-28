---
name: kotlin-arrow-context
description: >
  Kotlin Arrow functional programming with typed errors using Kotlin 2.4 context parameters.
  Use whenever the user writes or refactors Kotlin code involving Arrow's Either, Raise, typed
  errors, functional error handling, or context parameters — especially when migrating away from
  the `either { }.bind()` builder pattern toward `context(Raise<E>)` context parameters. Also
  use for Kotest testing with Arrow assertions (`shouldBeLeft`, `shouldBeRight`), coroutine
  interop with `Raise`, and setting up Kotlin 2.4 compiler flags.
---

# Kotlin Arrow Context Parameters

This skill covers writing idiomatic Kotlin using **Arrow KT** typed errors with **Kotlin 2.4 context parameters**. The primary goal is migrating from the traditional `either { }.bind()` builder pattern to flat, composable `context(Raise<E>)` functions.

## Why context parameters?

The standard Arrow `either { }` builder works but has drawbacks:

```kotlin
// Traditional either builder — .bind() noise, nesting, hard to compose
fun add(a: Int, b: Int) = either {
    if (a == b) raise(NotFoundError("Boom!!!")) else a + b
}
// Caller: either { add(1, 2).bind() }
```

With Kotlin 2.4 context parameters, the `Raise<E>` becomes an implicit dependency:

```kotlin
// Context parameters — flat, no .bind(), caller just calls the function
context(_: Raise<NotFoundError>)
fun add(a: Int, b: Int): Int =
    if (a == b) raise(NotFoundError("Boom!!!")) else a + b
// Caller: either { add(1, 2) }
```

The caller doesn't need `.bind()` because the compiler wires the `Raise` context through automatically. This means:
- Functions compose naturally without `.bind()` chains
- Functions can be tested in isolation by providing a mock `Raise`
- The same function works in `either { }`, `option { }`, or custom `Raise` scopes

## Syntax rules

Every entry in `context(...)` must be declared as `name: Type` or `_: Type`. Bare-type lists like `context(Raise<E>, CoroutineScope)` are the **legacy context-receivers** syntax and will not compile under `-Xcontext-parameters` alone.

Use `_: Raise<E>` (the underscore form) when you don't need to reference the `Raise` instance by name. This is Arrow's recommended form — `raise`, `ensure`, `ensureNotNull`, `bind`, `catch`, and `recover` are members/extensions of `Raise` and resolve unqualified against the implicit context value, so the parameter name is usually unnecessary. Use a named parameter (`context(r: Raise<E>)`) only when you must pass the `Raise` instance to another function explicitly, or to disambiguate multiple `Raise` scopes.

## Compiler setup

Kotlin 2.4 context parameters are experimental. The compiler flag **must** be enabled.

**Maven (`pom.xml`):**
```xml
<plugin>
  <groupId>org.jetbrains.kotlin</groupId>
  <artifactId>kotlin-maven-plugin</artifactId>
  <version>${kotlin.version}</version>
  <configuration>
    <args>
      <arg>-Xcontext-parameters</arg>
    </args>
  </configuration>
</plugin>
```

**Gradle (`build.gradle.kts`):**
```kotlin
kotlin {
    compilerOptions {
        freeCompilerArgs.add("-Xcontext-parameters")
    }
}
```

Kotlin version must be ≥ 2.4.0. Arrow version in this project is 2.2.3.

## Core patterns

### Pattern 1: Define a typed error function

```kotlin
data class NotFoundError(override val message: String) : RuntimeException(message)

context(_: Raise<NotFoundError>)
fun findUser(id: Int): User =
    userRepository.get(id) ?: raise(NotFoundError("User $id not found"))
```

Key conventions:
- The error type extends `RuntimeException` (or any `Throwable`) — this is Arrow's convention
- Prefer `context(_: Raise<E>)` — matches Arrow's official docs; `raise`, `ensure`, and friends resolve unqualified against the implicit context value
- Declare the return type explicitly (not inferred) — the compiler needs it
- Use the named form `context(r: Raise<E>)` + `r.raise(...)` only when you need to reference the `Raise` instance by name (e.g. passing it to another function, or disambiguating multiple `Raise` scopes)

### Pattern 2: Compose multiple context-parameter functions

```kotlin
either {
    val user = findUser(42)       // no .bind() needed
    val order = getOrder(user.id) // context flows automatically
    process(user, order)
}
```

The `either { }` block at the top provides the `Raise` scope. All functions inside inherit it.

### Pattern 3: Multiple context parameters

```kotlin
context(_: Raise<NotFoundError>, scope: CoroutineScope)
suspend fun fetchAndValidate(id: Int): User {
    val user = fetchUser(id) // from coroutine
    return user ?: raise(NotFoundError("User $id not found"))
}
```

When using multiple context parameters, give each a name (`name: Type`) or underscore (`_: Type`). Use `_` for the `Raise` parameter when you don't reference it by name; name the others (e.g. `scope: CoroutineScope`) when you need to call members on them.

### Pattern 4: Ensure (assertions as control flow)

```kotlin
context(_: Raise<ValidationError>)
fun validateEmail(email: String): String {
    ensure(email.contains("@")) { ValidationError("Invalid email: $email") }
    return email
}
```

`ensure` is a `Raise` extension: if the predicate fails, it calls `raise` with the lazy block. It resolves unqualified against the implicit context parameter, just like `raise` itself.

## Context parameters resolution

Kotlin resolves context parameters at the call site by searching for matching context values in the current scope, matching them **by type** (not by name). This is why `_: Raise<E>` works — the value is available for resolution even though it has no name.

A few consequences relevant to Arrow:

- **Type-based matching**: `either { findUser(1) }` works because the `either { }` block brings a `Raise<E>` value into scope, which matches the `context(_: Raise<E>)` declared by `findUser`.
- **Ambiguity**: if two values of the same `Raise<E>` type are in scope at the same level, the compiler reports an ambiguity error. This is the main caveat to the "works in `either { }`, `option { }`, or custom `Raise` scopes" claim — it holds as long as no second `Raise` of the same error type is in scope.
- **Explicit context arguments**: to disambiguate, or to call a function with a specific context value, pass it explicitly at the call site (`findUser(id, Raise = myRaise)`). This requires the `-Xexplicit-context-arguments` compiler flag:

**Maven (`pom.xml`):**
```xml
<arg>-Xexplicit-context-arguments</arg>
```

**Gradle (`build.gradle.kts`):**
```kotlin
freeCompilerArgs.add("-Xexplicit-context-arguments")
```

## When NOT to use context parameters

- **One-liner either blocks**: Simple inline `either { a + b }` calls are fine as-is
- **Libraries exposing Arrow types**: Public APIs may want to stay builder-based for compatibility
- **Pre-Kotlin 2.4 projects**: Context parameters are only available in Kotlin 2.4+

## Testing with Kotest

Use Kotest with the Arrow assertions library:

```kotlin
import arrow.core.Either
import arrow.core.raise.either
import io.kotest.assertions.arrow.core.shouldBeLeft
import io.kotest.assertions.arrow.core.shouldBeRight
import io.kotest.core.spec.style.FreeSpec

class MyTest : FreeSpec({
    "happy path" {
        either { findUser(1) } shouldBeRight expectedUser
    }
    "not found" {
        either { findUser(999) } shouldBeLeft NotFoundError("User 999 not found")
    }
})
```

Key testing patterns:
- Wrap the context function in `either { }` at the call site (not in the function definition)
- `shouldBeRight` and `shouldBeLeft` give readable assertions on `Either`
- `shouldBeLeft` matches on the error value directly

Dependencies (from the project's `pom.xml`):
```
io.kotest:kotest-runner-junit5-jvm (managed via kotest-bom 6.1.11)
io.kotest:kotest-assertions-core-jvm
io.kotest:kotest-assertions-arrow-jvm:6.1.11
```

## Migration recipe

To migrate an existing `either`-builder function to context parameters:

1. **Extract the body** from the `either { }` block
2. **Add `context(_: Raise<E>)`** as the first line of the function (use a named parameter only if you need to reference the `Raise` instance by name)
3. **Declare the return type** explicitly (no longer inferred from `either`)
4. **Remove `.bind()`** from all call sites
5. **Wrap the top-level caller** in `either { }` if not already present
6. **Run the tests** — if they pass, the migration is correct

Before:
```kotlin
fun process(input: Int) = either {
    val a = step1(input).bind()
    val b = step2(a).bind()
    step3(b)
}
```

After:
```kotlin
context(_: Raise<ProcessingError>)
fun step1(input: Int): Int = ...

context(_: Raise<ProcessingError>)
fun step2(input: Int): String = ...

context(_: Raise<ProcessingError>)
fun step3(input: String): User = ...

fun process(input: Int) = either {
    val a = step1(input)
    val b = step2(a)
    step3(b)
}
```

## Interop with arrow-resilience

When using `arrow-resilience` (retry, circuit breaker), context parameters compose naturally:

```kotlin
context(_: Raise<TransientError>)
suspend fun callExternalApi(): Response {
    val result = Schedule.recurs<Throwable>(3L)
        .retryEither { api.call() }
        .getOrElse { raise(TransientError("API unavailable after retries")) }
    return result
}
```
