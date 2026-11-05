#include "Interpreter.h"
#include "Lexer.h"
#include "Parser.h"
#include <cmath>
#include <exception>
#include <utility>
namespace Argon::Scripting {
Interpreter::Interpreter() {
    (void)registerNativeFunction("print", [](const std::vector<Value> &arguments, std::vector<std::string> &output) {
        std::string line;
        for (std::size_t i = 0; i < arguments.size(); ++i) {
            if (i) line += " ";
            line += arguments[i].toString();
        }
        output.push_back(std::move(line));
        return Value{};
    });
}
ExecutionResult Interpreter::execute(std::string_view source) {
    ExecutionResult result;
    Lexer lexer(source);
    Parser parser(lexer.tokenize());
    ParseResult parsed = parser.parse();
    if (!parsed.ok()) { result.diagnostics = std::move(parsed.diagnostics); return result; }
    try {
        for (const auto &statement : parsed.statements)
            result.lastValue = executeStatement(*statement, result.output);
        result.success = true;
    } catch (const RuntimeError &error) {
        result.diagnostics.push_back(Diagnostic{error.token.line, error.token.column, error.message});
    } catch (const std::exception &error) {
        result.diagnostics.push_back(Diagnostic{1, 1, std::string("Native function failed: ") + error.what()});
    } catch (...) {
        result.diagnostics.push_back(Diagnostic{1, 1, "Unknown runtime failure."});
    }
    return result;
}
bool Interpreter::registerNativeFunction(std::string name, NativeFunction function) {
    if (name.empty() || !function || m_nativeFunctions.contains(name)) return false;
    m_nativeFunctions.emplace(std::move(name), std::move(function));
    return true;
}
bool Interpreter::hasGlobal(const std::string &name) const { return m_globals.contains(name); }
std::optional<Value> Interpreter::global(const std::string &name) const {
    const auto found = m_globals.find(name);
    if (found == m_globals.end()) return std::nullopt;
    return found->second;
}
Value Interpreter::executeStatement(const Stmt &statement, std::vector<std::string> &output) {
    if (statement.kind == Stmt::Kind::VariableDeclaration) {
        if (m_globals.contains(statement.name))
            throw RuntimeError{statement.token, "Variable '" + statement.name + "' is already declared."};
        Value value = evaluate(*statement.expression, output);
        m_globals.emplace(statement.name, value);
        return value;
    }
    return evaluate(*statement.expression, output);
}
Value Interpreter::evaluate(const Expr &expression, std::vector<std::string> &output) {
    switch (expression.kind) {
    case Expr::Kind::Literal: return expression.literal;
    case Expr::Kind::Variable: {
        const auto found = m_globals.find(expression.name);
        if (found == m_globals.end()) throw RuntimeError{expression.token, "Undefined variable '" + expression.name + "'."};
        return found->second;
    }
    case Expr::Kind::Assign: {
        const auto found = m_globals.find(expression.name);
        if (found == m_globals.end()) throw RuntimeError{expression.token, "Cannot assign to undefined variable '" + expression.name + "'."};
        Value value = evaluate(*expression.right, output);
        found->second = value;
        return value;
    }
    case Expr::Kind::Unary: {
        const Value right = evaluate(*expression.right, output);
        if (expression.token.kind == TokenKind::Bang) {
            if (!right.isBoolean()) throw RuntimeError{expression.token, "Operator '!' requires a boolean."};
            return Value(!right.asBoolean());
        }
        if (expression.token.kind == TokenKind::Minus) {
            if (!right.isNumber()) throw RuntimeError{expression.token, "Unary '-' requires a number."};
            return Value(-right.asNumber());
        }
        break;
    }
    case Expr::Kind::Binary: {
        const Value left = evaluate(*expression.left, output);
        const TokenKind op = expression.token.kind;
        if (op == TokenKind::AndAnd) {
            if (!left.isBoolean()) throw RuntimeError{expression.token, "Operator '&&' requires booleans."};
            if (!left.asBoolean()) return Value(false);
            const Value right = evaluate(*expression.right, output);
            if (!right.isBoolean()) throw RuntimeError{expression.token, "Operator '&&' requires booleans."};
            return Value(right.asBoolean());
        }
        if (op == TokenKind::OrOr) {
            if (!left.isBoolean()) throw RuntimeError{expression.token, "Operator '||' requires booleans."};
            if (left.asBoolean()) return Value(true);
            const Value right = evaluate(*expression.right, output);
            if (!right.isBoolean()) throw RuntimeError{expression.token, "Operator '||' requires booleans."};
            return Value(right.asBoolean());
        }
        const Value right = evaluate(*expression.right, output);
        switch (op) {
        case TokenKind::Plus:
            if (left.isNumber() && right.isNumber()) return Value(left.asNumber() + right.asNumber());
            if (left.isString() && right.isString()) return Value(left.asString() + right.asString());
            throw RuntimeError{expression.token, "Operator '+' requires two numbers or two strings."};
        case TokenKind::Minus:
            if (!left.isNumber() || !right.isNumber()) throw RuntimeError{expression.token, "Operator '-' requires numbers."};
            return Value(left.asNumber() - right.asNumber());
        case TokenKind::Star:
            if (!left.isNumber() || !right.isNumber()) throw RuntimeError{expression.token, "Operator '*' requires numbers."};
            return Value(left.asNumber() * right.asNumber());
        case TokenKind::Slash:
            if (!left.isNumber() || !right.isNumber()) throw RuntimeError{expression.token, "Operator '/' requires numbers."};
            if (right.asNumber() == 0.0) throw RuntimeError{expression.token, "Division by zero."};
            return Value(left.asNumber() / right.asNumber());
        case TokenKind::Percent:
            if (!left.isNumber() || !right.isNumber()) throw RuntimeError{expression.token, "Operator '%' requires numbers."};
            if (right.asNumber() == 0.0) throw RuntimeError{expression.token, "Remainder by zero."};
            return Value(std::fmod(left.asNumber(), right.asNumber()));
        case TokenKind::EqualEqual: return Value(left == right);
        case TokenKind::BangEqual: return Value(!(left == right));
        case TokenKind::Greater: case TokenKind::GreaterEqual: case TokenKind::Less: case TokenKind::LessEqual:
            if (!left.isNumber() || !right.isNumber()) throw RuntimeError{expression.token, "Comparison operators require numbers."};
            if (op == TokenKind::Greater) return Value(left.asNumber() > right.asNumber());
            if (op == TokenKind::GreaterEqual) return Value(left.asNumber() >= right.asNumber());
            if (op == TokenKind::Less) return Value(left.asNumber() < right.asNumber());
            return Value(left.asNumber() <= right.asNumber());
        default: break;
        }
        break;
    }
    case Expr::Kind::Call: {
        const auto function = m_nativeFunctions.find(expression.name);
        if (function == m_nativeFunctions.end()) throw RuntimeError{expression.token, "Unknown function '" + expression.name + "'."};
        std::vector<Value> arguments;
        arguments.reserve(expression.arguments.size());
        for (const auto &argument : expression.arguments) arguments.push_back(evaluate(*argument, output));
        try { return function->second(arguments, output); }
        catch (const RuntimeError &) { throw; }
        catch (const std::exception &error) {
            throw RuntimeError{expression.token, "Native function '" + expression.name + "' failed: " + error.what()};
        } catch (...) {
            throw RuntimeError{expression.token, "Native function '" + expression.name + "' failed with an unknown error."};
        }
    }
    }
    throw RuntimeError{expression.token, "Invalid expression."};
}
} // namespace Argon::Scripting
