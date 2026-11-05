#include "Parser.h"
#include <string>
namespace Argon::Scripting {
namespace {
std::string decodeString(const std::string &lexeme) {
    std::string result;
    if (lexeme.size() < 2) return result;
    result.reserve(lexeme.size() - 2);
    for (std::size_t i = 1; i + 1 < lexeme.size(); ++i) {
        const char c = lexeme[i];
        if (c == '\\' && i + 2 < lexeme.size()) {
            const char escaped = lexeme[++i];
            switch (escaped) {
            case 'n': result.push_back('\n'); break;
            case 'r': result.push_back('\r'); break;
            case 't': result.push_back('\t'); break;
            case '"': result.push_back('"'); break;
            case '\\': result.push_back('\\'); break;
            default: result.push_back(escaped); break;
            }
        } else result.push_back(c);
    }
    return result;
}
}
Parser::Parser(std::vector<Token> tokens) : m_tokens(std::move(tokens)) {
    if (m_tokens.empty() || m_tokens.back().kind != TokenKind::EndOfFile)
        m_tokens.push_back(Token{TokenKind::EndOfFile, "", 1, 1});
}
ParseResult Parser::parse() {
    std::vector<StmtPtr> statements;
    while (!atEnd()) {
        try { statements.push_back(declaration()); }
        catch (const ParseError &) { synchronize(); }
    }
    return ParseResult{std::move(statements), std::move(m_diagnostics)};
}
StmtPtr Parser::declaration() {
    if (match({TokenKind::Let})) return variableDeclaration();
    return expressionStatement();
}
StmtPtr Parser::variableDeclaration() {
    const Token name = consume(TokenKind::Identifier, "Expected a variable name after 'let'.");
    consume(TokenKind::Equal, "Expected '=' after the variable name.");
    auto initializer = expression();
    consume(TokenKind::Semicolon, "Expected ';' after the variable declaration.");
    auto statement = std::make_unique<Stmt>(Stmt::Kind::VariableDeclaration, name);
    statement->name = name.lexeme;
    statement->expression = std::move(initializer);
    return statement;
}
StmtPtr Parser::expressionStatement() {
    const Token start = peek();
    auto value = expression();
    consume(TokenKind::Semicolon, "Expected ';' after the expression.");
    auto statement = std::make_unique<Stmt>(Stmt::Kind::Expression, start);
    statement->expression = std::move(value);
    return statement;
}
ExprPtr Parser::expression() { return assignment(); }
ExprPtr Parser::assignment() {
    auto value = logicalOr();
    if (match({TokenKind::Equal})) {
        const Token equals = previous();
        auto right = assignment();
        if (value->kind != Expr::Kind::Variable) fail(equals, "Invalid assignment target.");
        auto result = std::make_unique<Expr>(Expr::Kind::Assign, equals);
        result->name = value->name;
        result->right = std::move(right);
        return result;
    }
    return value;
}
ExprPtr Parser::logicalOr() {
    auto value = logicalAnd();
    while (match({TokenKind::OrOr})) {
        const Token op = previous(); auto right = logicalAnd();
        auto node = std::make_unique<Expr>(Expr::Kind::Binary, op);
        node->left = std::move(value); node->right = std::move(right); value = std::move(node);
    }
    return value;
}
ExprPtr Parser::logicalAnd() {
    auto value = equality();
    while (match({TokenKind::AndAnd})) {
        const Token op = previous(); auto right = equality();
        auto node = std::make_unique<Expr>(Expr::Kind::Binary, op);
        node->left = std::move(value); node->right = std::move(right); value = std::move(node);
    }
    return value;
}
ExprPtr Parser::equality() {
    auto value = comparison();
    while (match({TokenKind::BangEqual, TokenKind::EqualEqual})) {
        const Token op = previous(); auto right = comparison();
        auto node = std::make_unique<Expr>(Expr::Kind::Binary, op);
        node->left = std::move(value); node->right = std::move(right); value = std::move(node);
    }
    return value;
}
ExprPtr Parser::comparison() {
    auto value = term();
    while (match({TokenKind::Greater, TokenKind::GreaterEqual, TokenKind::Less, TokenKind::LessEqual})) {
        const Token op = previous(); auto right = term();
        auto node = std::make_unique<Expr>(Expr::Kind::Binary, op);
        node->left = std::move(value); node->right = std::move(right); value = std::move(node);
    }
    return value;
}
ExprPtr Parser::term() {
    auto value = factor();
    while (match({TokenKind::Minus, TokenKind::Plus})) {
        const Token op = previous(); auto right = factor();
        auto node = std::make_unique<Expr>(Expr::Kind::Binary, op);
        node->left = std::move(value); node->right = std::move(right); value = std::move(node);
    }
    return value;
}
ExprPtr Parser::factor() {
    auto value = unary();
    while (match({TokenKind::Slash, TokenKind::Star, TokenKind::Percent})) {
        const Token op = previous(); auto right = unary();
        auto node = std::make_unique<Expr>(Expr::Kind::Binary, op);
        node->left = std::move(value); node->right = std::move(right); value = std::move(node);
    }
    return value;
}
ExprPtr Parser::unary() {
    if (match({TokenKind::Bang, TokenKind::Minus})) {
        const Token op = previous(); auto right = unary();
        auto node = std::make_unique<Expr>(Expr::Kind::Unary, op);
        node->right = std::move(right); return node;
    }
    return call();
}
ExprPtr Parser::call() {
    auto value = primary();
    while (match({TokenKind::LeftParen})) value = finishCall(std::move(value));
    return value;
}
ExprPtr Parser::finishCall(ExprPtr callee) {
    if (callee->kind != Expr::Kind::Variable) fail(callee->token, "Only named functions can be called.");
    std::vector<ExprPtr> arguments;
    if (!check(TokenKind::RightParen)) {
        do {
            if (arguments.size() >= 32) fail(peek(), "A function call cannot have more than 32 arguments.");
            arguments.push_back(expression());
        } while (match({TokenKind::Comma}));
    }
    const Token closing = consume(TokenKind::RightParen, "Expected ')' after function arguments.");
    auto node = std::make_unique<Expr>(Expr::Kind::Call, closing);
    node->name = callee->name;
    node->arguments = std::move(arguments);
    return node;
}
ExprPtr Parser::primary() {
    if (match({TokenKind::False})) {
        auto node = std::make_unique<Expr>(Expr::Kind::Literal, previous()); node->literal = Value(false); return node;
    }
    if (match({TokenKind::True})) {
        auto node = std::make_unique<Expr>(Expr::Kind::Literal, previous()); node->literal = Value(true); return node;
    }
    if (match({TokenKind::Null})) return std::make_unique<Expr>(Expr::Kind::Literal, previous());
    if (match({TokenKind::Number})) {
        const Token number = previous();
        try { auto node = std::make_unique<Expr>(Expr::Kind::Literal, number); node->literal = Value(std::stod(number.lexeme)); return node; }
        catch (...) { fail(number, "Invalid numeric literal."); }
    }
    if (match({TokenKind::String})) {
        const Token string = previous();
        if (string.lexeme.size() < 2 || string.lexeme.back() != '"') fail(string, "Unterminated string literal.");
        auto node = std::make_unique<Expr>(Expr::Kind::Literal, string);
        node->literal = Value(decodeString(string.lexeme)); return node;
    }
    if (match({TokenKind::Identifier})) {
        auto node = std::make_unique<Expr>(Expr::Kind::Variable, previous()); node->name = previous().lexeme; return node;
    }
    if (match({TokenKind::LeftParen})) {
        auto node = expression(); consume(TokenKind::RightParen, "Expected ')' after the expression."); return node;
    }
    if (check(TokenKind::Invalid)) {
        const Token invalid = peek();
        if (!invalid.lexeme.empty() && invalid.lexeme.front() == '"') fail(invalid, "Unterminated string literal.");
        fail(invalid, "Invalid character '" + invalid.lexeme + "'.");
    }
    fail(peek(), "Expected an expression.");
}
bool Parser::match(std::initializer_list<TokenKind> kinds) {
    for (const auto kind : kinds) if (check(kind)) { advance(); return true; }
    return false;
}
bool Parser::check(TokenKind kind) const { return atEnd() ? kind == TokenKind::EndOfFile : peek().kind == kind; }
const Token &Parser::advance() { if (!atEnd()) ++m_current; return previous(); }
bool Parser::atEnd() const { return peek().kind == TokenKind::EndOfFile; }
const Token &Parser::peek() const { return m_tokens[m_current]; }
const Token &Parser::previous() const { return m_tokens[m_current - 1]; }
const Token &Parser::consume(TokenKind kind, const char *message) { if (check(kind)) return advance(); fail(peek(), message); }
[[noreturn]] void Parser::fail(const Token &token, const std::string &message) {
    m_diagnostics.push_back(Diagnostic{token.line, token.column, message}); throw ParseError{};
}
void Parser::synchronize() {
    if (!atEnd() && (m_current == 0 || previous().kind != TokenKind::Semicolon)) advance();
    while (!atEnd()) {
        if (previous().kind == TokenKind::Semicolon || peek().kind == TokenKind::Let) return;
        advance();
    }
}
} // namespace Argon::Scripting
