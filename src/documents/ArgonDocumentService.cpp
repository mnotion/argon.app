#include "ArgonDocumentService.h"

#include "ArgonDocument.h"
#include "../app/AppPaths.h"

#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <QDebug>

ArgonDocumentService::ArgonDocumentService(QObject *parent)
    : QObject(parent)
{
    QString error;
    if (!ArgonPaths::ensureDirectoryStructure(&error) && !error.isEmpty())
        qWarning().noquote() << error;
}

QString ArgonDocumentService::argonDirectory() const
{
    return QDir::cleanPath(ArgonPaths::argonFilesDirectory());
}

QVariantMap ArgonDocumentService::convertFile(const QString &sourcePath,
                                               bool retainOriginal)
{
    QVariantMap response;
    const QFileInfo sourceInfo(sourcePath);
    if (sourceInfo.suffix().compare(QStringLiteral("agn"), Qt::CaseInsensitive) == 0
        || ArgonDocument::isDocumentFile(sourcePath)) {
        response.insert(QStringLiteral("success"), false);
        response.insert(QStringLiteral("error"),
                        QStringLiteral("The source is already an Argon .agn document."));
        return response;
    }

    const QString outputDirectory = argonDirectory();
    if (!QDir().mkpath(outputDirectory)) {
        response.insert(QStringLiteral("success"), false);
        response.insert(QStringLiteral("error"), QStringLiteral("Could not create the Argon Files folder."));
        return response;
    }

    QString baseName = sourceInfo.completeBaseName().trimmed();
    if (baseName.isEmpty())
        baseName = QStringLiteral("Untitled");

    QString outputPath = QDir(outputDirectory).filePath(baseName + QStringLiteral(".agn"));
    for (int suffix = 2; QFileInfo::exists(outputPath); ++suffix) {
        outputPath = QDir(outputDirectory).filePath(
            baseName + QStringLiteral(" (") + QString::number(suffix) + QStringLiteral(").agn"));
    }

    QVariantMap summary;
    QString error;
    if (!ArgonDocument::convertFile(sourcePath, outputPath, retainOriginal, &summary, &error)) {
        response.insert(QStringLiteral("success"), false);
        response.insert(QStringLiteral("error"), error);
        return response;
    }

    response.insert(QStringLiteral("success"), true);
    response.insert(QStringLiteral("path"), outputPath);
    response.insert(QStringLiteral("fileUrl"), QUrl::fromLocalFile(outputPath).toString());
    response.insert(QStringLiteral("summary"), summary);
    return response;
}

QVariantMap ArgonDocumentService::inspectFile(const QString &argonPath) const
{
    QVariantMap response;
    ArgonDocumentData document;
    QString error;
    if (!ArgonDocument::readFile(argonPath, document, &error)) {
        response.insert(QStringLiteral("success"), false);
        response.insert(QStringLiteral("error"), error);
        return response;
    }

    response.insert(QStringLiteral("success"), true);
    response.insert(QStringLiteral("metadata"), document.metadata);
    response.insert(QStringLiteral("hasText"), document.hasText);
    response.insert(QStringLiteral("hasOriginal"), document.hasOriginal);
    response.insert(QStringLiteral("textLength"), document.textContent.size());
    response.insert(QStringLiteral("originalBytes"), document.originalData.size());
    return response;
}

QString ArgonDocumentService::readTextContent(const QString &argonPath) const
{
    ArgonDocumentData document;
    if (!ArgonDocument::readFile(argonPath, document, nullptr) || !document.hasText)
        return {};
    return document.textContent;
}

QVariantList ArgonDocumentService::listDocuments() const
{
    QVariantList documents;
    const QDir directory(argonDirectory());
    const QFileInfoList files = directory.entryInfoList(
        QStringList{QStringLiteral("*.agn")},
        QDir::Files | QDir::NoDotAndDotDot,
        QDir::Name);
    for (const QFileInfo &file : files) {
        if (file.isSymLink())
            continue;
        QVariantMap item;
        item.insert(QStringLiteral("name"), file.fileName());
        item.insert(QStringLiteral("path"), file.absoluteFilePath());
        item.insert(QStringLiteral("fileUrl"), QUrl::fromLocalFile(file.absoluteFilePath()).toString());
        item.insert(QStringLiteral("size"), file.size());
        item.insert(QStringLiteral("modified"), file.lastModified().toString(Qt::ISODate));
        documents.append(item);
    }
    return documents;
}
