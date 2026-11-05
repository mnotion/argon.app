#include "ArgonDocument.h"

#include <QCryptographicHash>
#include <QDataStream>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMimeDatabase>
#include <QSaveFile>
#include <QSet>
#include <QUuid>
#include <QtEndian>
#include <QtGlobal>

namespace
{
constexpr char kMagic[] = "ARGONAGN";
constexpr qint64 kHeaderSize = 36;
constexpr quint16 kMajorVersion = 1;
constexpr quint16 kMinorVersion = 0;
constexpr quint32 kFlagOriginalRetained = 0x01;
constexpr quint32 kFlagTextRepresentation = 0x02;
constexpr quint32 kKnownFlags = kFlagOriginalRetained | kFlagTextRepresentation;
constexpr qint64 kMaxSourceBytes = 512LL * 1024LL * 1024LL;
constexpr qint64 kMaxContentBytes = 256LL * 1024LL * 1024LL;
constexpr quint32 kMaxMetadataBytes = 1024U * 1024U;

QString sha256Hex(const QByteArray &bytes)
{
    return QString::fromLatin1(
        QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
}

bool writeRaw(QDataStream &stream, const QByteArray &bytes)
{
    return bytes.isEmpty()
        || stream.writeRawData(bytes.constData(), bytes.size()) == bytes.size();
}

bool isTextExtension(const QString &extension)
{
    static const QSet<QString> extensions = {
        QStringLiteral("txt"), QStringLiteral("md"), QStringLiteral("markdown"),
        QStringLiteral("csv"), QStringLiteral("tsv"), QStringLiteral("json"),
        QStringLiteral("xml"), QStringLiteral("html"), QStringLiteral("htm"),
        QStringLiteral("log"), QStringLiteral("ini"), QStringLiteral("cfg"),
        QStringLiteral("yaml"), QStringLiteral("yml"), QStringLiteral("toml"),
        QStringLiteral("properties"), QStringLiteral("qml"), QStringLiteral("js"),
        QStringLiteral("mjs"), QStringLiteral("ts"), QStringLiteral("tsx"),
        QStringLiteral("css"), QStringLiteral("scss"), QStringLiteral("less"),
        QStringLiteral("c"), QStringLiteral("h"), QStringLiteral("cc"),
        QStringLiteral("cpp"), QStringLiteral("hpp"), QStringLiteral("cxx"),
        QStringLiteral("hh"), QStringLiteral("py"), QStringLiteral("java"),
        QStringLiteral("kt"), QStringLiteral("kts"), QStringLiteral("cs"),
        QStringLiteral("go"), QStringLiteral("rs"), QStringLiteral("rb"),
        QStringLiteral("php"), QStringLiteral("swift"), QStringLiteral("sql"),
        QStringLiteral("sh"), QStringLiteral("bash"), QStringLiteral("bat"),
        QStringLiteral("cmd"), QStringLiteral("ps1"), QStringLiteral("diff"),
        QStringLiteral("patch"), QStringLiteral("tex"), QStringLiteral("r"),
        QStringLiteral("lua"), QStringLiteral("pl"), QStringLiteral("dockerfile")
    };
    return extensions.contains(extension.toLower());
}

struct EncodedPayload
{
    QByteArray bytes;
    QString codec = QStringLiteral("none");
};

EncodedPayload encodePayload(const QByteArray &source)
{
    EncodedPayload result;
    result.bytes = source;
    if (source.isEmpty())
        return result;

    // qCompress includes its uncompressed length. Keep raw data whenever
    // compression would make it larger, which is common for compressed media.
    const QByteArray compressed = qCompress(source, 5);
    if (!compressed.isEmpty() && compressed.size() < source.size()) {
        result.bytes = compressed;
        result.codec = QStringLiteral("qcompress");
    }
    return result;
}

bool decodePayload(const QByteArray &stored,
                   const QString &codec,
                   qint64 maximumBytes,
                   QByteArray &decoded,
                   QString *errorMessage)
{
    if (codec == QStringLiteral("none")) {
        if (stored.size() > maximumBytes) {
            if (errorMessage) *errorMessage = QStringLiteral("A payload exceeds the supported size limit.");
            return false;
        }
        decoded = stored;
        return true;
    }

    if (codec != QStringLiteral("qcompress")) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn file uses an unknown payload codec.");
        return false;
    }

    if (stored.size() < 4) {
        if (errorMessage) *errorMessage = QStringLiteral("A compressed .agn payload is incomplete.");
        return false;
    }

    const quint32 expectedSize = qFromBigEndian<quint32>(
        reinterpret_cast<const uchar *>(stored.constData()));
    if (static_cast<quint64>(expectedSize) > static_cast<quint64>(maximumBytes)) {
        if (errorMessage) *errorMessage = QStringLiteral("A decompressed payload exceeds the supported size limit.");
        return false;
    }

    decoded = qUncompress(stored);
    if (decoded.size() != static_cast<qsizetype>(expectedSize)) {
        if (errorMessage) *errorMessage = QStringLiteral("A compressed .agn payload could not be decompressed.");
        return false;
    }
    return true;
}

bool writeDocument(const QString &outputPath,
                   const QJsonObject &metadata,
                   const QByteArray &contentBytes,
                   const QByteArray &originalBytes,
                   quint32 flags,
                   QString *errorMessage)
{
    const EncodedPayload content = encodePayload(contentBytes);
    const EncodedPayload original = encodePayload(originalBytes);
    if (content.bytes.size() > kMaxContentBytes || original.bytes.size() > kMaxSourceBytes) {
        if (errorMessage) *errorMessage = QStringLiteral("The encoded document exceeds the supported size limit.");
        return false;
    }

    QJsonObject encoding;
    encoding.insert(QStringLiteral("content"), content.codec);
    encoding.insert(QStringLiteral("original"), original.codec);
    QJsonObject completeMetadata = metadata;
    completeMetadata.insert(QStringLiteral("encoding"), encoding);

    const QByteArray metadataBytes = QJsonDocument(completeMetadata).toJson(QJsonDocument::Compact);
    if (metadataBytes.isEmpty() || metadataBytes.size() > static_cast<qsizetype>(kMaxMetadataBytes)) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn metadata is too large.");
        return false;
    }

