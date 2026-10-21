#include "UserSettingsService.h"

#include "AppPaths.h"

#include <QUuid>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSaveFile>
#include <QDebug>

UserSettingsService::UserSettingsService(QObject *parent)
    : QObject(parent)
{
    m_filePath = QDir(ArgonPaths::settingsDirectory()).filePath(
        QStringLiteral("app-settings.json"));
    qInfo().noquote() << "[Settings] Persistent settings file:" << m_filePath;
    load();
}

QVariant UserSettingsService::value(const QString &key,
                                    const QVariant &fallback) const
{
    const auto it = m_values.constFind(key);
    return it == m_values.cend() ? fallback : it.value();
}

bool UserSettingsService::setValue(const QString &key, const QVariant &value)
{
    const QString normalizedKey = key.trimmed();
    if (normalizedKey.isEmpty() || !m_writeAllowed)
        return false;

    const auto oldValue = m_values.constFind(normalizedKey);
    const bool existed = oldValue != m_values.cend();
    const QVariant previous = existed ? oldValue.value() : QVariant();
    if (existed && previous == value)
        return true;

    m_values.insert(normalizedKey, value);
    if (save())
        return true;

    if (existed)
        m_values.insert(normalizedKey, previous);
    else
        m_values.remove(normalizedKey);
    return false;
}

bool UserSettingsService::sync()
{
    return m_writeAllowed && save();
}

bool UserSettingsService::load()
{
    QFile file(m_filePath);
    if (!file.exists())
        return true;
    if (!file.open(QIODevice::ReadOnly)) {
        m_writeAllowed = false;
        qWarning().noquote() << "[Settings] Could not read" << m_filePath
                             << ":" << file.errorString();
        return false;
    }

    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        file.close();
        return preserveInvalidFile();
    }

    const QJsonObject root = document.object();
    const QJsonValue values = root.value(QStringLiteral("values"));
    if (!values.isObject()) {
        file.close();
        return preserveInvalidFile();
    }

    m_values = values.toObject().toVariantMap();
    return true;
}

bool UserSettingsService::preserveInvalidFile()
{
    // Never replace the original unless a separate recovery copy was created.
    const QString backupPath = m_filePath + QStringLiteral(".corrupt-")
        + QUuid::createUuid().toString(QUuid::WithoutBraces);
    if (!QFile::copy(m_filePath, backupPath)) {
        m_writeAllowed = false;
        qWarning().noquote() << "[Settings] Could not preserve invalid settings file:"
                             << m_filePath;
        return false;
    }
    qWarning().noquote() << "[Settings] Invalid settings file preserved at"
                         << backupPath;
    return true;
}

bool UserSettingsService::save() const
{
    if (!m_writeAllowed)
        return false;

    const QFileInfo fileInfo(m_filePath);
    if (!QDir().mkpath(fileInfo.absolutePath())) {
        qWarning().noquote() << "[Settings] Could not create settings directory:"
                             << fileInfo.absolutePath();
        return false;
    }

    QJsonObject root;
    root.insert(QStringLiteral("schemaVersion"), 1);
    root.insert(QStringLiteral("values"), QJsonObject::fromVariantMap(m_values));
    const QByteArray bytes = QJsonDocument(root).toJson(QJsonDocument::Indented);

    QSaveFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning().noquote() << "[Settings] Could not write" << m_filePath
                             << ":" << file.errorString();
        return false;
    }
    if (file.write(bytes) != bytes.size()) {
        qWarning().noquote() << "[Settings] Could not write complete settings file:"
                             << m_filePath << ":" << file.errorString();
        file.cancelWriting();
        return false;
    }
    if (!file.commit()) {
        qWarning().noquote() << "[Settings] Could not commit settings file:"
                             << m_filePath << ":" << file.errorString();
        return false;
    }
    return true;
}
