#include "../../src/documents/ArgonDocument.h"

#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QDebug>

#include <cstdlib>

void verify(bool condition)
{
    if (!condition)
        std::abort();
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QTemporaryDir directory;
    verify(directory.isValid());

    const QString sourcePath = directory.filePath(QStringLiteral("sample.md"));
    const QString argonPath = directory.filePath(QStringLiteral("sample.agn"));
    const QByteArray original = QByteArrayLiteral("# Heading\r\nLine two\r\n");
    {
        QFile source(sourcePath);
        verify(source.open(QIODevice::WriteOnly));
        verify(source.write(original) == original.size());
    }

    QString error;
    QVariantMap summary;
    verify(ArgonDocument::convertFile(sourcePath, argonPath, true, &summary, &error));
    verify(QFileInfo::exists(argonPath));
    verify(summary.value(QStringLiteral("isText")).toBool());
    verify(summary.value(QStringLiteral("originalRetained")).toBool());

    ArgonDocumentData document;
    verify(ArgonDocument::readFile(argonPath, document, &error));
    verify(document.hasText);
    verify(document.hasOriginal);
    verify(document.textContent == QStringLiteral("# Heading\nLine two\n"));
    verify(document.originalData == original);

    const QString compactPath = directory.filePath(QStringLiteral("compact.agn"));
    verify(ArgonDocument::convertFile(sourcePath, compactPath, false, nullptr, &error));
    verify(ArgonDocument::readFile(compactPath, document, &error));
    verify(document.hasText);
    verify(!document.hasOriginal);
    verify(document.originalData.isEmpty());

    const QString binaryPath = directory.filePath(QStringLiteral("image.bin"));
    const QByteArray binaryBytes("\0\1\2\xFF", 4);
    {
        QFile binary(binaryPath);
        verify(binary.open(QIODevice::WriteOnly));
        verify(binary.write(binaryBytes) == binaryBytes.size());
    }
    verify(!ArgonDocument::convertFile(binaryPath,
                                       directory.filePath(QStringLiteral("lossy.agn")),
                                       false, nullptr, &error));

    const QString opaquePath = directory.filePath(QStringLiteral("image.agn"));
    verify(ArgonDocument::convertFile(binaryPath, opaquePath, true, nullptr, &error));
    verify(ArgonDocument::readFile(opaquePath, document, &error));
    verify(!document.hasText);
    verify(document.hasOriginal);
    verify(document.originalData == binaryBytes);

    // Trailing bytes are rejected, rather than silently ignored.
    {
        QFile corrupted(argonPath);
        verify(corrupted.open(QIODevice::Append));
        verify(corrupted.write("x", 1) == 1);
    }
    verify(!ArgonDocument::readFile(argonPath, document, &error));

    qInfo() << "Argon document format tests passed.";
    return 0;
}
