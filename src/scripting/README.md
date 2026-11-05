# Argon Script

Argon Script is an internal scripting language intended first for repeatable development tests of Argon's UI, Ink engine, and services.

## Compiler pipeline

1. Lexer: source text to tokens.
2. Parser: tokens to an AST (next implementation step).
3. Compiler: AST to bytecode.
4. VM: executes bytecode with an explicit, allowlisted host API.

## Initial syntax direction

```argon
let message = "hello";
let enabled = true;
```

The language should begin with expressions, local variables, and host API calls. Control flow and functions can follow after the runtime is testable.

## Safety boundary

The runtime must not expose arbitrary C++/Qt reflection, unrestricted QObject construction, native code loading, or unrestricted filesystem access. UI, Ink, and Search integrations should be registered as explicit capabilities and enabled only in developer/test builds initially.

## Tests

Configure with `-DARGON_BUILD_SCRIPTING_TESTS=ON`, then build and run `ctest`.
