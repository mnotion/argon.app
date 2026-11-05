#include "../../src/documents/ArgonDocument.h"

#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QDebug>

#include <cassert>

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QTemporaryDir directory;
    assert(directory.isValid());

    const QString sourcePath = directory.filePath(QStringLiteral("sample.md"));
    const QString argonPath = directory.filePath(QStringLiteral("sample.agn"));
    const QByteArray original = QByteArrayLiteral("# Heading\r\nLine two\r\n");
    {
        QFile source(sourcePath);
        assert(source.open(QIODevice::WriteOnly));
        assert(source.write(original) == original.size());
    }

    QString error;
    QVariantMap summary;
    assert(ArgonDocument::convertFile(sourcePath, argonPath, true, &summary, &error));
    assert(QFileInfo::exists(argonPath));
    assert(summary.value(QStringLiteral("isText")).toBool());
    assert(summary.value(QStringLiteral("originalRetained")).toBool());

    ArgonDocumentData document;
    assert(ArgonDocument::readFile(argonPath, document, &error));
    assert(document.hasText);
    assert(document.hasOriginal);
    assert(document.textContent == QStringLiteral("# Heading\nLine two\n"));
    assert(document.originalData == original);

    const QString compactPath = directory.filePath(QStringLiteral("compact.agn"));
    assert(ArgonDocument::convertFile(sourcePath, compactPath, false, nullptr, &error));
    assert(ArgonDocument::readFile(compactPath, document, &error));
    assert(document.hasText);
    assert(!document.hasOriginal);
    assert(document.originalData.isEmpty());

    const QString binaryPath = directory.filePath(QStringLiteral("image.bin"));
    const QByteArray binaryBytes("\0\1\2\xFF", 4);
    {
        QFile binary(binaryPath);
        assert(binary.open(QIODevice::WriteOnly));
        assert(binary.write(binaryBytes) == binaryBytes.size());
    }
    assert(!ArgonDocument::convertFile(binaryPath,
                                       directory.filePath(QStringLiteral("lossy.agn")),
                                       false, nullptr, &error));

    const QString opaquePath = directory.filePath(QStringLiteral("image.agn"));
    assert(ArgonDocument::convertFile(binaryPath, opaquePath, true, nullptr, &error));
    assert(ArgonDocument::readFile(opaquePath, document, &error));
    assert(!document.hasText);
    assert(document.hasOriginal);
    assert(document.originalData == binaryBytes);

    // Trailing bytes are rejected, rather than silently ignored.
    {
        QFile corrupted(argonPath);
        assert(corrupted.open(QIODevice::Append));
        assert(corrupted.write("x", 1) == 1);
    }
    assert(!ArgonDocument::readFile(argonPath, document, &error));

    qInfo() << "Argon document format tests passed.";
    return 0;
}
