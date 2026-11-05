#pragma once

#include <QByteArray>
#include <QString>
#include <QVariantMap>

struct ArgonDocumentData
{
    QVariantMap metadata;
    QString textContent;
    QByteArray originalData;
    bool hasText = false;
    bool hasOriginal = false;
};

class ArgonDocument final
{
public:
    // Writes a versioned .agn file atomically. The source file is never modified.
    static bool convertFile(const QString &sourcePath,
                            const QString &outputPath,
                            bool retainOriginal,
                            QVariantMap *summary = nullptr,
                            QString *errorMessage = nullptr);

    // Validates the container, decompresses its sections, and verifies SHA-256 hashes.
    static bool readFile(const QString &argonPath,
                         ArgonDocumentData &document,
                         QString *errorMessage = nullptr);

    static bool isDocumentFile(const QString &path);
};
