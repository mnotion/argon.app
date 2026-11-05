#pragma once
#include <string>
#include <utility>
#include <variant>
namespace Argon::Scripting {
class Value final {
public:
    using Storage = std::variant<std::monostate, double, bool, std::string>;
    Value() = default;
    Value(double value) : m_storage(value) {}
    Value(bool value) : m_storage(value) {}
    Value(std::string value) : m_storage(std::move(value)) {}
    Value(const char *value) : m_storage(std::string(value)) {}
    [[nodiscard]] bool isNull() const { return std::holds_alternative<std::monostate>(m_storage); }
    [[nodiscard]] bool isNumber() const { return std::holds_alternative<double>(m_storage); }
    [[nodiscard]] bool isBoolean() const { return std::holds_alternative<bool>(m_storage); }
    [[nodiscard]] bool isString() const { return std::holds_alternative<std::string>(m_storage); }
    [[nodiscard]] double asNumber() const { return std::get<double>(m_storage); }
    [[nodiscard]] bool asBoolean() const { return std::get<bool>(m_storage); }
    [[nodiscard]] const std::string &asString() const { return std::get<std::string>(m_storage); }
    [[nodiscard]] const Storage &storage() const { return m_storage; }
    [[nodiscard]] std::string toString() const;
    [[nodiscard]] bool operator==(const Value &other) const { return m_storage == other.m_storage; }
private:
    Storage m_storage;
};
} // namespace Argon::Scripting
