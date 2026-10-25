#include "AccountService.h"

#include "AppPaths.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QClipboard>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStringList>
#include <QTimer>
#include <QUuid>
#include <utility>
#include <QUrl>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <dpapi.h>
#endif

namespace
{
#ifndef ARGON_API_BASE_URL
#define ARGON_API_BASE_URL "https://argon-backend-y4b1.onrender.com"
#endif

QString responseError(const QJsonObject &json, const QString &fallback)
{
    const QJsonValue detail = json.value(QStringLiteral("detail"));
    if (detail.isString() && !detail.toString().trimmed().isEmpty())
        return detail.toString();
    if (detail.isArray()) {
        QStringList messages;
        for (const QJsonValue &item : detail.toArray()) {
            if (item.isObject() && item.toObject().value(QStringLiteral("msg")).isString())
                messages.append(item.toObject().value(QStringLiteral("msg")).toString());
        }
        if (!messages.isEmpty())
            return messages.join(QStringLiteral("\n"));
    }
    return fallback;
}
}

AccountService::AccountService(QObject *parent)
    : QObject(parent)
{
    QDir().mkpath(ArgonPaths::accountsDirectory());
    loadPendingRegistration();
    loadPendingUit();
    if (!m_pendingUit.isEmpty())
        clearPendingRegistration();
    restoreSession();
}

QString AccountService::sessionPath() const
{
    return QDir(ArgonPaths::accountsDirectory()).filePath(QStringLiteral("session.bin"));
}

QString AccountService::pendingUitPath() const
{
    return QDir(ArgonPaths::accountsDirectory()).filePath(QStringLiteral("pending-uit.bin"));
}

QString AccountService::pendingRegistrationPath() const
{
    return QDir(ArgonPaths::accountsDirectory()).filePath(QStringLiteral("pending-registration.bin"));
}

bool AccountService::savePendingRegistration(const QString &username)
{
    const QString normalized = username.normalized(QString::NormalizationForm_C).toCaseFolded();
    const QString currentNormalized =
        m_registrationUsername.normalized(QString::NormalizationForm_C).toCaseFolded();
    if (m_registrationId.isEmpty() || normalized != currentNormalized) {
        m_registrationId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        m_registrationUsername = username;
    }

    const QJsonObject pending{
        {QStringLiteral("schemaVersion"), 1},
        {QStringLiteral("registrationId"), m_registrationId},
        {QStringLiteral("username"), m_registrationUsername},
    };
    if (!writeProtectedJson(pendingRegistrationPath(), pending))
        return false;
    emit registrationStateChanged();
    return true;
}

bool AccountService::loadPendingRegistration()
{
    QJsonObject pending;
    if (!readProtectedJson(pendingRegistrationPath(), pending))
        return false;

    const QString id = pending.value(QStringLiteral("registrationId")).toString();
    const QString username = pending.value(QStringLiteral("username")).toString();
    if (QUuid(id).isNull() || username.isEmpty())
        return false;
    m_registrationId = QUuid(id).toString(QUuid::WithoutBraces);
    m_registrationUsername = username;
    emit registrationStateChanged();
    return true;
}

void AccountService::clearPendingRegistration()
{
    if (QFileInfo::exists(pendingRegistrationPath()) && !QFile::remove(pendingRegistrationPath())) {
        setErrorMessage(QStringLiteral("Argon could not clear the interrupted-signup marker. It will retry safely on the next launch."));
        return;
    }
    m_registrationId.clear();
    m_registrationUsername.clear();
    emit registrationStateChanged();
}

void AccountService::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void AccountService::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}

void AccountService::clearError()
{
    setErrorMessage(QString());
}

