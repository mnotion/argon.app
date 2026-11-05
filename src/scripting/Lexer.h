#pragma once

#include "Token.h"

#include <string_view>
#include <vector>

namespace Argon::Scripting {

class Lexer final {
public:
    explicit Lexer(std::string_view source);

    [[nodiscard]] std::vector<Token> tokenize();

private:
    [[nodiscard]] Token scanToken();
    [[nodiscard]] Token makeToken(TokenKind kind) const;
    [[nodiscard]] Token scanIdentifier();
    [[nodiscard]] Token scanNumber();
    [[nodiscard]] Token scanString();
    [[nodiscard]] bool match(char expected);
    [[nodiscard]] char peek() const;
    [[nodiscard]] char peekNext() const;
    [[nodiscard]] char advance();
    [[nodiscard]] bool atEnd() const;
    void skipWhitespace();

    std::string_view m_source;
    std::size_t m_start = 0;
    std::size_t m_current = 0;
    std::size_t m_line = 1;
    std::size_t m_column = 1;
    std::size_t m_startLine = 1;
    std::size_t m_startColumn = 1;
};

} // namespace Argon::Scripting
