---
description: Kotlin baseline guidance for idiomatic Kotlin code.
applyTo: "**/*.kt"
---

- Prefer Kotlin idioms over Java-style patterns.
- Use `data class` for DTO/state holders; prefer immutable `val` properties by default.
- Use default parameter values instead of overload explosions when behavior is clear.
- Favor expression style (`if`, `when`, single-expression functions) for concise, readable code.
- Use null-safety idioms consistently: `?.`, `?:`, `?.let {}`, and explicit `?: throw ...` for required values.
- Prefer collection operators (`filter`, `map`, `firstOrNull`, `associate`, etc.) over manual loops when intent is clearer.
- Use `in` / `!in` for containment checks and idiomatic ranges (`1..n`, `1..<n`, `downTo`, `step`).
- Use scope functions intentionally:
  - `let` for nullable transformations
  - `apply` for object configuration
  - `with` for grouped calls on an existing receiver
  - `run` for expression blocks / fallback computation
- Use extension functions for domain-specific readability when they improve discoverability and do not hide complexity.
- Prefer `object` for stateless singletons and constants grouping.
- Use `@JvmInline value class` for type-safe identifiers/wrappers (for example, domain IDs).
- Use `use {}` for closeable resources instead of manual try/finally.
- Keep error handling explicit; avoid swallowing exceptions.
- Keep public APIs strongly typed and explicit; avoid ambiguous magic values.
