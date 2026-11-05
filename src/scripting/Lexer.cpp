#include "Lexer.h"
#include <cctype>
#include <utility>
namespace Argon::Scripting {
Lexer::Lexer(std::string_view source) : m_source(source) {}
std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;
    while (true) {
        Token token = scanToken();
        const bool finished = token.kind == TokenKind::EndOfFile;
        tokens.push_back(std::move(token));
        if (finished) break;
    }
    return tokens;
}
Token Lexer::scanToken() {
    skipWhitespaceAndComments();
    m_start = m_current; m_startLine = m_line; m_startColumn = m_column;
    if (atEnd()) return makeToken(TokenKind::EndOfFile);
    const char c = advance();
    switch (c) {
    case '(': return makeToken(TokenKind::LeftParen);
    case ')': return makeToken(TokenKind::RightParen);
    case '{': return makeToken(TokenKind::LeftBrace);
    case '}': return makeToken(TokenKind::RightBrace);
    case ',': return makeToken(TokenKind::Comma);
    case ';': return makeToken(TokenKind::Semicolon);
    case '+': return makeToken(TokenKind::Plus);
    case '-': return makeToken(TokenKind::Minus);
    case '*': return makeToken(TokenKind::Star);
    case '/': return makeToken(TokenKind::Slash);
    case '%': return makeToken(TokenKind::Percent);
    case '!': return makeToken(match('=') ? TokenKind::BangEqual : TokenKind::Bang);
    case '=': return makeToken(match('=') ? TokenKind::EqualEqual : TokenKind::Equal);
    case '<': return makeToken(match('=') ? TokenKind::LessEqual : TokenKind::Less);
    case '>': return makeToken(match('=') ? TokenKind::GreaterEqual : TokenKind::Greater);
    case '&': return match('&') ? makeToken(TokenKind::AndAnd) : makeToken(TokenKind::Invalid);
    case '|': return match('|') ? makeToken(TokenKind::OrOr) : makeToken(TokenKind::Invalid);
    case '"': return scanString();
    default:
        if (std::isdigit(static_cast<unsigned char>(c))) return scanNumber();
        if (std::isalpha(static_cast<unsigned char>(c)) || c == '_') return scanIdentifier();
        return makeToken(TokenKind::Invalid);
    }
}
Token Lexer::scanIdentifier() {
    while (std::isalnum(static_cast<unsigned char>(peek())) || peek() == '_') (void)advance();
    const std::string word(m_source.substr(m_start, m_current - m_start));
    TokenKind kind = TokenKind::Identifier;
    if (word == "let") kind = TokenKind::Let;
    else if (word == "true") kind = TokenKind::True;
    else if (word == "false") kind = TokenKind::False;
    else if (word == "null") kind = TokenKind::Null;
    return makeToken(kind);
}
Token Lexer::scanNumber() {
    while (std::isdigit(static_cast<unsigned char>(peek()))) (void)advance();
    if (peek() == '.' && std::isdigit(static_cast<unsigned char>(peekNext()))) {
        (void)advance();
        while (std::isdigit(static_cast<unsigned char>(peek()))) (void)advance();
    }
    return makeToken(TokenKind::Number);
}
Token Lexer::scanString() {
    while (!atEnd() && peek() != '"') {
        if (peek() == '\\') {
            (void)advance();
            if (atEnd()) return makeToken(TokenKind::Invalid);
            (void)advance();
        } else (void)advance();
    }
    if (atEnd()) return makeToken(TokenKind::Invalid);
    (void)advance();
    return makeToken(TokenKind::String);
}
Token Lexer::makeToken(TokenKind kind) const {
    return Token{kind, std::string(m_source.substr(m_start, m_current - m_start)), m_startLine, m_startColumn};
}
bool Lexer::match(char expected) {
    if (atEnd() || m_source[m_current] != expected) return false;
    (void)advance(); return true;
}
char Lexer::peek() const { return atEnd() ? '\0' : m_source[m_current]; }
char Lexer::peekNext() const { return m_current + 1 >= m_source.size() ? '\0' : m_source[m_current + 1]; }
char Lexer::advance() {
    const char c = m_source[m_current++];
    if (c == '\n') { ++m_line; m_column = 1; } else { ++m_column; }
    return c;
}
bool Lexer::atEnd() const { return m_current >= m_source.size(); }
void Lexer::skipWhitespaceAndComments() {
    while (!atEnd()) {
        const char c = peek();
        if (c == ' ' || c == '\r' || c == '\t' || c == '\n') { (void)advance(); continue; }
        if (c == '/' && peekNext() == '/') {
            while (!atEnd() && peek() != '\n') (void)advance();
            continue;
        }
        break;
    }
}
} // namespace Argon::Scripting
