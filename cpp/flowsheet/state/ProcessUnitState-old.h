
#pragma once

#include <QObject>
#include <QString>

class ProcessUnitState : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString type READ type CONSTANT)
    Q_PROPERTY(QString displayName READ displayName WRITE setDisplayName NOTIFY displayNameChanged)
    Q_PROPERTY(QString iconKey READ iconKey CONSTANT)

public:
public:
   explicit ProcessUnitState(QObject* parent = nullptr);
   virtual ~ProcessUnitState() = default;

   void setId(const QString& v) { id_ = v; }
   QString id() const { return id_; }
   void setType(const QString& v) { type_ = v; }
   QString type() const { return type_; }
   QString displayName() const { return displayName_; }
   void setDisplayName(const QString& v);
   QString iconKey() const { return iconKey_; }
   void setIconKey(const QString& v) { iconKey_ = v; }

signals:
    void displayNameChanged();

protected:
    QString id_;
    QString type_;
    QString displayName_;
    QString iconKey_;
};
