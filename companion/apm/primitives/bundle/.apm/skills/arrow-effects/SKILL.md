---
name: arrow-effects
description: "Arrow-kt typed error handling and effect-based development patterns. USE FOR: Either monad, raise/either DSL, typed domain errors, bind/ensure patterns, NonEmptyList validation, mapOrAccumulate, Ior, Option, and functional error handling in Kotlin. DO NOT USE FOR: Spring Boot basics, general Kotlin patterns, standalone coroutines, kotlinx-serialization."
license: Apache-2.0
compatibility: opencode
metadata:
  framework: arrow-kt-2.2
---

# Arrow Effect-Based Development

Arrow-kt 2.x replaces exception-based error handling with **typed errors** — errors become part of the return type, making all error paths visible at compile time. The project uses `arrow-core` and `arrow-fx-coroutines`.

## Core Types

| Type | Purpose | When to Use |
|------|---------|-------------|
| `Either<L, R>` | A value of either `Left(L)` or `Right(R)` | Return type for operations that can fail. `Left` = error, `Right` = success. |
| `Raise<E>` | Context receiver for error propagation | Inside `either { }` blocks, `Raise` provides `ensure()`, `ensureNotNull()`, `raise()`, and `bind()`. |
| `NonEmptyList<A>` | A list guaranteed to have at least one element | Validation errors, algorithm sets, encryption methods — anything requiring non-empty semantics. |
| `Option<A>` | A value that may or may not exist (`Some`/`None`) | Preferred over nullable for explicit optionality, especially in domain models. |
| `Ior<L, R>` | Both Left and Right, or just one | Rare. Use when you need to accumulate warnings alongside a successful result. |

## The `either { }` DSL

The primary pattern. Wrap a function body in `either { }` to produce an `Either`. Use `bind()` to unwrap nested Eithers — it short-circuits on `Left`.

### Pattern: Use Case Implementation

From the project use cases (`InitTransaction`, `PostWalletResponse`):

```kotlin
// port/input/InitTransaction.kt — fun interface defining the contract
fun interface InitTransaction {
    suspend operator fun invoke(
        initTransactionTO: InitTransactionTO,
    ): Either<ValidationError, InitTransactionResponse>
}

// port/input/InitTransaction.kt — Live implementation
class InitTransactionLive(
    private val generateTransactionId: GenerateTransactionId,
    // ... other dependencies
) : InitTransaction {

    override suspend fun invoke(
        initTransactionTO: InitTransactionTO,
    ): Either<ValidationError, InitTransactionResponse> = either {
        // bind() extracts the Right value, or short-circuits with Left
        val (nonce, type) = initTransactionTO.toDomain(
            verifierConfig.transactionDataHashAlgorithm,
            verifierConfig.clientMetaData.vpFormatsSupported,
        ).bind()

        val responseMode = responseMode(initTransactionTO)
        val getWalletResponseMethod = getWalletResponseMethod(initTransactionTO).bind()
        val issuerChain = issuerChain(initTransactionTO).bind()

        // ... business logic ...

        storePresentation(updatedPresentation)
        response // implicitly wrapped in Right
    }
}
```

### `bind()` — Extracting Values

`bind()` extracts the `Right` value from any `Either`. On `Left`, it immediately short-circuits the entire `either { }` block, returning the error.

```kotlin
// Chain operations — each bind() potentially short-circuits
val (nonce, type) = initTransactionTO.toDomain(...).bind()
val getWalletResponseMethod = getWalletResponseMethod(initTransactionTO).bind()
val issuerChain = issuerChain(initTransactionTO).bind()
```

Also used to chain `Either`-producing operations inline:
```kotlin
.submit(presentation, responseObject)
    .onLeft { cause -> logFailure(presentation, responseObject, cause) }
    .onRight { (submitted, accepted) -> logWalletResponsePosted(submitted, accepted) }
    .map { (_, accepted) -> accepted }
    .bind()
```

### `ensure()` — Guard Clauses

`ensure()` takes a boolean condition and an error lambda. If false, raises the error and short-circuits.

```kotlin
// port/input/InitTransaction.kt — validating required fields
fun requiredQuery(): DCQL {
    ensureNotNull(dcqlQuery) { ValidationError.MissingPresentationQuery }
    ensure(
        dcqlQuery.credentials.value.all {
            val format = it.format
            vpFormatsSupported.supports(format)
        },
    ) { ValidationError.UnsupportedFormat }
    return dcqlQuery
}

// port/input/InitTransaction.kt — state machine guards
fun requiredNonce(): Nonce {
    ensure(!nonce.isNullOrBlank()) { ValidationError.MissingNonce }
    return Nonce(nonce)
}
```

