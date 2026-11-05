#pragma once
#include "AST.h"
#include "Diagnostic.h"
#include "Token.h"
#include <initializer_list>
#include <vector>
namespace Argon::Scripting {
struct ParseResult {
    std::vector<StmtPtr> statements;
    std::vector<Diagnostic> diagnostics;
    [[nodiscard]] bool ok() const { return diagnostics.empty(); }
};
class Parser final {
public:
    explicit Parser(std::vector<Token> tokens);
    [[nodiscard]] ParseResult parse();
private:
    struct ParseError {};
    [[nodiscard]] StmtPtr declaration();
    [[nodiscard]] StmtPtr variableDeclaration();
    [[nodiscard]] StmtPtr expressionStatement();
    [[nodiscard]] ExprPtr expression();
    [[nodiscard]] ExprPtr assignment();
    [[nodiscard]] ExprPtr logicalOr();
    [[nodiscard]] ExprPtr logicalAnd();
    [[nodiscard]] ExprPtr equality();
    [[nodiscard]] ExprPtr comparison();
    [[nodiscard]] ExprPtr term();
    [[nodiscard]] ExprPtr factor();
    [[nodiscard]] ExprPtr unary();
    [[nodiscard]] ExprPtr call();
    [[nodiscard]] ExprPtr finishCall(ExprPtr callee);
    [[nodiscard]] ExprPtr primary();
    [[nodiscard]] bool match(std::initializer_list<TokenKind> kinds);
    [[nodiscard]] bool check(TokenKind kind) const;
    const Token &advance();
    [[nodiscard]] bool atEnd() const;
    [[nodiscard]] const Token &peek() const;
    [[nodiscard]] const Token &previous() const;
    const Token &consume(TokenKind kind, const char *message);
    [[noreturn]] void fail(const Token &token, const std::string &message);
    void synchronize();
    std::vector<Token> m_tokens;
    std::size_t m_current = 0;
    std::vector<Diagnostic> m_diagnostics;
};
} // namespace Argon::Scripting