QByteArray AccountService::protectBytes(const QByteArray &data) const
{
#ifdef Q_OS_WIN
    DATA_BLOB input{};
    input.cbData = static_cast<DWORD>(data.size());
    input.pbData = reinterpret_cast<BYTE *>(const_cast<char *>(data.constData()));
    DATA_BLOB output{};
    if (!CryptProtectData(&input, L"Argon local account state", nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        return {};
    }
    QByteArray protectedData("ARGON_DPAPI_V1:");
    protectedData.append(reinterpret_cast<const char *>(output.pbData),
                         static_cast<qsizetype>(output.cbData));
    LocalFree(output.pbData);
    return protectedData;
#else
    // Non-Windows development builds use owner-only file permissions below.
    // The distributed Windows build uses DPAPI to protect session and pending UIT data.
    QByteArray protectedData("ARGON_LOCAL_V1:");
    protectedData.append(data);
    return protectedData;
#endif
}

QByteArray AccountService::unprotectBytes(const QByteArray &data) const
{
#ifdef Q_OS_WIN
    static const QByteArray prefix("ARGON_DPAPI_V1:");
    if (!data.startsWith(prefix))
        return {};
    QByteArray protectedPayload = data.mid(prefix.size());
    DATA_BLOB input{};
    input.cbData = static_cast<DWORD>(protectedPayload.size());
    input.pbData = reinterpret_cast<BYTE *>(protectedPayload.data());
    DATA_BLOB output{};
    if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                            CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        return {};
    }
    QByteArray clear(reinterpret_cast<const char *>(output.pbData),
                     static_cast<qsizetype>(output.cbData));
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    return clear;
#else
    static const QByteArray prefix("ARGON_LOCAL_V1:");
    if (!data.startsWith(prefix))
        return {};
    return data.mid(prefix.size());
#endif
}

bool AccountService::writeProtectedJson(const QString &path, const QJsonObject &object)
{
    const QByteArray plain = QJsonDocument(object).toJson(QJsonDocument::Compact);
    const QByteArray protectedData = protectBytes(plain);
    if (protectedData.isEmpty())
        return false;
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    if (file.write(protectedData) != protectedData.size()) {
        file.cancelWriting();
        return false;
    }
    if (!file.commit())
        return false;
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

bool AccountService::readProtectedJson(const QString &path, QJsonObject &object) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    const QByteArray protectedData = file.readAll();
    file.close();

    const QByteArray plain = unprotectBytes(protectedData);
    if (plain.isEmpty())
        return false;
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(plain, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return false;
    object = document.object();
    return true;
}

bool AccountService::savePendingUit(const QString &uit, const QJsonObject &account)
{
    m_pendingUit = uit;
    m_pendingUsername = account.value(QStringLiteral("username")).toString();
    m_pendingAccountId = account.value(QStringLiteral("id")).toString();
    m_pendingUdt = account.value(QStringLiteral("udt")).toString();

    QJsonObject pending{
        {QStringLiteral("schemaVersion"), 1},
        {QStringLiteral("uit"), m_pendingUit},
        {QStringLiteral("username"), m_pendingUsername},
        {QStringLiteral("accountId"), m_pendingAccountId},
        {QStringLiteral("udt"), m_pendingUdt},
    };
    const bool saved = writeProtectedJson(pendingUitPath(), pending);
    emit pendingStateChanged();
    if (saved)
        clearPendingRegistration();
    return saved;
}

bool AccountService::loadPendingUit()
{
    QJsonObject pending;
    if (!readProtectedJson(pendingUitPath(), pending))
        return false;
    m_pendingUit = pending.value(QStringLiteral("uit")).toString();
    m_pendingUsername = pending.value(QStringLiteral("username")).toString();
    m_pendingAccountId = pending.value(QStringLiteral("accountId")).toString();
    m_pendingUdt = pending.value(QStringLiteral("udt")).toString();
    if (m_pendingUit.isEmpty())
        return false;
    emit pendingStateChanged();
    return true;
}

void AccountService::restoreSession()
{
    QJsonObject session;
    if (!readProtectedJson(sessionPath(), session))
        return;
    m_accessToken = session.value(QStringLiteral("accessToken")).toString();
    const QJsonObject account = session.value(QStringLiteral("account")).toObject();
    applyAccount(account);
    const bool changed = !m_accessToken.isEmpty() != m_loggedIn;
    m_loggedIn = !m_accessToken.isEmpty();
    emit accountChanged();
    if (changed)
        emit loggedInChanged();
    if (m_loggedIn)
        QTimer::singleShot(0, this, &AccountService::refreshProfile);
}

void AccountService::refreshProfile()
{
    if (m_accessToken.isEmpty())
        return;
    requestJson(QStringLiteral("GET"), QStringLiteral("/api/v1/account/me"), {},
                m_accessToken, [this](int status, const QJsonObject &json, const QString &) {
        if (status >= 200 && status < 300) {
            applyAccount(json);
            QJsonObject session{
                {QStringLiteral("accessToken"), m_accessToken},
                {QStringLiteral("account"), json},
            };
            writeProtectedJson(sessionPath(), session);
            emit accountChanged();
        } else if (status == 401) {
            clearSession();
        }
        // On network failures, retain the locally persisted session so a temporary
        // outage or a sleeping free service does not silently sign the user out.
    });
}

void AccountService::applyAccount(const QJsonObject &account)
{
    m_username = account.value(QStringLiteral("username")).toString();
    m_accountId = account.value(QStringLiteral("id")).toString();
    m_udt = account.value(QStringLiteral("udt")).toString();
    m_plan = account.value(QStringLiteral("plan")).toString(QStringLiteral("Free"));
    m_storageLimitBytes = static_cast<qint64>(
        account.value(QStringLiteral("storage_limit_bytes")).toDouble(
            account.value(QStringLiteral("storageLimitBytes")).toDouble(1073741824.0)));
}

void AccountService::setSession(const QString &token, const QJsonObject &account)
{
    const bool wasLoggedIn = m_loggedIn;
    m_accessToken = token;
    applyAccount(account);
    m_loggedIn = !m_accessToken.isEmpty();
    const QJsonObject session{
        {QStringLiteral("accessToken"), m_accessToken},
        {QStringLiteral("account"), account},
    };
    if (!writeProtectedJson(sessionPath(), session))
        setErrorMessage(QStringLiteral("Your session could not be saved securely on this device. You may need to log in again after restarting Argon."));
    emit accountChanged();
    if (wasLoggedIn != m_loggedIn)
        emit loggedInChanged();
}

void AccountService::clearSession()
{
    const bool wasLoggedIn = m_loggedIn;
    m_accessToken.clear();
    m_username.clear();
    m_accountId.clear();
    m_udt.clear();
    m_plan = QStringLiteral("Free");
    m_storageLimitBytes = 1073741824LL;
    QFile::remove(sessionPath());
    m_loggedIn = false;
    emit accountChanged();
    if (wasLoggedIn)
        emit loggedInChanged();
}

void AccountService::requestJson(const QString &method, const QString &path,
                                 const QJsonObject &body, const QString &bearerToken,
                                 JsonCallback callback)
{
    QUrl url(QString::fromLatin1(ARGON_API_BASE_URL) + path);
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setTransferTimeout(120000);
    if (!bearerToken.isEmpty())
        request.setRawHeader("Authorization", QByteArray("Bearer ") + bearerToken.toUtf8());

    QNetworkReply *reply = nullptr;
    const QByteArray bytes = QJsonDocument(body).toJson(QJsonDocument::Compact);
    if (method == QStringLiteral("GET")) {
        reply = m_network.get(request);
    } else if (method == QStringLiteral("POST")) {
        reply = m_network.post(request, bytes);
    } else {
        reply = m_network.sendCustomRequest(request, method.toUtf8(), bytes);
    }

    connect(reply, &QNetworkReply::finished, this, [reply, callback = std::move(callback)]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray responseBytes = reply->readAll();
        QJsonObject json;
        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(responseBytes, &parseError);
        if (parseError.error == QJsonParseError::NoError && document.isObject())
            json = document.object();
        QString message;
        if (status < 200 || status >= 300) {
            message = responseError(json, reply->errorString());
        } else if (reply->error() != QNetworkReply::NoError && status == 0) {
            message = reply->errorString();
        }
        callback(status, json, message);
        reply->deleteLater();
    });
}

