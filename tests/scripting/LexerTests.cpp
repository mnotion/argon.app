#include "Lexer.h"

#include <cassert>
#include <iostream>

using Argon::Scripting::Lexer;
using Argon::Scripting::TokenKind;

int main()
{
    Lexer lexer("let answer = 42;\nanswer >= 10 && true");
    const auto tokens = lexer.tokenize();

    assert(tokens.size() == 11);
    assert(tokens[0].kind == TokenKind::Let);
    assert(tokens[1].kind == TokenKind::Identifier);
    assert(tokens[2].kind == TokenKind::Equal);
    assert(tokens[3].kind == TokenKind::Number);
    assert(tokens[4].kind == TokenKind::Semicolon);
    assert(tokens[5].kind == TokenKind::Identifier);
    assert(tokens[6].kind == TokenKind::GreaterEqual);
    assert(tokens[7].kind == TokenKind::Number);
    assert(tokens[8].kind == TokenKind::AndAnd);\n    assert(tokens[9].kind == TokenKind::True);\n    assert(tokens[10].kind == TokenKind::EndOfFile);

    Lexer strings("\"hello world\"");
    const auto stringTokens = strings.tokenize();
    assert(stringTokens.front().kind == TokenKind::String);
    assert(stringTokens.front().lexeme == "\"hello world\"");

    std::cout << "Argon lexer tests passed.\n";
    return 0;
}
