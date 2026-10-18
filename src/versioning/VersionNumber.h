#pragma once

#include <compare>
#include <optional>

#include <QString>
#include <QtGlobal>

// Strict MAJOR.MINOR.PATCH version number.
// Components are parsed and compared numerically, never as strings.
class VersionNumber final
{
public:
    VersionNumber(quint64 major, quint64 minor, quint64 patch) noexcept;

    static std::optional<VersionNumber> parse(
        const QString &text,
        QString *errorMessage = nullptr);

    quint64 major() const noexcept;
    quint64 minor() const noexcept;
    quint64 patch() const noexcept;

    QString toString() const;
    bool isNewerThan(const VersionNumber &other) const noexcept;
    std::strong_ordering operator<=>(const VersionNumber &other) const noexcept;
    bool operator==(const VersionNumber &other) const noexcept = default;

private:
    quint64 m_major;
    quint64 m_minor;
    quint64 m_patch;
};