### `ensureNotNull()` — Null Guards

Shorthand for `ensure(value != null)` — also smart-casts to non-null:

```kotlin
// port/input/PostWalletResponse.kt
ensureNotNull(vpToken) { WalletResponseValidationError.MissingVpToken }

// port/input/InitTransaction.kt
ensureNotNull(presentation) { WalletResponseValidationError.PresentationNotFound }
```

### `raise()` — Explicit Error Raising

Use `raise()` when the error condition cannot be expressed as a simple boolean:

```kotlin
// port/input/InitTransaction.kt — branching logic
when {
    null != initTransaction.authorizationRequestUri && null != initTransaction.authorizationRequestScheme ->
        raise(ValidationError.ContainsBothAuthorizationRequestUriAndAuthorizationRequestScheme)

    null != initTransaction.authorizationRequestUri ->
        UnresolvedAuthorizationRequestUri.fromUri(initTransaction.authorizationRequestUri).getOrElse {
            raise(ValidationError.InvalidAuthorizationRequestUri)
        }
    // ...
}

// port/input/PostWalletResponse.kt — nested either with getOrElse fallback
}.getOrElse {
    when (it) {
        is BadJOSEException -> raise(WalletResponseValidationError.InvalidEncryptedResponse(it))
        else -> throw it
    }
}
```

## Domain Error Modeling

Errors are modeled as **sealed interfaces** with data objects. This gives the compiler exhaustive checking when matching errors at the boundary.

### Pattern: Sealed Error Hierarchy

```kotlin
// port/input/InitTransaction.kt — flat errors + nested sub-interfaces
sealed interface ValidationError {
    data object MissingPresentationQuery : ValidationError
    data object MissingNonce : ValidationError
    data object InvalidWalletResponseTemplate : ValidationError
    data object InvalidTransactionData : ValidationError
    data object UnsupportedFormat : ValidationError
    data object InvalidIssuerChain : ValidationError

    // Sub-sealed interface for grouped constraints
    sealed interface HaipNotSupported : ValidationError {
        data object SdJwtVcOrMsoMdocMustBeSupported : HaipNotSupported
        data object JwsAlgorithmES256MustBeSupported : HaipNotSupported
        data object ClientIdPrefixX509HashMustBeUsed : HaipNotSupported
        // ...
    }
}

// port/input/PostWalletResponse.kt — errors with payload
sealed interface WalletResponseValidationError {
    data object PresentationNotFound : WalletResponseValidationError
    data class UnexpectedResponseMode(
        val requestId: RequestId,
        val expected: ResponseModeOption,
        val actual: ResponseModeOption,
    ) : WalletResponseValidationError
    data class InvalidVpToken(val message: String, val cause: Throwable? = null) : WalletResponseValidationError
    // ...
}
```

**Guidelines:**
- Use `data object` for errors with no payload
- Use `data class` for errors that carry context (useful for error messages/diagnostics)
- Group related errors in nested `sealed interface` sub-types for namespacing
- Favor specific error types over generic string errors

## `Raise<E>` as Context Receiver

For reusable validation functions, use `Raise<E>` as a **context receiver** — callable from any `either { }` block with a matching error type.

### Pattern: Profile Validation

```kotlin
// port/input/InitTransaction.kt — reusable validator with Raise context
private fun interface ProfileValidator {
    suspend fun Raise<ValidationError>.validate(
        config: VerifierConfig,
        presentation: Presentation.Requested,
        jarMode: EmbedOption<RequestId>,
    )

    companion object {
        val OpenId4VP = ProfileValidator { _, _, _ -> }
        val HAIP = ProfileValidator { config, presentation, jarMode ->
            with(config.clientMetaData.vpFormatsSupported) {
                ensure(null != sdJwtVc || null != msoMdoc) {
                    ValidationError.HaipNotSupported.SdJwtVcOrMsoMdocMustBeSupported
                }
                // ... more checks
            }
            ensure(config.verifierId is VerifierId.X509Hash) {
                ValidationError.HaipNotSupported.ClientIdPrefixX509HashMustBeUsed
            }
            ensure(presentation.responseMode is ResponseMode.DirectPostJwt) {
                ValidationError.HaipNotSupported.ResponseModeDirectPostJwtMustBeSupported
            }
            ensure(jarMode is EmbedOption.ByReference) {
                ValidationError.HaipNotSupported.AuthorizationRequestMustBeProvidedByReference
            }
        }
    }
}

// Usage — called from inside an either { } block
with(profile.validator) {
    validate(verifierConfig, requestedPresentation, jarMode)
}
```

