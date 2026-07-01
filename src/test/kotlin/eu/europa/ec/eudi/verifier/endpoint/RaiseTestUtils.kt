package eu.europa.ec.eudi.verifier.endpoint

import arrow.core.raise.Raise
import arrow.core.raise.either
import kotlin.test.fail

suspend fun <E, A> assertRaises(block: suspend Raise<E>.() -> A): E =
    either { block() }.fold(
        ifLeft = { it },
        ifRight = { fail("Expected an error to be raised, but the block succeeded with: $it") }
    )

suspend fun <E, A> assertSucceeds(block: suspend Raise<E>.() -> A): A =
    either { block() }.fold(
        ifLeft = { fail("Expected success, but raised error: $it") },
        ifRight = { it }
    )
