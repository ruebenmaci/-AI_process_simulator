
#pragma once

#include <QObject>
#include <QString>
#include <QUuid>

class ProcessUnitState : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString guid READ guid CONSTANT)
    Q_PROPERTY(QString type READ type CONSTANT)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QString displayName READ displayName WRITE setDisplayName NOTIFY nameChanged)
    Q_PROPERTY(QString iconKey READ iconKey CONSTANT)

public:
public:
   explicit ProcessUnitState(QObject* parent = nullptr);
   virtual ~ProcessUnitState() = default;

   void setId(const QString& v) { id_ = v; }
   QString id() const { return id_; }
   QString guid() const { return guid_; }
   void setType(const QString& v) { type_ = v; }
   QString type() const { return type_; }
   QString name() const { return name_; }
   void setName(const QString& v);
   QString displayName() const { return name_; }
   void setDisplayName(const QString& v) { setName(v); }
   QString iconKey() const { return iconKey_; }
   void setIconKey(const QString& v) { iconKey_ = v; }

signals:
    void nameChanged();
    void displayNameChanged();

protected:
    QString id_;
    QString guid_;
    QString type_;
    QString name_;
    QString iconKey_;
};
