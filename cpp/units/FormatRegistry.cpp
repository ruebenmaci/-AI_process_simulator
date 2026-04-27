#include "FormatRegistry.h"
#include "UnitRegistry.h"

#include <cmath>
#include <QJsonObject>

FormatRegistry* FormatRegistry::s_instance = nullptr;


FormatRegistry* FormatRegistry::instance()
{
    return s_instance;
}

QJsonObject FormatRegistry::saveProjectSettings() const
{
    QJsonObject out;
    out[QStringLiteral("activeSet")] = m_activeSet;

    QJsonObject customSets;
    for (auto it = m_sets.constBegin(); it != m_sets.constEnd(); ++it) {
        if (m_builtinSetNames.contains(it.key()))
            continue;

        QJsonObject setObj;
        for (auto qit = it.value().constBegin(); qit != it.value().constEnd(); ++qit) {
            QJsonObject specObj;
            specObj[QStringLiteral("kind")] = static_cast<int>(qit.value().kind);
            specObj[QStringLiteral("digits")] = qit.value().digits;
            specObj[QStringLiteral("expSwitch")] = qit.value().expSwitch;
            setObj[qit.key()] = specObj;
        }
        customSets[it.key()] = setObj;
    }
    out[QStringLiteral("customSets")] = customSets;
    return out;
}

