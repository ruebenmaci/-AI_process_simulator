#pragma once
//
// ─────────────────────────────────────────────────────────────────────────────
//  FormatRegistry.h  —  Per-quantity number formatting for AI Process Simulator
//
//  Registers as a QML context property: gFormats
//
//  Sister registry to gUnits.  Where gUnits handles "what units does this
//  quantity have, and how do I convert between them," gFormats handles
//  "how should a number of this quantity be displayed."
//
//  HYSYS-style design: the user picks a format spec per quantity (Temperature
//  uses 2 decimal places fixed, MassFlow uses 4 sig figs auto-switching to
//  exponential, etc.).  Specs are grouped into named sets — the built-in
//  "Engineering Default" set is read-only; users may clone and edit copies.
//
//  Usage from QML:
//      gFormats.format("Temperature", 298.15, "°C")     // → "25.00"
//      gFormats.format("MassFlow",   100000.0, "kg/h")  // → "1.000e+05"
//      gFormats.formatValue("Pressure", 145.0)          // → "145.0"  (already in display unit)
//
//  Usage from C++ (e.g. UnitRegistry):
//      gFormats->format("Temperature", siValue, "°C")
//
//  Format kinds:
//      Fixed       — N decimal places, always fixed notation
//      SigFig      — N significant figures, switches to exponential when
//                    |exp10| > expSwitch (default 5)
//      Exponential — always scientific, N decimal places in mantissa
//
//  Backward-compat note: this class has no persistence wired up yet.  The
//  defaults are seeded in the constructor and used in-memory for the
//  session.  Persistence + a settings-page editor land later.
// ─────────────────────────────────────────────────────────────────────────────

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHash>
#include <QSet>
#include <QJsonObject>

class FormatRegistry : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString activeFormatSet READ activeFormatSet WRITE setActiveFormatSet NOTIFY activeFormatSetChanged)

public:
    enum FormatKind { Fixed = 0, SigFig = 1, Exponential = 2 };
    Q_ENUM(FormatKind)

    struct Spec {
        FormatKind kind = Fixed;
        int        digits = 3;
        // For SigFig mode only: when |floor(log10(|v|))| > expSwitch,
        // the formatter switches to scientific notation.  Default 5
        // means values between 1e-5 and 1e+5 stay in fixed notation;
        // anything outside that range flips to exponential.
        int        expSwitch = 5;
    };

    explicit FormatRegistry(QObject* parent = nullptr);

    static FormatRegistry* instance();

    // Project-file persistence for custom number-format sets + active selection
    QJsonObject saveProjectSettings() const;
    void loadProjectSettings(const QJsonObject& obj);

    // ───────── QML-callable formatting ─────────
    //
    // format()       — convert SI value to display unit (via gUnits) then format
    // formatValue()  — value is already in display units; just format
    //
    // Both honor the active format set's spec for the given quantity.
    // Quantities with no registered spec fall back to Fixed/3.
    Q_INVOKABLE QString format     (const QString& quantity, double siValue, const QString& displayUnit) const;
    Q_INVOKABLE QString formatValue(const QString& quantity, double value) const;

    // ───────── Spec inspection (for the future settings editor) ─────────
    Q_INVOKABLE int         decimals  (const QString& quantity) const;  // s.digits
    Q_INVOKABLE int         formatKind(const QString& quantity) const;  // s.kind cast to int
    Q_INVOKABLE int         expSwitch (const QString& quantity) const;
    Q_INVOKABLE QStringList knownQuantities() const;

    // ───────── Format set management ─────────
    QString          activeFormatSet() const { return m_activeSet; }
    Q_INVOKABLE void setActiveFormatSet(const QString& name);
    Q_INVOKABLE QStringList formatSetNames() const;
    Q_INVOKABLE bool isBuiltInFormatSet(const QString& name) const;

    // Editor support (no UI yet; method shapes locked in for later)
    Q_INVOKABLE bool cloneFormatSet(const QString& sourceName, const QString& newName);
    Q_INVOKABLE void setSpec(const QString& setName,
                             const QString& quantity,
                             int kind, int digits, int expSwitch);

    // Inject the sibling UnitRegistry (registered as gUnits on the same QML
    // context).  Call once from main.cpp after both objects are constructed.
    // Without this, format() can't do unit conversion and degrades to
    // formatValue() (assumes the value is already in the display unit).
    void setUnitRegistry(const class UnitRegistry* units) { m_units = units; }

    // Convenience for callers (UnitRegistry uses this).  Returns the active
    // set's spec for this quantity, or a Fixed/3 fallback.
    Spec specFor(const QString& quantity) const;

    // Pure formatter — no quantity lookup, no conversion, just format the value
    // with the given spec.  Used internally and also exposed via formatValue().
    static QString formatWithSpec(double v, const Spec& s);

signals:
    void formatsChanged();           // any spec edited (for live re-render)
    void activeFormatSetChanged();   // user switched active set

private:
    void seedEngineeringDefaults();

    // setName → quantity → spec
    QHash<QString, QHash<QString, Spec>> m_sets;
    QString                              m_activeSet;
    const class UnitRegistry*            m_units = nullptr;  // injected by main.cpp
    QSet<QString> m_builtinSetNames;

    static FormatRegistry* s_instance;
};
