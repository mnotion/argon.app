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

## Development without release deployment

Use **`dev.bat`** for day-to-day development. It uses a separate `build-dev` directory, loads QML directly from the repository's `qml/` folder, builds only the `Argon` target, and launches that development executable. It does not run `windeployqt`, copy files into the installed app, or package a release.

- QML edits are read from source the next time `dev.bat` launches. They do not require a build.
- C++ edits use CMake's incremental build. The first development run configures and builds the application; later runs rebuild only C++ files and generated artifacts affected by changes, then relink the app.
- The development build uses the same `%LOCALAPPDATA%\Argon-sim` user-data directory as the installed app.
- Press **F12** to use the interpreter console.

Use **`run.bat`** when you want to build and launch the normal installed app. It calls `build.bat /nopause`, which reconfigures as needed, incrementally compiles changed C++ and QML resources in the normal `build/` directory, runs the interpreter tests, deploys the refreshed app and Qt runtime, and then launches the newly deployed executable. It does not reuse the development executable: the installed app is built separately with its packaged QML resources.

Use **`build.bat`** directly only when you want to build and deploy without launching Argon.


## Run interpreter tests

Use **`test-interpreter.bat`** to build only the standalone `ArgonScriptingTests` target and run its CTest test. After the tests pass, it calls `run.bat`, which now builds and deploys the normal desktop app before launching it. The interpreter test target itself does not rebuild the desktop executable.


## Current limitations

This is the first executable interpreter milestone, not the final Argon automation API. It does not yet have loops, conditionals, user-defined functions, collections, imports, asynchronous operations, or direct UI automation. Those will be added as concrete testing workflows require them.