void FormatRegistry::loadProjectSettings(const QJsonObject& obj)
{
    QStringList toRemove;
    for (auto it = m_sets.constBegin(); it != m_sets.constEnd(); ++it) {
        if (!m_builtinSetNames.contains(it.key()))
            toRemove.push_back(it.key());
    }
    for (const QString& name : toRemove)
        m_sets.remove(name);

    const QJsonObject customSets = obj.value(QStringLiteral("customSets")).toObject();
    for (auto sit = customSets.constBegin(); sit != customSets.constEnd(); ++sit) {
        const QString setName = sit.key().trimmed();
        if (setName.isEmpty() || m_builtinSetNames.contains(setName))
            continue;

        QHash<QString, Spec> setSpecs;
        const QJsonObject setObj = sit.value().toObject();
        for (auto qit = setObj.constBegin(); qit != setObj.constEnd(); ++qit) {
            const QJsonObject specObj = qit.value().toObject();
            Spec s;
            s.kind = static_cast<FormatKind>(specObj.value(QStringLiteral("kind")).toInt(0));
            s.digits = std::max(0, specObj.value(QStringLiteral("digits")).toInt(3));
            s.expSwitch = std::max(0, specObj.value(QStringLiteral("expSwitch")).toInt(5));
            setSpecs.insert(qit.key(), s);
        }
        if (!setSpecs.isEmpty())
            m_sets.insert(setName, setSpecs);
    }

    const QString requestedActive = obj.value(QStringLiteral("activeSet")).toString();
    if (!requestedActive.isEmpty() && m_sets.contains(requestedActive))
        m_activeSet = requestedActive;
    else if (!m_sets.contains(m_activeSet))
        m_activeSet = QStringLiteral("Engineering Default");

    emit activeFormatSetChanged();
    emit formatsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Engineering Default format spec — calibrated to HYSYS visual conventions
//  with magnitude-aware "auto" (SigFig) for quantities that span orders of
//  magnitude.  Pattern:
//
//    Fixed  — used when a quantity always sits in a known narrow range
//             (temperatures in °C/°F, fractions, MW, density, omega, SG)
//    SigFig — used when a quantity can span orders of magnitude
//             (energy flow, volumetric flow, viscosity, thermal cond, etc.)
//
//  These ship as the read-only "Engineering Default" set.  When the
//  settings-page editor lands, users will be able to clone it and edit
//  per-quantity formats in their own named set.
// ─────────────────────────────────────────────────────────────────────────────

FormatRegistry::FormatRegistry(QObject* parent)
    : QObject(parent)
{
    if (!s_instance)
        s_instance = this;
    seedEngineeringDefaults();
    m_activeSet = QStringLiteral("Engineering Default");
}

void FormatRegistry::seedEngineeringDefaults()
{
    QHash<QString, Spec> d;

    auto fix = [](int dp)             { return Spec{ Fixed,  dp, 5 }; };
    auto sig = [](int n, int sw = 5)  { return Spec{ SigFig, n,  sw }; };

    // ── Temperature & pressure ────────────────────────────────────────────
    d.insert("Temperature",         fix(2));   // 25.00 °C
    d.insert("DeltaTemperature",    fix(2));   // 5.00 ΔK
    d.insert("Pressure",            fix(1));   // 2175.0 kPa
    d.insert("DeltaPressure",       fix(1));   // 12.5 kPa

    // ── Flows ─────────────────────────────────────────────────────────────
    d.insert("MassFlow",            sig(4));   // 100000 / 12.34 / 1.234e+07
    d.insert("MolarFlow",           fix(3));   // 467.575 kmol/h
    d.insert("VolumeFlow",          sig(4));   // 0.1299 / 1.234e+04
    d.insert("StdLiqVolFlow",       sig(4));
    d.insert("EnergyFlow",          sig(4));   // duties — wide range
    d.insert("HeatFlow",            sig(4));   // alias used in some panels
    d.insert("Power",               sig(4));

    // ── Compositions & ratios ─────────────────────────────────────────────
    d.insert("MassFraction",        fix(4));   // 0.0450
    d.insert("MoleFraction",        fix(4));   // 0.0450
    d.insert("VapourFraction",      fix(4));   // 0.0000 / 1.0000
    d.insert("KValue",              sig(4));   // 12.34 / 0.001234

    // ── Component-level scalars ───────────────────────────────────────────
    d.insert("MolarMass",           fix(2));   // 78.11 kg/kmol
    d.insert("Acentric",            fix(4));   // 0.0470
    d.insert("Omega",               fix(4));   // alias for Acentric
    d.insert("SpecificGravity",     fix(3));   // 0.543

    // ── Bulk physical properties ──────────────────────────────────────────
    d.insert("Density",             fix(2));   // 876.45 kg/m³
    d.insert("MolarVolume",         sig(4));
    d.insert("SpecificEnthalpy",    sig(4));   // wide range
    d.insert("SpecificEntropy",     fix(3));
    d.insert("SpecificHeat",        fix(3));
    d.insert("Viscosity",           sig(4));   // 0.8945 cP / 2.345e-05 Pa·s
    d.insert("ThermalConductivity", sig(4));
    d.insert("SurfaceTension",      fix(3));
    d.insert("Energy",              sig(4));

    // ── Geometry ──────────────────────────────────────────────────────────
    d.insert("Length",              fix(3));
    d.insert("Diameter",            fix(3));
    d.insert("Area",                sig(4));
    d.insert("Volume",              sig(4));

    // ── Time & misc ───────────────────────────────────────────────────────
    d.insert("Time",                sig(4));
    d.insert("Percentage",          fix(2));
    d.insert("Dimensionless",       fix(0));   // counts / integers
    d.insert("Count",               fix(0));

    m_sets.insert(QStringLiteral("Engineering Default"), d);
    if (!m_builtinSetNames.contains(QStringLiteral("Engineering Default")))
        m_builtinSetNames.insert(QStringLiteral("Engineering Default"));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pure formatter.  No quantity lookup, no conversion.  This is the heart
//  of the registry — every formatted number flows through here.
// ─────────────────────────────────────────────────────────────────────────────
QString FormatRegistry::formatWithSpec(double v, const Spec& s)
{
    if (!std::isfinite(v)) return QStringLiteral("—");

    switch (s.kind) {
    case Fixed: {
        int decimals = std::max(0, s.digits);

        // ── Precision-preservation rule for small values ────────────────────
        // When |v| < 1 and the spec's fixed decimals would drop the value
        // below kMinSigFigsForSmallValues significant digits, bump the decimal
        // count so at least that many sig figs survive. Prevents, e.g.,
        // MolarMass 0.11630 kg/mol displaying as "0.12" at Fixed/2 — the rule
        // bumps it to "0.1163" (4 sig figs).
        //
        // Integer part is zero, so sig figs = decimals - leadingZeros, where
        // leadingZeros is the count of zeros between the decimal point and
        // the first non-zero digit. For v in [0.1, 1): leadingZeros = 0.
        // For v in [0.01, 0.1): leadingZeros = 1. Etc.
        constexpr int kMinSigFigsForSmallValues = 4;
        if (v != 0.0 && std::fabs(v) < 1.0) {
            const int leadingZeros = -static_cast<int>(
                std::floor(std::log10(std::fabs(v)))) - 1;
            const int neededDecimals = leadingZeros + kMinSigFigsForSmallValues;
            if (neededDecimals > decimals)
                decimals = neededDecimals;
        }
        return QString::number(v, 'f', decimals);
    }

    case Exponential:
        return QString::number(v, 'e', std::max(0, s.digits));

    case SigFig: {
        // Zero is a special case — there's no log of zero.  Render with
        // (digits-1) decimals so a 4-sig-fig spec yields "0.000".
        if (v == 0.0)
            return QString::number(0.0, 'f', std::max(0, s.digits - 1));

        const double absV = std::fabs(v);
        const int    exp  = static_cast<int>(std::floor(std::log10(absV)));

        // Magnitude too extreme — flip to scientific (digits-1 mantissa decimals).
        if (std::abs(exp) > s.expSwitch)
            return QString::number(v, 'e', std::max(0, s.digits - 1));

        // Fixed notation, decimals chosen so total significant figures = digits.
        // For v=123.45 with digits=4 → exp=2 → decimals = 4-1-2 = 1 → "123.5"
        // For v=0.04567 with digits=4 → exp=-2 → decimals = 4-1-(-2) = 5 → "0.04567"
        const int decimals = std::max(0, s.digits - 1 - exp);
        return QString::number(v, 'f', decimals);
    }
    }
    return QString::number(v);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Active-set lookup — falls back to Engineering Default if the active
//  set is missing the requested quantity (e.g. user-cloned set hasn't
//  added a row for an exotic quantity yet).
// ─────────────────────────────────────────────────────────────────────────────
FormatRegistry::Spec FormatRegistry::specFor(const QString& quantity) const
{
    const auto activeIt = m_sets.constFind(m_activeSet);
    if (activeIt != m_sets.constEnd()) {
        const auto specIt = activeIt->constFind(quantity);
        if (specIt != activeIt->constEnd())
            return *specIt;
    }
    // Fall back to Engineering Default
    const auto defaultIt = m_sets.constFind(QStringLiteral("Engineering Default"));
    if (defaultIt != m_sets.constEnd()) {
        const auto specIt = defaultIt->constFind(quantity);
        if (specIt != defaultIt->constEnd())
            return *specIt;
    }
    // Last-resort fallback for unregistered quantities
    return Spec{ Fixed, 3, 5 };
}

// ─────────────────────────────────────────────────────────────────────────────
//  QML-facing formatting entry points
// ─────────────────────────────────────────────────────────────────────────────
QString FormatRegistry::format(const QString& quantity,
                               double siValue,
                               const QString& displayUnit) const
{
    if (!std::isfinite(siValue)) return QStringLiteral("—");

    // If a UnitRegistry has been injected (the normal case in main.cpp), do
    // SI → display-unit conversion first.  If not (pure C++ tests), treat
    // siValue as already being in the display unit.
    const double display = m_units
        ? m_units->fromSI(quantity, siValue, displayUnit)
        : siValue;

    if (!std::isfinite(display)) return QStringLiteral("—");
    return formatWithSpec(display, specFor(quantity));
}

QString FormatRegistry::formatValue(const QString& quantity, double value) const
{
    return formatWithSpec(value, specFor(quantity));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Spec inspection
// ─────────────────────────────────────────────────────────────────────────────
int FormatRegistry::decimals(const QString& quantity) const
{
    return specFor(quantity).digits;
}

int FormatRegistry::formatKind(const QString& quantity) const
{
    return static_cast<int>(specFor(quantity).kind);
}

int FormatRegistry::expSwitch(const QString& quantity) const
{
    return specFor(quantity).expSwitch;
}

QStringList FormatRegistry::knownQuantities() const
{
    QStringList out;
    const auto activeIt = m_sets.constFind(m_activeSet);
    if (activeIt != m_sets.constEnd())
        out = activeIt->keys();
    out.sort();
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Format set management
// ─────────────────────────────────────────────────────────────────────────────
void FormatRegistry::setActiveFormatSet(const QString& name)
{
    if (name == m_activeSet) return;
    if (!m_sets.contains(name)) {
        qWarning("FormatRegistry::setActiveFormatSet: unknown set '%s'",
                 qUtf8Printable(name));
        return;
    }
    m_activeSet = name;
    emit activeFormatSetChanged();
    emit formatsChanged();
}

QStringList FormatRegistry::formatSetNames() const
{
    auto names = m_sets.keys();
    names.sort();
    return names;
}

bool FormatRegistry::isBuiltInFormatSet(const QString& name) const
{
    return m_builtinSetNames.contains(name);
}

bool FormatRegistry::cloneFormatSet(const QString& sourceName, const QString& newName)
{
    const QString trimmed = newName.trimmed();
    if (trimmed.isEmpty() || m_sets.contains(trimmed)) {
        qWarning("FormatRegistry::cloneFormatSet: bad target name '%s'",
                 qUtf8Printable(newName));
        return false;
    }
    const auto srcIt = m_sets.constFind(sourceName);
    if (srcIt == m_sets.constEnd()) {
        qWarning("FormatRegistry::cloneFormatSet: unknown source '%s'",
                 qUtf8Printable(sourceName));
        return false;
    }
    m_sets.insert(trimmed, *srcIt);
    emit formatsChanged();
    return true;
}

void FormatRegistry::setSpec(const QString& setName,
                             const QString& quantity,
                             int kind, int digits, int expSwitch)
{
    // Prevent edits to the built-in default — it must remain a stable baseline
    // that users can clone from.  This mirrors HYSYS's read-only SI/Field sets.
    if (setName == QStringLiteral("Engineering Default")) {
        qWarning("FormatRegistry::setSpec: 'Engineering Default' is read-only; "
                 "clone it first.");
        return;
    }
    auto it = m_sets.find(setName);
    if (it == m_sets.end()) {
        qWarning("FormatRegistry::setSpec: unknown set '%s'",
                 qUtf8Printable(setName));
        return;
    }
    Spec s;
    s.kind      = static_cast<FormatKind>(kind);
    s.digits    = std::max(0, digits);
    s.expSwitch = std::max(0, expSwitch);
    (*it)[quantity] = s;
    if (setName == m_activeSet)
        emit formatsChanged();
}
