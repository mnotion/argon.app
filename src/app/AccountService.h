#pragma once

#include <QObject>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QString>

#include <functional>

class QNetworkReply;

class AccountService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY loggedInChanged)
    Q_PROPERTY(QString username READ username NOTIFY accountChanged)
    Q_PROPERTY(QString accountId READ accountId NOTIFY accountChanged)
    Q_PROPERTY(QString udt READ udt NOTIFY accountChanged)
    Q_PROPERTY(QString plan READ plan NOTIFY accountChanged)
    Q_PROPERTY(qint64 storageLimitBytes READ storageLimitBytes NOTIFY accountChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(bool hasPendingUit READ hasPendingUit NOTIFY pendingStateChanged)
    Q_PROPERTY(QString pendingUit READ pendingUit NOTIFY pendingStateChanged)

public:
    explicit AccountService(QObject *parent = nullptr);

    bool loggedIn() const { return m_loggedIn; }
    QString username() const { return m_username; }
    QString accountId() const { return m_accountId; }
    QString udt() const { return m_udt; }
    QString plan() const { return m_plan; }
    qint64 storageLimitBytes() const { return m_storageLimitBytes; }
    bool busy() const { return m_busy; }
    QString errorMessage() const { return m_errorMessage; }
    bool hasPendingUit() const { return !m_pendingUit.isEmpty(); }
    QString pendingUit() const { return m_pendingUit; }

    Q_INVOKABLE void createAccount(const QString &username, const QString &password);
    Q_INVOKABLE void login(const QString &username, const QString &password);
    Q_INVOKABLE void recoverPassword(const QString &username, const QString &uit,
                                    const QString &newPassword);
    Q_INVOKABLE void logout();
    Q_INVOKABLE void acknowledgePendingUit();
    Q_INVOKABLE void copyPendingUit();
    Q_INVOKABLE void clearError();

signals:
    void loggedInChanged();
    void accountChanged();
    void busyChanged();
    void errorMessageChanged();
    void pendingStateChanged();
    void recoveryCompleted();

private:
    using JsonCallback = std::function<void(int, const QJsonObject &, const QString &)>;

    void setBusy(bool busy);
    void setErrorMessage(const QString &message);
    void requestJson(const QString &method, const QString &path,
                     const QJsonObject &body, const QString &bearerToken,
                     JsonCallback callback);
    void restoreSession();
    void refreshProfile();
    void applyAccount(const QJsonObject &account);
    void setSession(const QString &token, const QJsonObject &account);
    void clearSession();
    bool writeProtectedJson(const QString &path, const QJsonObject &object);
    bool readProtectedJson(const QString &path, QJsonObject &object) const;
    QByteArray protectBytes(const QByteArray &data) const;
    QByteArray unprotectBytes(const QByteArray &data) const;
    QString sessionPath() const;
    QString pendingUitPath() const;
    bool savePendingUit(const QString &uit, const QJsonObject &account);
    bool loadPendingUit();

    QNetworkAccessManager m_network;
    bool m_loggedIn = false;
    bool m_busy = false;
    QString m_username;
    QString m_accountId;
    QString m_udt;
    QString m_plan = QStringLiteral("Free");
    qint64 m_storageLimitBytes = 1073741824LL;
    QString m_accessToken;
    QString m_errorMessage;
    QString m_pendingUit;
    QString m_pendingUsername;
    QString m_pendingAccountId;
    QString m_pendingUdt;
};