void AccountService::createAccount(const QString &username, const QString &password)
{
    if (m_busy)
        return;
    setErrorMessage(QString());
    if (!savePendingRegistration(username)) {
        setErrorMessage(QStringLiteral("Argon could not save the signup attempt securely. Check disk access and try again."));
        return;
    }

    const QString registrationId = m_registrationId;
    setBusy(true);
    requestJson(QStringLiteral("POST"), QStringLiteral("/api/v1/auth/signup"),
                {{QStringLiteral("registration_id"), registrationId},
                 {QStringLiteral("username"), username},
                 {QStringLiteral("password"), password}},
                QString(), [this](int status, const QJsonObject &json, const QString &error) {
        if (status != 200 && status != 201) {
            setErrorMessage(error.isEmpty()
                ? QStringLiteral("Account creation failed. Check your connection and try again.")
                : error);
            // Reuse the saved registration ID when retrying after a lost response.
            setBusy(false);
            return;
        }

        const QString token = json.value(QStringLiteral("access_token")).toString();
        const QString uit = json.value(QStringLiteral("uit")).toString();
        const QJsonObject account = json.value(QStringLiteral("account")).toObject();
        if (token.isEmpty() || uit.size() != 10 || account.value(QStringLiteral("username")).toString().isEmpty()) {
            setErrorMessage(QStringLiteral("The server returned an incomplete signup response. Retry the same signup; Argon will reuse the saved attempt ID."));
            setBusy(false);
            return;
        }

        const bool pendingSaved = savePendingUit(uit, account);
        setSession(token, account);
        if (!pendingSaved) {
            setErrorMessage(QStringLiteral("Your account was created, but the UIT screen could not be saved securely. Keep Argon open and retry this same signup to recover it."));
        }
        setBusy(false);
    });
}

