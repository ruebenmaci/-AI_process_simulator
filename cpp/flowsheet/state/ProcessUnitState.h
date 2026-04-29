
#pragma once

#include <QObject>
#include <QString>
#include <QUuid>

// ─────────────────────────────────────────────────────────────────────────────
// ConnectivityStatus
//
// Lightweight value type describing the *current* connection-completeness of
// a unit op, independent of whether it has been solved. Aggregated by
// FlowsheetStatusModel into the bottom Status panel.
//
// "OK" = unit has all the connections it needs to be solvable. It may still
// fail at solve time for spec/thermo reasons; that's a separate dimension
// surfaced via the unit's runtime statusLevel/diagnostics.
// ─────────────────────────────────────────────────────────────────────────────
struct ConnectivityStatus {
    // 0 = OK, 2 = Warn (e.g. partial inlet count on a mixer, but still
    // solvable), 3 = Fail (e.g. no feed connected at all).
    int     severity = 0;
    // Short human-readable reason, e.g. "missing product stream",
    // "only 1 of 2 inlets connected". Empty when severity is OK.
    QString reason;
};

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

   // ── Connectivity status (override per unit op) ───────────────────────────
   //
   // Returns the current connection-completeness of this unit, evaluated
   // from its connection state (NOT from solver results). Default
   // implementation returns OK; concrete unit ops override to encode their
   // specific connection requirements (e.g. column needs a feed; mixer
   // needs at least 2 inlets; HEX needs all four ports).
   //
   // Called by FlowsheetStatusModel to populate the bottom Status panel.
   // Should be cheap — it's invoked on every connection change across the
   // flowsheet.
   virtual ConnectivityStatus connectivityStatus() const { return {}; }

   // Emitted by a concrete unit op whenever a change to its connection
   // state could alter what connectivityStatus() returns. Used by the
   // FlowsheetStatusModel aggregator. Subclasses connect their existing
   // *StreamChanged signals to this in their constructors so subscribers
   // need only watch one thing.
signals:
    void nameChanged();
    void displayNameChanged();
    void connectivityStatusChanged();

protected:
    QString id_;
    QString guid_;
    QString type_;
    QString name_;
    QString iconKey_;
};
