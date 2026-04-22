#pragma once
//
// ─────────────────────────────────────────────────────────────────────────────
//  UnitRegistry.h  —  Central units registry for AI Process Simulator
//
//  Registers as a QML singleton property: gUnits
//
//  Usage from QML:
//      gUnits.fromSI("Pressure", stream.pressurePa, "bar")     // → 10.0
//      gUnits.toSI  ("Pressure", 145.0,             "psia")    // → 999737.0
//      gUnits.unitsFor("Pressure")                             // → ["Pa","kPa","MPa","bar","atm","psia","psig","barg","mmHg","inH2O"]
//      gUnits.defaultUnit("Pressure")                          // → active Unit Set's default for Pressure
//      gUnits.format("Pressure", siValue, displayUnit)        // → "10.0"   (per gFormats spec)
//      gUnits.format("Pressure", siValue, displayUnit, 3)      // → "10.000" (explicit override)
//      gUnits.parseInline("Pressure", "145 psia")              // → { ok:true, valueSI:999737.0, unit:"psia" }
//
//  The internal storage convention is SI:
//      Temperature → K        Pressure → Pa             MassFlow → kg/s (note: kg/s not kg/h)
//      MolarFlow   → mol/s    VolumeFlow → m³/s         SpecificEnthalpy → J/kg
//      SpecificEntropy → J/(kg·K)                       SpecificHeat → J/(kg·K)
//      Density → kg/m³        Viscosity → Pa·s          ThermalCond → W/(m·K)
//      SurfaceTension → N/m   MolarMass → kg/mol        Power → W
//      Energy → J             Dimensionless → (no conversion)
//
//  IMPORTANT: Stream's Q_PROPERTY values are in their own historical units
//  (kg/h, K, Pa, kJ/kg, etc.) — not all canonical SI.  The registry lets
//  callers convert to/from any unit, so the panel code reads the raw property
//  value and asks the registry to display it as the user wants it.
// ─────────────────────────────────────────────────────────────────────────────

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QHash>
#include <QVector>
#include <QSet>
#include <QJsonObject>

class UnitRegistry : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString activeUnitSet READ activeUnitSet WRITE setActiveUnitSet NOTIFY activeUnitSetChanged)
    Q_PROPERTY(QStringList availableUnitSets READ availableUnitSets CONSTANT)

public:
    // ───────── Internal data structures (header-private) ─────────
    struct Unit {
        QString  name;        // e.g. "psia", "°C", "kg/h"
        double   scale = 1.0; // toSI: si = display * scale + offset
        double   offset = 0.0;
        QString  display;     // optional pretty display name (defaults to name)
        QStringList aliases;  // for inline parser: "psi" → "psia"
    };
    // A "quantity" is what the value represents (Pressure, Temperature…).
    struct Quantity {
        QString          name;
        QVector<Unit>    units;
    };

    explicit UnitRegistry(QObject* parent = nullptr);

    static UnitRegistry* instance();

    // ───────── QML-callable API ─────────
    // Project-file persistence for custom unit sets + active selection
    QJsonObject saveProjectSettings() const;
    void loadProjectSettings(const QJsonObject& obj);

    Q_INVOKABLE double      toSI       (const QString& quantity, double  display, const QString& unit) const;
    Q_INVOKABLE double      fromSI     (const QString& quantity, double  siValue, const QString& unit) const;
    Q_INVOKABLE QStringList unitsFor   (const QString& quantity) const;
    Q_INVOKABLE QStringList knownQuantities() const;
    Q_INVOKABLE QString     defaultUnit(const QString& quantity) const;
    Q_INVOKABLE QString     unitForSet(const QString& setName, const QString& quantity) const;
    Q_INVOKABLE bool        isCompatible(const QString& quantity, const QString& unit) const;
    Q_INVOKABLE QString     format     (const QString& quantity, double siValue, const QString& unit, int decimals = -1) const;

    // Parse  "145 psia"  →  { ok, valueSI, unit, error }
    // Bare number   →  { ok, valueSI from `assumeUnit`, unit:assumeUnit }
    // Number + unit →  { ok, valueSI converted from typed unit, unit:typed   }
    Q_INVOKABLE QVariantMap parseInline(const QString& quantity,
                                        const QString& text,
                                        const QString& assumeUnit) const;

    // For the picker preview: list of {unit, preview} where preview = fromSI(siValue, unit) formatted
    Q_INVOKABLE QVariantList unitOptionsFor(const QString& quantity, double siValue, int decimals = -1) const;

    // Unit Sets  ("SI", "Field", "British")
    QString     activeUnitSet() const { return m_activeSet; }
    QStringList availableUnitSets() const;
    Q_INVOKABLE QStringList unitSetNames() const;
    Q_INVOKABLE bool isBuiltInUnitSet(const QString& name) const;
    Q_INVOKABLE void setActiveUnitSet(const QString& name);
    Q_INVOKABLE bool cloneUnitSet(const QString& sourceName, const QString& newName);
    Q_INVOKABLE bool setUnitForQuantity(const QString& setName, const QString& quantity, const QString& unit);

    // Inject the sibling FormatRegistry (registered as gFormats on the same
    // QML context).  Call once from main.cpp after both objects are
    // constructed.  Without this, format() and unitOptionsFor() fall back
    // to a 3-dp default when called with the gFormats sentinel (decimals < 0).
    void setFormatRegistry(const class FormatRegistry* fmt) { m_formats = fmt; }

    // For panels: what siProp value should this row read its calculated value from?
    // Caller still binds to stream.pressurePa directly — registry is purely a converter.
    // (Method left for future schema work.)

signals:
    void activeUnitSetChanged();
    // Fires whenever ANY display unit changes (Unit Set switch).
    // Panels listen to this and re-format every cell.
    void unitsChanged();

private:
    void registerQuantity(const QString& q);
    void registerUnit(const QString& quantity,
                      const QString& name,
                      double scale,
                      double offset = 0.0,
                      const QStringList& aliases = {},
                      const QString& display = QString());
    void registerUnitSet(const QString& set, const QHash<QString, QString>& defaults, bool builtIn = true);
    const Unit* findUnit(const QString& quantity, const QString& unit) const;

    QHash<QString, Quantity>                   m_quantities;
    QHash<QString, QHash<QString, QString>>    m_unitSets;     // setName → quantity → unit
    QSet<QString>                              m_builtinUnitSets;
    QString                                    m_activeSet;
    const class FormatRegistry*                m_formats = nullptr;  // injected by main.cpp

    static UnitRegistry* s_instance;
};