    QSaveFile file(outputPath);
    if (!file.open(QIODevice::WriteOnly)) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not create .agn file: ") + file.errorString();
        return false;
    }

    QDataStream stream(&file);
    stream.setByteOrder(QDataStream::BigEndian);
    stream.setVersion(QDataStream::Qt_6_5);
    const QByteArray magic(kMagic, 8);
    if (!writeRaw(stream, magic)) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not write the .agn header.");
        file.cancelWriting();
        return false;
    }

    stream << kMajorVersion
           << kMinorVersion
           << flags
           << static_cast<quint32>(metadataBytes.size())
           << static_cast<quint64>(content.bytes.size())
           << static_cast<quint64>(original.bytes.size());

    if (stream.status() != QDataStream::Ok
        || !writeRaw(stream, metadataBytes)
        || !writeRaw(stream, content.bytes)
        || !writeRaw(stream, original.bytes)
        || file.error() != QFileDevice::NoError) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not write the complete .agn document.");
        file.cancelWriting();
        return false;
    }

    if (!file.commit()) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not finish writing .agn file: ") + file.errorString();
        return false;
    }
    return true;
}
} // namespace

bool ArgonDocument::convertFile(const QString &sourcePath,
                                const QString &outputPath,
                                bool retainOriginal,
                                QVariantMap *summary,
                                QString *errorMessage)
{
    const QFileInfo sourceInfo(sourcePath);
    if (!sourceInfo.exists() || !sourceInfo.isFile()) {
        if (errorMessage) *errorMessage = QStringLiteral("The source path is not a file.");
        return false;
    }
    if (sourceInfo.isSymLink()) {
        if (errorMessage) *errorMessage = QStringLiteral("Symbolic links cannot be converted directly.");
        return false;
    }
    if (sourceInfo.size() < 0 || sourceInfo.size() > kMaxSourceBytes) {
        if (errorMessage) *errorMessage = QStringLiteral("The source file exceeds the 512 MiB conversion limit.");
        return false;
    }

    const QString cleanOutput = QFileInfo(outputPath).absoluteFilePath();
    if (QFileInfo(cleanOutput).suffix().compare(QStringLiteral("agn"), Qt::CaseInsensitive) != 0) {
        if (errorMessage) *errorMessage = QStringLiteral("Argon documents must use the .agn extension.");
        return false;
    }
    if (cleanOutput == sourceInfo.absoluteFilePath()) {
        if (errorMessage) *errorMessage = QStringLiteral("The output cannot overwrite the source file.");
        return false;
    }
    if (isDocumentFile(sourceInfo.absoluteFilePath())) {
        if (errorMessage) *errorMessage = QStringLiteral("The source is already an Argon .agn document.");
        return false;
    }

    QFile sourceFile(sourceInfo.absoluteFilePath());
    if (!sourceFile.open(QIODevice::ReadOnly)) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not read the source file: ") + sourceFile.errorString();
        return false;
    }
    const QByteArray sourceBytes = sourceFile.readAll();
    if (sourceFile.error() != QFileDevice::NoError || sourceBytes.size() > kMaxSourceBytes) {
        if (errorMessage) *errorMessage = QStringLiteral("The source file could not be read completely or exceeds 512 MiB.");
        return false;
    }

    const QString extension = sourceInfo.suffix().toLower();
    bool isText = isTextExtension(extension) && !sourceBytes.contains('\0');
    QString normalizedText;
    QByteArray contentBytes;
    if (isText) {
        const QString decoded = QString::fromUtf8(sourceBytes.constData(), sourceBytes.size());
        // Invalid UTF-8 is kept as opaque bytes instead of being silently replaced.
        if (decoded.toUtf8() != sourceBytes) {
            isText = false;
        } else {
            normalizedText = decoded;
            normalizedText.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
            normalizedText.replace(QLatin1Char('\r'), QLatin1Char('\n'));
            normalizedText = normalizedText.normalized(QString::NormalizationForm_C);
            contentBytes = normalizedText.toUtf8();
        }
    }

    if (!retainOriginal && !isText) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Original-file retention can only be disabled for supported UTF-8 text files.");
        }
        return false;
    }

    const QMimeDatabase mimeDatabase;
    QJsonObject source;
    source.insert(QStringLiteral("fileName"), sourceInfo.fileName());
    source.insert(QStringLiteral("extension"), extension);
    source.insert(QStringLiteral("mimeType"),
                  mimeDatabase.mimeTypeForFile(sourceInfo.fileName(), QMimeDatabase::MatchExtension).name());
    source.insert(QStringLiteral("size"), static_cast<double>(sourceBytes.size()));
    source.insert(QStringLiteral("sha256"), sha256Hex(sourceBytes));
    source.insert(QStringLiteral("retained"), retainOriginal);

    QJsonObject representation;
    representation.insert(QStringLiteral("kind"), isText ? QStringLiteral("text") : QStringLiteral("opaque"));
    representation.insert(QStringLiteral("mimeType"),
                          isText ? QStringLiteral("text/plain; charset=utf-8")
                                 : QStringLiteral("application/octet-stream"));
    if (isText) {
        representation.insert(QStringLiteral("charset"), QStringLiteral("utf-8"));
        representation.insert(QStringLiteral("normalization"), QStringLiteral("NFC with LF line endings"));
    }

    QJsonObject integrity;
    integrity.insert(QStringLiteral("contentSha256"), sha256Hex(contentBytes));
    integrity.insert(QStringLiteral("originalSha256"), sha256Hex(retainOriginal ? sourceBytes : QByteArray()));

    QJsonObject metadata;
    metadata.insert(QStringLiteral("schema"), QStringLiteral("org.argon.document"));
    metadata.insert(QStringLiteral("formatVersion"), 1);
    metadata.insert(QStringLiteral("documentId"),
                    QUuid::createUuid().toString(QUuid::WithoutBraces));
    metadata.insert(QStringLiteral("createdAt"),
                    QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    metadata.insert(QStringLiteral("title"), sourceInfo.completeBaseName());
    metadata.insert(QStringLiteral("source"), source);
    metadata.insert(QStringLiteral("representation"), representation);
    metadata.insert(QStringLiteral("integrity"), integrity);

    quint32 flags = 0;
    if (retainOriginal) flags |= kFlagOriginalRetained;
    if (isText) flags |= kFlagTextRepresentation;

    if (!QDir().mkpath(QFileInfo(cleanOutput).absolutePath())) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not create the output folder.");
        return false;
    }
    if (!writeDocument(cleanOutput, metadata, contentBytes,
                       retainOriginal ? sourceBytes : QByteArray(),
                       flags, errorMessage)) {
        return false;
    }

    if (summary) {
        summary->clear();
        summary->insert(QStringLiteral("path"), cleanOutput);
        summary->insert(QStringLiteral("fileName"), QFileInfo(cleanOutput).fileName());
        summary->insert(QStringLiteral("title"), sourceInfo.completeBaseName());
        summary->insert(QStringLiteral("sourceBytes"), sourceBytes.size());
        summary->insert(QStringLiteral("argonBytes"), QFileInfo(cleanOutput).size());
        summary->insert(QStringLiteral("isText"), isText);
        summary->insert(QStringLiteral("originalRetained"), retainOriginal);
        summary->insert(QStringLiteral("documentId"), metadata.value(QStringLiteral("documentId")).toString());
    }
    return true;
}