### Pattern: Device Response Validation with Raise

```kotlin
// adapter/out/mso/DeviceResponseValidator.kt
private suspend fun Raise<DeviceResponseError.InvalidDocuments>.ensureValidDocuments(
    deviceResponse: DeviceResponse,
    documentValidator: DocumentValidator,
    transactionId: TransactionId?,
    handoverInfo: HandoverInfo?,
): List<MDoc> =
    deviceResponse.documents.withIndex().mapOrAccumulate { (index, document) ->
        documentValidator
            .ensureValid(document, transactionId, handoverInfo)
            .mapLeft { documentErrors -> InvalidDocument(index, document.docType.value, documentErrors) }
            .bind()
    }.mapLeft(DeviceResponseError::InvalidDocuments).bind()
```

## Validation Accumulation with `mapOrAccumulate`

Use `mapOrAccumulate` when you need to validate multiple items and collect **all** errors, not just the first one.

```kotlin
// adapter/out/mso/DeviceResponseValidator.kt — validates all documents, collects all errors
deviceResponse.documents.withIndex().mapOrAccumulate { (index, document) ->
    documentValidator
        .ensureValid(document, transactionId, handoverInfo)
        .mapLeft { documentErrors -> InvalidDocument(index, document.docType.value, documentErrors) }
        .bind()
}.mapLeft(DeviceResponseError::InvalidDocuments).bind()
```

**Fail-fast vs accumulate:**
| Approach | Code | Behavior |
|----------|------|----------|
| Fail-fast | `list.map { validate(it).bind() }` | Stops at first error |
| Accumulate | `list.mapOrAccumulate { validate(it).bind() }` | Collects all errors as `NonEmptyList<E>` → `mapLeft` converts to domain error |

## NonEmptyList

For types that must have at least one element. Prevents empty-collection bugs at the type level.

```kotlin
// domain/VerifierConfig.kt — algorithms, methods, etc.
val encryptionMethods: NonEmptyList<EncryptionMethod>
val sdJwtAlgorithms: NonEmptyList<JWSAlgorithm>?
val issuerAuthAlgorithms: NonEmptyList<CoseAlgorithm>?

// domain/TransactionData.kt
val credentialIds: NonEmptyList<String>
val hashAlgorithms: NonEmptyList<String>?
```

### Creating NonEmptyList

```kotlin
import arrow.core.nonEmptyListOf
import arrow.core.toNonEmptyListOrNull

val list = nonEmptyListOf("a", "b")       // safe: compile-time guarantee
val maybe = someList.toNonEmptyListOrNull() // returns NonEmptyList? or null
```

### Serialization

```kotlin
// Use NonEmptyListSerializer for kotlinx.serialization
@file:UseSerializers(NonEmptyListSerializer::class)
import arrow.core.serialization.NonEmptyListSerializer
```

## `Either.catch` — Wrapping Exception-Throwing Code

Use `Either.catch { }` to capture exceptions as `Left`. Useful when calling Java/third-party code that throws.

```kotlin
// port/input/InitTransaction.kt — wrapping JCA certificate parsing
private fun issuerChain(initTransaction: InitTransactionTO): Either<ValidationError, NonEmptyList<X509Certificate>?> =
    Either.catch {
        initTransaction.issuerChain?.let { parsePemEncodedX509CertificateChain(it).getOrThrow() }
    }.mapLeft { ValidationError.InvalidIssuerChain }
```

**Caution:** `Either.catch` catches `Throwable` by default. Use `Either.catch(e: Exception)` to narrow the scope, or map/recover specific exception types.

## Boundary Mapping: Either to HTTP

At the adapter layer, map `Either` to Spring WebFlux `ServerResponse` using `fold`:

```kotlin
// adapter/input/web/VerifierApi.kt — fold with named parameters
initTransaction(input).fold(
    ifRight = { response ->
        when (response) {
            is InitTransactionResponse.JwtSecuredAuthorizationRequestTO -> {
                ok().json()
                    .header(TRANSACTION_ID_HEADER, response.transactionId)
                    .bodyValueAndAwait(response)
            }
            is InitTransactionResponse.QrCode -> {
                ok().contentType(IMAGE_PNG)
                    .header(TRANSACTION_ID_HEADER, response.transactionId)
                    .bodyValueAndAwait(response.qrCode)
            }
        }
    },
    ifLeft = { error -> error.asBadRequest() },
)

// adapter/input/web/WalletApi.kt — fold with error-to-JSON conversion
postWalletResponse(requestId, walletResponse).fold(
    ifRight = { response ->
        ok().json().bodyValueAndAwait(response ?: JsonObject(emptyMap()))
    },
    ifLeft = { error ->
        badRequest().json().bodyValueAndAwait(error.toJson())
    },
)
```

