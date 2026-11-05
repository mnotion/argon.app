#include "Interpreter.h"
#include "Lexer.h"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
using Argon::Scripting::Interpreter;
using Argon::Scripting::Lexer;
using Argon::Scripting::TokenKind;
using Argon::Scripting::Value;
namespace {
void check(bool condition, const char *message) {
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}
void testLexer() {
    Lexer lexer("let answer = 42;\nanswer >= 10 && true // comment\n");
    const auto tokens = lexer.tokenize();
    check(tokens.size() == 11, "lexer token count and EOF");
    check(tokens[0].kind == TokenKind::Let, "let keyword");
    check(tokens[1].kind == TokenKind::Identifier, "identifier");
    check(tokens[6].kind == TokenKind::GreaterEqual, "greater-equal operator");
    check(tokens[8].kind == TokenKind::AndAnd, "logical and operator");
    check(tokens.back().kind == TokenKind::EndOfFile, "EOF after whitespace and comment");
}
void testArithmeticAndVariables() {
    Interpreter interpreter;
    const auto result = interpreter.execute("let x = 10;\nlet y = 20;\nlet answer = x + y;\nprint(answer);\nprint(2 + 3 * 4);\nanswer;\n");
    check(result.success, "arithmetic program executes");
    check(result.output.size() == 2, "arithmetic output count");
    check(result.output[0] == "30", "variable arithmetic output");
    check(result.output[1] == "14", "operator precedence");
    check(interpreter.global("answer").has_value(), "global retained");
    check(result.lastValue.has_value() && result.lastValue->toString() == "30", "last expression value");
}
void testPersistentEnvironmentAndAssignment() {
    Interpreter interpreter;
    check(interpreter.execute("let count = 1;").success, "initial declaration");
    const auto result = interpreter.execute("count = count + 4; print(count);");
    check(result.success, "prior globals persist");
    check(result.output.size() == 1 && result.output[0] == "5", "assignment and persistence");
}
void testStringsBooleansAndShortCircuit() {
    Interpreter interpreter;
    const auto result = interpreter.execute("let name = \"Ar\" + \"gon\";\nprint(name);\nprint(2 < 3 && true);\nprint(false && unknownFunction());\nprint(true || unknownFunction());\nprint(\"line\\nnext\");\n");
    check(result.success, "strings, booleans and short circuit");
    check(result.output.size() == 5, "output count");
    check(result.output[0] == "Argon", "string concatenation");
    check(result.output[1] == "true", "comparison and logical and");
    check(result.output[2] == "false", "logical and short circuits");
    check(result.output[3] == "true", "logical or short circuits");
    check(result.output[4] == "line\nnext", "escape decoding");
}
void testNativeFunctionAllowlist() {
    Interpreter interpreter;
    check(interpreter.registerNativeFunction("doubleIt", [](const std::vector<Value> &args, std::vector<std::string> &) {
        if (args.size() != 1 || !args[0].isNumber()) throw std::runtime_error("doubleIt expects one number");
        return Value(args[0].asNumber() * 2.0);
    }), "register host function");
    check(!interpreter.registerNativeFunction("doubleIt", [](const auto &, auto &) { return Value{}; }), "duplicate rejected");
    const auto result = interpreter.execute("print(doubleIt(21));");
    check(result.success && result.output.size() == 1 && result.output[0] == "42", "registered function callable");
    check(!interpreter.execute("unknown();").success, "unregistered function rejected");
}
void testDiagnostics() {
    Interpreter interpreter;
    const auto parseError = interpreter.execute("let value = 1\nprint(value);");
    check(!parseError.success && !parseError.diagnostics.empty(), "missing semicolon is a parse error");
    check(parseError.diagnostics[0].line == 2, "parse error line");
    const auto runtimeError = interpreter.execute("print(missing);");
    check(!runtimeError.success && !runtimeError.diagnostics.empty(), "undefined variable is runtime error");
    check(runtimeError.diagnostics[0].message.find("Undefined variable") != std::string::npos, "undefined variable message");
    const auto invalidAtStart = interpreter.execute("@;");
    check(!invalidAtStart.success && !invalidAtStart.diagnostics.empty(), "invalid first character is diagnosed");
    const auto divisionError = interpreter.execute("print(10 / 0);");
    check(!divisionError.success && divisionError.diagnostics[0].message == "Division by zero.", "division by zero");
}
}
int main() {
    testLexer(); testArithmeticAndVariables(); testPersistentEnvironmentAndAssignment();
    testStringsBooleansAndShortCircuit(); testNativeFunctionAllowlist(); testDiagnostics();
    std::cout << "Argon interpreter tests passed.\n";
    return 0;
}
