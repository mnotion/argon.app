#pragma once

#include <QObject>
#include <QVariant>
#include <QVariantMap>

class UserSettingsService final : public QObject
{
    Q_OBJECT

public:
    explicit UserSettingsService(QObject *parent = nullptr);

    Q_INVOKABLE QVariant value(const QString &key,
                               const QVariant &fallback = QVariant()) const;
    Q_INVOKABLE bool setValue(const QString &key, const QVariant &value);
    Q_INVOKABLE bool sync();

private:
    bool load();
    bool preserveInvalidFile();
    bool save() const;

    QString m_filePath;
    QVariantMap m_values;
    bool m_writeAllowed = true;
};
