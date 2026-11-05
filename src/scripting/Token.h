#pragma once

#include <cstddef>
#include <string>

namespace Argon::Scripting {

enum class TokenKind {
    EndOfFile,
    Identifier,
    Number,
    String,

    Let,
    True,
    False,
    Null,

    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Comma,
    Semicolon,

    Plus,
    Minus,
    Star,
    Slash,
    Percent,

    Equal,
    EqualEqual,
    Bang,
    BangEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,

    AndAnd,
    OrOr,

    Invalid
};

struct Token {
    TokenKind kind = TokenKind::Invalid;
    std::string lexeme;
    std::size_t line = 1;
    std::size_t column = 1;
};

} // namespace Argon::Scripting
