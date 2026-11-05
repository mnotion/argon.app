# Argon Script Interpreter

Argon Script is an embedded, deliberately small interpreter intended first for repeatable development tests of Argon's UI, Ink engine, and C++ services. It interprets source directly: scripts are not compiled to bytecode and do not create a separate executable.

## Current language

```argon
// Variables and arithmetic
let width = 10;
let height = 20;
let area = width * height;
print(area); // 200

// Strings, booleans, comparisons and assignment
let label = "Argon";
let enabled = true;
label = label + " Script";
print(label);
print(enabled && area >= 100);
```

Supported features: `let` declarations; reassignment; numbers, strings, booleans and `null`; arithmetic; comparisons; boolean logic with short-circuit evaluation; named native calls; built-in `print(...)`; line comments; string escapes; persistent globals; and line/column diagnostics. Each declaration and expression statement ends in `;`.

## Embedding and host capabilities

The C++ host can register an explicit function with `Interpreter::registerNativeFunction`. Scripts can call only registered functions. This is the intended integration boundary for Argon services: expose specific, reviewed operations rather than arbitrary QObject reflection, unrestricted filesystem access, native code loading, or unrestricted C++ execution.

The interpreter has no general-purpose file, process, network, Qt reflection, or native-code APIs.

## Build and test

The scripting engine has no Qt dependency. Configure with `-DARGON_BUILD_SCRIPTING_TESTS=ON`, build, then run `ctest --test-dir build --output-on-failure`.

The engine sources are also part of the `Argon` executable. The existing Windows `run.bat` remains the one-file build, deployment, and launch entry point.

## Current limitations

This is the first executable interpreter milestone, not the final Argon automation API. It does not yet have loops, conditionals, user-defined functions, collections, imports, asynchronous operations, or direct UI automation. Those will be added as concrete testing workflows require them.
