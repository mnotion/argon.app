#include "VersionNumber.h"

#include <QRegularExpression>
#include <QRegularExpressionMatch>

namespace {
void assignError(QString *target, const QString &message)
{
    if (target)
        *target = message;
}
}

VersionNumber::VersionNumber(quint64 major, quint64 minor, quint64 patch) noexcept
    : m_major(major), m_minor(minor), m_patch(patch)
{
}

std::optional<VersionNumber> VersionNumber::parse(const QString &text, QString *errorMessage)
{
    static const QRegularExpression expression(
        QStringLiteral("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"));

    const QRegularExpressionMatch match = expression.match(text);
    if (!match.hasMatch()) {
        assignError(
            errorMessage,
            QStringLiteral("Version must use MAJOR.MINOR.PATCH, for example 1.2.3."));
        return std::nullopt;
    }

    bool majorOk = false;
    bool minorOk = false;
    bool patchOk = false;
    const quint64 major = match.captured(1).toULongLong(&majorOk);
    const quint64 minor = match.captured(2).toULongLong(&minorOk);
    const quint64 patch = match.captured(3).toULongLong(&patchOk);

    if (!majorOk || !minorOk || !patchOk) {
        assignError(errorMessage, QStringLiteral("Version component exceeds the supported numeric range."));
        return std::nullopt;
    }

    assignError(errorMessage, QString());
    return VersionNumber(major, minor, patch);
}

quint64 VersionNumber::major() const noexcept
{
    return m_major;
}

quint64 VersionNumber::minor() const noexcept
{
    return m_minor;
}

quint64 VersionNumber::patch() const noexcept
{
    return m_patch;
}

QString VersionNumber::toString() const
{
    return QStringLiteral("%1.%2.%3")
        .arg(m_major)
        .arg(m_minor)
        .arg(m_patch);
}

bool VersionNumber::isNewerThan(const VersionNumber &other) const noexcept
{
    return (*this <=> other) == std::strong_ordering::greater;
}

std::strong_ordering VersionNumber::operator<=>(const VersionNumber &other) const noexcept
{
    if (m_major < other.m_major)
        return std::strong_ordering::less;
    if (m_major > other.m_major)
        return std::strong_ordering::greater;

    if (m_minor < other.m_minor)
        return std::strong_ordering::less;
    if (m_minor > other.m_minor)
        return std::strong_ordering::greater;

    if (m_patch < other.m_patch)
        return std::strong_ordering::less;
    if (m_patch > other.m_patch)
        return std::strong_ordering::greater;

    return std::strong_ordering::equal;
}
