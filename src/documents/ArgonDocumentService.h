#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class ArgonDocumentService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString argonDirectory READ argonDirectory CONSTANT)

public:
    explicit ArgonDocumentService(QObject *parent = nullptr);

    QString argonDirectory() const;

    // Converts one local file into the managed Argon Files folder.
    Q_INVOKABLE QVariantMap convertFile(const QString &sourcePath,
                                        bool retainOriginal = true);

    // Validates a .agn file before returning metadata.
    Q_INVOKABLE QVariantMap inspectFile(const QString &argonPath) const;
    Q_INVOKABLE QString readTextContent(const QString &argonPath) const;
    Q_INVOKABLE QVariantList listDocuments() const;
};
