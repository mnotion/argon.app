#include "ReleaseMetadataService.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>

#include "LatestReleaseMetadata.h"
#include "VersionNumber.h"

namespace {
const QString kDefaultMetadataUrl = QStringLiteral(
    "https://raw.githubusercontent.com/ananas123123/argon.updater/rel-config/latest.json");

bool isSecureMetadataUrl(const QUrl &url)
{
    if (!url.isValid() || url.host().isEmpty())
        return false;

    if (url.scheme() == QStringLiteral("https"))
        return true;

    // Permit plain HTTP only for loopback test servers. Never use it for remote hosts.
    const QString host = url.host().toLower();
    return url.scheme() == QStringLiteral("http")
        && (host == QStringLiteral("localhost")
            || host == QStringLiteral("127.0.0.1")
            || host == QStringLiteral("::1"));
}
}

ReleaseMetadataService::ReleaseMetadataService(QObject *parent)
    : QObject(parent),
      m_currentVersion(QCoreApplication::applicationVersion()),
      m_metadataUrl(qEnvironmentVariable(
          "ARGON_LATEST_JSON_URL", kDefaultMetadataUrl))
{
}

QString ReleaseMetadataService::currentVersion() const
{
    return m_currentVersion;
}

QString ReleaseMetadataService::latestVersion() const
{
    return m_latestVersion;
}

QString ReleaseMetadataService::releaseNotesUrl() const
{
    return m_releaseNotesUrl;
}

QString ReleaseMetadataService::status() const
{
    return m_status;
}

QString ReleaseMetadataService::metadataUrl() const
{
    return m_metadataUrl.toString(QUrl::FullyEncoded);
}

bool ReleaseMetadataService::checking() const
{
    return m_checking;
}

bool ReleaseMetadataService::checkSucceeded() const
{
    return m_checkSucceeded;
}

bool ReleaseMetadataService::updateAvailable() const
{
    return m_updateAvailable;
}

void ReleaseMetadataService::checkForUpdates()
{
    if (m_checking)
        return;

    if (!isSecureMetadataUrl(m_metadataUrl)) {
        failCheck(QStringLiteral(
            "Release metadata URL must use HTTPS (HTTP is allowed only on localhost for tests)."));
        return;
    }

    QString currentVersionError;
    const auto current = VersionNumber::parse(m_currentVersion, &currentVersionError);
    if (!current) {
        failCheck(QStringLiteral("The installed Argon version is invalid: %1")
                      .arg(currentVersionError));
        return;
    }

    m_checking = true;
    m_checkSucceeded = false;
    m_status = QStringLiteral("Checking for the latest stable release...");
    emit stateChanged();

    // Bypass intermediary caches for the public raw GitHub metadata endpoint.
    // The unique query also makes each periodic request a fresh cache key.
    QUrl requestUrl = m_metadataUrl;
    if (requestUrl.host().compare(
            QStringLiteral("raw.githubusercontent.com"), Qt::CaseInsensitive) == 0) {
        QUrlQuery query(requestUrl);
        query.removeAllQueryItems(QStringLiteral("_argon_refresh"));
        query.addQueryItem(
            QStringLiteral("_argon_refresh"),
            QString::number(QDateTime::currentMSecsSinceEpoch()));
        requestUrl.setQuery(query);
    }

    QNetworkRequest request(requestUrl);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(
        QByteArrayLiteral("Cache-Control"),
        QByteArrayLiteral("no-cache, no-store, max-age=0"));
    request.setRawHeader(QByteArrayLiteral("Pragma"), QByteArrayLiteral("no-cache"));
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("Argon/%1").arg(m_currentVersion));
    // Keep a stalled connection from blocking the next 10-second retry slot.
    request.setTransferTimeout(8000);
    request.setAttribute(
        QNetworkRequest::CacheLoadControlAttribute,
        QNetworkRequest::AlwaysNetwork);
    request.setAttribute(QNetworkRequest::CacheSaveControlAttribute, false);
    request.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, current]() {
        const QByteArray responseBody = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const QString networkErrorText = reply->errorString();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        if (networkError != QNetworkReply::NoError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            const QString detail = httpStatus > 0
                ? QStringLiteral("HTTP %1").arg(httpStatus)
                : networkErrorText;
            failCheck(QStringLiteral("Could not retrieve release metadata: %1").arg(detail));
            return;
        }

        QString metadataError;
        const auto metadata = LatestReleaseMetadata::parse(responseBody, &metadataError);
        if (!metadata) {
            failCheck(QStringLiteral("Release metadata validation failed: %1").arg(metadataError));
            return;
        }

        m_latestVersion = metadata->version.toString();
        m_releaseNotesUrl = metadata->releaseNotesUrl.toString(QUrl::FullyEncoded);
        m_updateAvailable = metadata->version.isNewerThan(*current);
        m_checkSucceeded = true;
        m_checking = false;

        if (m_updateAvailable) {
            m_status = QStringLiteral("Version %1 is available.").arg(m_latestVersion);
        } else if (metadata->version == *current) {
            m_status = QStringLiteral("Argon is up to date.");
        } else {
            m_status = QStringLiteral(
                "The installed version is newer than the configured stable release.");
        }

        emit stateChanged();
    });
}

void ReleaseMetadataService::failCheck(const QString &message)
{
    m_checking = false;
    m_checkSucceeded = false;
    m_updateAvailable = false;
    m_status = message;
    emit stateChanged();
}