### Error to HTTP Mapping

Exhaustively match every error variant (compiler-enforced with sealed interface):

```kotlin
// adapter/input/web/VerifierApi.kt
private suspend fun ValidationError.asBadRequest(): ServerResponse {
    val error = when (this) {
        ValidationError.MissingPresentationQuery -> "MissingPresentationQuery"
        ValidationError.MissingNonce -> "MissingNonce"
        ValidationError.InvalidWalletResponseTemplate -> "InvalidWalletResponseTemplate"
        // ... every variant must be covered
    }
    return badRequest().json().bodyValueAndAwait(mapOf("error" to error))
}
```

## Coroutines Integration

All use cases are `suspend` functions returning `Either`. Patterns for coroutine integration:

### Sequential Composition

```kotlin
override suspend fun invoke(
    initTransactionTO: InitTransactionTO,
): Either<ValidationError, InitTransactionResponse> = either {
    val (nonce, type) = initTransactionTO.toDomain(...).bind()    // step 1
    val responseMode = responseMode(initTransactionTO)            // step 2
    val getWalletResponseMethod = getWalletResponseMethod(initTransactionTO).bind() // step 3
    // ... each bind() may suspend
}
```

### Inline Suspend Functions in `either { }`

Suspend functions can be called directly inside `either { }` blocks:

```kotlin
// port/input/PostWalletResponse.kt — suspend functions declared inline
private suspend fun submit(
    presentation: RequestObjectRetrieved,
    responseObject: AuthorisationResponseTO,
): Either<WalletResponseValidationError, Pair<Submitted, WalletResponseAcceptedTO?>> =
    either {
        val submitted = doSubmit(presentation, responseObject)
            .bind()
            .also { storePresentation(it) }
        // ...
        submitted to accepted
    }
```

## Project-Specific Patterns

### Port-Hexagonal Architecture

The project uses hexagonal architecture. Arrow patterns map onto it as follows:

```
port/input/
  ├── InitTransaction.kt     ← fun interface returns Either<ValidationError, Response>
  ├── PostWalletResponse.kt  ← fun interface returns Either<WalletResponseValidationError, Response>
  └── GetWalletResponse.kt   ← returns QueryResponse (non-Either, uses sealed class)

adapter/input/web/
  ├── VerifierApi.kt         ← fold() maps Either → ServerResponse
  └── WalletApi.kt           ← fold() maps Either → ServerResponse

adapter/out/
  └── mso/
      └── DeviceResponseValidator.kt ← mapOrAccumulate for batch validation
```

### Dependency Versions

From `gradle/libs.versions.toml`:
- `arrow = "2.2.1.1"` (arrow-stack BOM)
- `arrow-core`, `arrow-fx-coroutines`, `arrow-core-serialization`

### Key Imports

```kotlin
import arrow.core.*
import arrow.core.raise.either
import arrow.core.raise.ensure
import arrow.core.raise.ensureNotNull
import arrow.core.raise.Raise
```

## Anti-patterns

| Anti-pattern | Why Wrong | Better Alternative |
|---|---|---|
| `either.getOrThrow()` in domain logic | Throws if Left, bypassing typed errors | Use `bind()` inside `either { }` or `fold()` at boundaries |
| Mixing `try/catch` with `Either` | Defeats typed error tracking | Use `Either.catch {}` or `recover` |
| `either.fold({ error -> ... }, { success -> ... })` with positional args | Error-prone argument ordering | Use named parameters: `fold(ifRight = ..., ifLeft = ...)` |
| Returning `Either<String, T>` instead of sealed errors | Loses exhaustiveness checking | Always use sealed error types |
| Using `null` for optional values | Bypasses type safety | Use `Option` or make null explicit via the type |
| Blind `!!` or `getOrThrow()` | Runtime crashes | Use `ensureNotNull()` or `bind()` |
| Catching broad `Throwable` in `Either.catch` | Masks bugs like `OutOfMemoryError` | Narrow to `Exception` or the specific types you expect |
