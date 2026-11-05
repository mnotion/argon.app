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

## Developer console

The Windows development build enables the F12 console through `ARGON_ENABLE_SCRIPT_CONSOLE=ON`. Press **F12** while Argon is running to open it. The interpreter session persists between Run clicks; use **Reset session** to clear its variables.

The console currently exposes only these Argon host functions:

- `applicationVersion()` — returns the running Argon version.
- `search("text")` — runs Argon's existing name search and returns the first page as JSON text.
- `nextSearchPage()` — returns the next search page as JSON text.
- `print(...)` — writes values to the console output.

The console option defaults to OFF, so regular builds do not enable the developer interface. The Windows `build.bat` configuration turns it on.

## Run without compiling

Use **`run.bat`** to launch the already-deployed app from `%LOCALAPPDATA%\Argon-sim\App\Argon.exe`. It does not call CMake, compile targets, or deploy Qt files. Press **F12** in the running app to use the interpreter.

Use **`build.bat`** only when you intentionally need to compile and deploy changes to the C++ or QML application. The first deployment also requires this build step. Once the deployed app exists, normal launches should use `run.bat`.

## Run interpreter tests

Use **`test-interpreter.bat`** to build only the standalone `ArgonScriptingTests` target and run its CTest test. It does not rebuild the Argon desktop executable or deploy the application. This test command requires the existing `build` directory to have been configured with `ARGON_BUILD_SCRIPTING_TESTS=ON`, as the Windows `build.bat` configuration does.

## Current limitations

This is the first executable interpreter milestone, not the final Argon automation API. It does not yet have loops, conditionals, user-defined functions, collections, imports, asynchronous operations, or direct UI automation. Those will be added as concrete testing workflows require them.