bool ArgonDocument::readFile(const QString &argonPath,
                             ArgonDocumentData &document,
                             QString *errorMessage)
{
    document = {};
    QFile file(argonPath);
    if (!file.open(QIODevice::ReadOnly)) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not open .agn file: ") + file.errorString();
        return false;
    }
    if (file.size() < kHeaderSize) {
        if (errorMessage) *errorMessage = QStringLiteral("The file is too small to be a valid .agn document.");
        return false;
    }

    QDataStream stream(&file);
    stream.setByteOrder(QDataStream::BigEndian);
    stream.setVersion(QDataStream::Qt_6_5);
    char magic[8] = {};
    if (stream.readRawData(magic, 8) != 8
        || QByteArray(magic, 8) != QByteArray(kMagic, 8)) {
        if (errorMessage) *errorMessage = QStringLiteral("This file does not have an Argon .agn signature.");
        return false;
    }

    quint16 major = 0;
    quint16 minor = 0;
    quint32 flags = 0;
    quint32 metadataLength = 0;
    quint64 contentLength = 0;
    quint64 originalLength = 0;
    stream >> major >> minor >> flags >> metadataLength >> contentLength >> originalLength;

    if (stream.status() != QDataStream::Ok
        || major != kMajorVersion
        || minor > kMinorVersion
        || (flags & ~kKnownFlags) != 0) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn format version or header flags are not supported.");
        return false;
    }
    if (metadataLength == 0 || metadataLength > kMaxMetadataBytes
        || contentLength > static_cast<quint64>(kMaxContentBytes)
        || originalLength > static_cast<quint64>(kMaxSourceBytes)) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn header contains invalid section sizes.");
        return false;
    }

    const quint64 expectedSize = static_cast<quint64>(kHeaderSize)
        + metadataLength + contentLength + originalLength;
    if (expectedSize != static_cast<quint64>(file.size())) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn file is truncated or contains unexpected trailing data.");
        return false;
    }

    QByteArray metadataBytes(static_cast<qsizetype>(metadataLength), Qt::Uninitialized);
    QByteArray storedContent(static_cast<qsizetype>(contentLength), Qt::Uninitialized);
    QByteArray storedOriginal(static_cast<qsizetype>(originalLength), Qt::Uninitialized);
    if (stream.readRawData(metadataBytes.data(), metadataBytes.size()) != metadataBytes.size()
        || stream.readRawData(storedContent.data(), storedContent.size()) != storedContent.size()
        || stream.readRawData(storedOriginal.data(), storedOriginal.size()) != storedOriginal.size()) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn file could not be read completely.");
        return false;
    }

    QJsonParseError parseError{};
    const QJsonDocument json = QJsonDocument::fromJson(metadataBytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !json.isObject()) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn metadata is invalid.");
        return false;
    }
    const QJsonObject metadata = json.object();
    if (metadata.value(QStringLiteral("schema")).toString() != QStringLiteral("org.argon.document")
        || metadata.value(QStringLiteral("formatVersion")).toInt(-1) != 1) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn metadata schema is not supported.");
        return false;
    }

    const QJsonObject source = metadata.value(QStringLiteral("source")).toObject();
    const QJsonObject representation = metadata.value(QStringLiteral("representation")).toObject();
    const QJsonObject integrity = metadata.value(QStringLiteral("integrity")).toObject();
    const QJsonObject encoding = metadata.value(QStringLiteral("encoding")).toObject();
    const bool retained = (flags & kFlagOriginalRetained) != 0;
    const bool hasText = (flags & kFlagTextRepresentation) != 0;
    if (source.value(QStringLiteral("retained")).toBool() != retained
        || representation.value(QStringLiteral("kind")).toString()
            != (hasText ? QStringLiteral("text") : QStringLiteral("opaque"))
        || (!retained && !storedOriginal.isEmpty())) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn metadata does not match its binary header.");
        return false;
    }

    QByteArray contentBytes;
    if (!decodePayload(storedContent, encoding.value(QStringLiteral("content")).toString(),
                       kMaxContentBytes, contentBytes, errorMessage)) {
        return false;
    }
    QByteArray originalBytes;
    if (!decodePayload(storedOriginal, encoding.value(QStringLiteral("original")).toString(),
                       kMaxSourceBytes, originalBytes, errorMessage)) {
        return false;
    }

    if (sha256Hex(contentBytes) != integrity.value(QStringLiteral("contentSha256")).toString()) {
        if (errorMessage) *errorMessage = QStringLiteral("The normalized content failed its SHA-256 integrity check.");
        return false;
    }
    if (retained) {
        if (sha256Hex(originalBytes) != source.value(QStringLiteral("sha256")).toString()
            || sha256Hex(originalBytes) != integrity.value(QStringLiteral("originalSha256")).toString()) {
            if (errorMessage) *errorMessage = QStringLiteral("The original source payload failed its SHA-256 integrity check.");
            return false;
        }
    } else if (integrity.value(QStringLiteral("originalSha256")).toString()
               != sha256Hex(QByteArray())) {
        if (errorMessage) *errorMessage = QStringLiteral("The .agn file has an invalid empty-source integrity value.");
        return false;
    }

    QString textContent;
    if (hasText) {
        textContent = QString::fromUtf8(contentBytes.constData(), contentBytes.size());
        if (textContent.toUtf8() != contentBytes) {
            if (errorMessage) *errorMessage = QStringLiteral("The normalized text section is not valid UTF-8.");
            return false;
        }
    } else if (!contentBytes.isEmpty()) {
        if (errorMessage) *errorMessage = QStringLiteral("An opaque .agn document must not contain a text section.");
        return false;
    }

    document.metadata = metadata.toVariantMap();
    document.textContent = textContent;
    document.originalData = retained ? originalBytes : QByteArray();
    document.hasText = hasText;
    document.hasOriginal = retained;
    return true;
}

bool ArgonDocument::isDocumentFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    return file.read(8) == QByteArray(kMagic, 8);
}
