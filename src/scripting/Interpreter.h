#pragma once
#include "AST.h"
#include "Diagnostic.h"
#include "Value.h"
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>
namespace Argon::Scripting {
struct ExecutionResult {
    bool success = false;
    std::vector<std::string> output;
    std::vector<Diagnostic> diagnostics;
    std::optional<Value> lastValue;
};
class Interpreter final {
public:
    using NativeFunction = std::function<Value(const std::vector<Value> &, std::vector<std::string> &)>;
    Interpreter();
    [[nodiscard]] ExecutionResult execute(std::string_view source);
    [[nodiscard]] bool registerNativeFunction(std::string name, NativeFunction function);
    [[nodiscard]] bool hasGlobal(const std::string &name) const;
    [[nodiscard]] std::optional<Value> global(const std::string &name) const;
private:
    struct RuntimeError { Token token; std::string message; };
    [[nodiscard]] Value executeStatement(const Stmt &statement, std::vector<std::string> &output);
    [[nodiscard]] Value evaluate(const Expr &expression, std::vector<std::string> &output);
    std::unordered_map<std::string, Value> m_globals;
    std::unordered_map<std::string, NativeFunction> m_nativeFunctions;
};
} // namespace Argon::Scripting
