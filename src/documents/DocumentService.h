#pragma once
#include <QObject>
#include <QStringList>

class DocumentService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList recentDocuments READ recentDocuments NOTIFY recentDocumentsChanged)
public:
    explicit DocumentService(QObject *parent = nullptr);
    QStringList recentDocuments() const;
signals:
    void recentDocumentsChanged();
private:
    QStringList m_recentDocuments;
};
