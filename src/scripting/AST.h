#pragma once
#include "Token.h"
#include "Value.h"
#include <memory>
#include <string>
#include <utility>
#include <vector>
namespace Argon::Scripting {
struct Expr {
    enum class Kind { Literal, Variable, Assign, Unary, Binary, Call };
    explicit Expr(Kind expressionKind, Token sourceToken) : kind(expressionKind), token(std::move(sourceToken)) {}
    Kind kind;
    Token token;
    Value literal;
    std::string name;
    std::unique_ptr<Expr> left;
    std::unique_ptr<Expr> right;
    std::vector<std::unique_ptr<Expr>> arguments;
};
struct Stmt {
    enum class Kind { VariableDeclaration, Expression };
    explicit Stmt(Kind statementKind, Token sourceToken) : kind(statementKind), token(std::move(sourceToken)) {}
    Kind kind;
    Token token;
    std::string name;
    std::unique_ptr<Expr> expression;
};
using ExprPtr = std::unique_ptr<Expr>;
using StmtPtr = std::unique_ptr<Stmt>;
} // namespace Argon::Scripting
