#pragma once
#include <cstddef>
#include <string>
namespace Argon::Scripting {
struct Diagnostic {
    std::size_t line = 1;
    std::size_t column = 1;
    std::string message;
    [[nodiscard]] std::string toString() const {
        return "[line " + std::to_string(line) + ", column " + std::to_string(column) + "] " + message;
    }
};
} // namespace Argon::Scripting