void AccountService::login(const QString &username, const QString &password)
{
    if (m_busy)
        return;
    setErrorMessage(QString());
    setBusy(true);
    requestJson(QStringLiteral("POST"), QStringLiteral("/api/v1/auth/login"),
                {{QStringLiteral("username"), username},
                 {QStringLiteral("password"), password}},
                QString(), [this](int status, const QJsonObject &json, const QString &error) {
        if (status < 200 || status >= 300) {
            setErrorMessage(error.isEmpty()
                ? QStringLiteral("Login failed. Check your connection and credentials.")
                : error);
            setBusy(false);
            return;
        }
        const QString token = json.value(QStringLiteral("access_token")).toString();
        const QJsonObject account = json.value(QStringLiteral("account")).toObject();
        if (token.isEmpty() || account.value(QStringLiteral("username")).toString().isEmpty()) {
            setErrorMessage(QStringLiteral("The server returned an incomplete login response."));
            setBusy(false);
            return;
        }
        setSession(token, account);
        setBusy(false);
    });
}

void AccountService::recoverPassword(const QString &username, const QString &uit,
                                     const QString &newPassword)
{
    if (m_busy)
        return;
    setErrorMessage(QString());
    setBusy(true);
    requestJson(QStringLiteral("POST"), QStringLiteral("/api/v1/auth/recover"),
                {{QStringLiteral("username"), username},
                 {QStringLiteral("uit"), uit},
                 {QStringLiteral("new_password"), newPassword}},
                QString(), [this](int status, const QJsonObject &, const QString &error) {
        if (status < 200 || status >= 300) {
            setErrorMessage(error.isEmpty()
                ? QStringLiteral("Password recovery failed. Check your username, UIT and password rules.")
                : error);
            setBusy(false);
            return;
        }
        setErrorMessage(QString());
        setBusy(false);
        emit recoveryCompleted();
    });
}

void AccountService::logout()
{
    if (m_busy)
        return;
    if (m_accessToken.isEmpty()) {
        clearSession();
        return;
    }
    setErrorMessage(QString());
    setBusy(true);
    requestJson(QStringLiteral("POST"), QStringLiteral("/api/v1/auth/logout"), {},
                m_accessToken, [this](int status, const QJsonObject &, const QString &error) {
        if ((status >= 200 && status < 300) || status == 401) {
            clearSession();
            setErrorMessage(QString());
        } else {
            setErrorMessage(error.isEmpty()
                ? QStringLiteral("Argon couldn't confirm logout. Check your connection and retry.")
                : error);
        }
        setBusy(false);
    });
}

void AccountService::acknowledgePendingUit()
{
    if (m_pendingUit.isEmpty() || m_busy || m_accessToken.isEmpty())
        return;
    setErrorMessage(QString());
    setBusy(true);
    requestJson(QStringLiteral("POST"), QStringLiteral("/api/v1/auth/uit/acknowledge"), {},
                m_accessToken, [this](int status, const QJsonObject &, const QString &error) {
        if (status < 200 || status >= 300) {
            setErrorMessage(error.isEmpty()
                ? QStringLiteral("Argon could not confirm that your UIT was saved. Your token has been kept; try again.")
                : error);
            setBusy(false);
            return;
        }

        // Clear the local token only after the backend confirms acknowledgement.
        if (QFileInfo::exists(pendingUitPath()) && !QFile::remove(pendingUitPath())) {
            setErrorMessage(QStringLiteral("The UIT was acknowledged, but Argon could not clear the local screen file. The token remains on this device; retry to finish."));
            setBusy(false);
            return;
        }
        m_pendingUit.clear();
        m_pendingUsername.clear();
        m_pendingAccountId.clear();
        m_pendingUdt.clear();
        setErrorMessage(QString());
        emit pendingStateChanged();
        setBusy(false);
    });
}

void AccountService::copyPendingUit()
{
    if (m_pendingUit.isEmpty())
        return;
    if (QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(m_pendingUit);
}
