#include "UnitRegistry.h"
#include "FormatRegistry.h"

#include <QRegularExpression>
#include <QtMath>
#include <cmath>

// ─────────────────────────────────────────────────────────────────────────────
//  Reference constants
//
//  Pressure offsets:
//      psig = psia − 14.6959         (atm reference)
//      barg = bar  − 1.01325
//      gauge offsets are stored in Pa: 101325 Pa
//
//  Temperature offsets (toSI: K = display * scale + offset):
//      °C → K:  scale = 1, offset = 273.15
//      °F → K:  scale = 5/9, offset = (459.67) * 5/9 = 255.372222…
//      °R → K:  scale = 5/9, offset = 0
//
//  All other quantities are pure linear (offset = 0).
// ─────────────────────────────────────────────────────────────────────────────

UnitRegistry* UnitRegistry::s_instance = nullptr;

UnitRegistry::UnitRegistry(QObject* parent)
    : QObject(parent)
{
    s_instance = this;

    // ───────── Quantities + units (toSI: si = display*scale + offset) ─────────

    // ─── Temperature  (SI = Kelvin) ───
    registerQuantity("Temperature");
    registerUnit("Temperature", "K",  1.0,            0.0,            { "k", "kelvin" });
    registerUnit("Temperature", "°C", 1.0,            273.15,         { "c", "degC", "deg C", "celsius" });
    registerUnit("Temperature", "°F", 5.0/9.0,        459.67*5.0/9.0, { "f", "degF", "deg F", "fahrenheit" });
    registerUnit("Temperature", "°R", 5.0/9.0,        0.0,            { "r", "degR", "rankine" });

    // ─── Pressure  (SI = Pa) ───
    registerQuantity("Pressure");
    registerUnit("Pressure", "Pa",   1.0,        0.0,    { "pa" });
    registerUnit("Pressure", "kPa",  1.0e3,      0.0,    { "kpa" });
    registerUnit("Pressure", "MPa",  1.0e6,      0.0,    { "mpa" });
    registerUnit("Pressure", "bar",  1.0e5,      0.0,    { });
    registerUnit("Pressure", "atm",  101325.0,   0.0,    { });
    registerUnit("Pressure", "psia", 6894.757,   0.0,    { "psi" });   // psi → psia
    registerUnit("Pressure", "psig", 6894.757,   101325.0, { });
    registerUnit("Pressure", "barg", 1.0e5,      101325.0, { });
    registerUnit("Pressure", "mmHg", 133.3224,   0.0,    { "torr" });
    registerUnit("Pressure", "inH2O",249.0889,   0.0,    { "inH₂O", "inWC" });

    // ─── MassFlow  (SI = kg/s, but Stream stores kg/h — registry stays SI) ───
    // Conversion factor for kg/h → kg/s: divide by 3600.
    registerQuantity("MassFlow");
    registerUnit("MassFlow", "kg/s",   1.0,                 0.0, { "kgps", "kg per s" });
    registerUnit("MassFlow", "kg/h",   1.0/3600.0,          0.0, { "kgph", "kg per h", "kg/hr" });
    registerUnit("MassFlow", "kg/min", 1.0/60.0,            0.0, { });
    registerUnit("MassFlow", "tonne/h",1000.0/3600.0,       0.0, { "t/h", "tph" });
    registerUnit("MassFlow", "lb/h",   0.45359237/3600.0,   0.0, { "lbph", "lb per h", "lb/hr" });
    registerUnit("MassFlow", "lb/s",   0.45359237,          0.0, { "lbps" });
    registerUnit("MassFlow", "Mlb/h",  453.59237/3600.0,    0.0, { "Mlbph" });   // 1000 lb/h
    registerUnit("MassFlow", "g/s",    0.001,               0.0, { });
    registerUnit("MassFlow", "g/min",  0.001/60.0,          0.0, { });

    // ─── MolarFlow  (SI = mol/s, Stream stores kmol/h) ───
    registerQuantity("MolarFlow");
    registerUnit("MolarFlow", "mol/s",   1.0,             0.0, { });
    registerUnit("MolarFlow", "kmol/s",  1000.0,          0.0, { });
    registerUnit("MolarFlow", "mol/h",   1.0/3600.0,      0.0, { "molph" });
    registerUnit("MolarFlow", "kmol/h",  1000.0/3600.0,   0.0, { "kmolph", "kgmol/hr", "kmol/hr" });
    registerUnit("MolarFlow", "lbmol/h", 453.59237/3600.0,0.0, { "lbmolph", "lbmole/hr" });
    registerUnit("MolarFlow", "MMscfd",  1177.17, /* approx, gas STD */ 0.0, { "MMSCFD" }); // 1 MMscfd ≈ 1177.17 mol/s at 60°F, 1 atm

    // ─── VolumeFlow  (SI = m³/s, Stream stores m³/h) ───
    registerQuantity("VolumeFlow");
    registerUnit("VolumeFlow", "m³/s",   1.0,                  0.0, { "m3/s" });
    registerUnit("VolumeFlow", "m³/h",   1.0/3600.0,           0.0, { "m3/h", "m3ph", "m3/hr" });
    registerUnit("VolumeFlow", "L/s",    0.001,                0.0, { });
    registerUnit("VolumeFlow", "L/min",  0.001/60.0,           0.0, { "lpm" });
    registerUnit("VolumeFlow", "mL/min", 1.0e-6/60.0,          0.0, { });
    registerUnit("VolumeFlow", "ft³/h",  0.0283168/3600.0,     0.0, { "ft3/h", "cfh" });
    registerUnit("VolumeFlow", "ft³/s",  0.0283168,            0.0, { "ft3/s", "cfs" });
    registerUnit("VolumeFlow", "bbl/d",  0.158987/86400.0,     0.0, { "bpd", "bblpd" });
    registerUnit("VolumeFlow", "gpm",    0.00378541/60.0,      0.0, { "gal/min" });

    // ─── Power  (SI = W) ───  (Stream stores kW for duties internally elsewhere)
    registerQuantity("Power");
    registerUnit("Power", "W",   1.0,        0.0, { "watt" });
    registerUnit("Power", "kW",  1.0e3,      0.0, { });
    registerUnit("Power", "MW",  1.0e6,      0.0, { });
    registerUnit("Power", "hp",  745.6999,   0.0, { });
    registerUnit("Power", "Btu/h",   0.293071, 0.0, { "btuh", "btu/hr" });
    registerUnit("Power", "MMBtu/h", 293071.0, 0.0, { "mmbtuh", "mmbtu/hr" });
    registerUnit("Power", "kcal/h",  4.184/3.6, 0.0, { });

    // ─── Energy  (SI = J) ───
    registerQuantity("Energy");
    registerUnit("Energy", "J",     1.0,        0.0, { "joule" });
    registerUnit("Energy", "kJ",    1000.0,     0.0, { });
    registerUnit("Energy", "MJ",    1.0e6,      0.0, { });
    registerUnit("Energy", "kcal",  4184.0,     0.0, { });
    registerUnit("Energy", "Btu",   1055.056,   0.0, { });
    registerUnit("Energy", "kWh",   3.6e6,      0.0, { });

    // ─── SpecificEnthalpy  (SI = J/kg, Stream stores kJ/kg) ───
    registerQuantity("SpecificEnthalpy");
    registerUnit("SpecificEnthalpy", "J/kg",   1.0,       0.0, { });
    registerUnit("SpecificEnthalpy", "kJ/kg",  1000.0,    0.0, { });
    registerUnit("SpecificEnthalpy", "MJ/kg",  1.0e6,     0.0, { });
    registerUnit("SpecificEnthalpy", "Btu/lb", 2326.0,    0.0, { "btu/lbm" });
    registerUnit("SpecificEnthalpy", "kcal/kg",4184.0,    0.0, { });

    // ─── SpecificEntropy  (SI = J/(kg·K), Stream stores kJ/(kg·K)) ───
    registerQuantity("SpecificEntropy");
    registerUnit("SpecificEntropy", "J/kg·K",   1.0,    0.0, { "j/kg.k", "j/kg-k" });
    registerUnit("SpecificEntropy", "kJ/kg·K",  1000.0, 0.0, { "kj/kg.k", "kj/kg-k" });
    registerUnit("SpecificEntropy", "Btu/lb·°F",4186.8, 0.0, { "btu/lb.f" });
    registerUnit("SpecificEntropy", "kcal/kg·°C", 4184.0, 0.0, { });

    // ─── SpecificHeat (Cp)  (same dimensions as SpecificEntropy, alias quantity) ───
    registerQuantity("SpecificHeat");
    registerUnit("SpecificHeat", "J/kg·K",   1.0,    0.0, { });
    registerUnit("SpecificHeat", "kJ/kg·K",  1000.0, 0.0, { });
    registerUnit("SpecificHeat", "Btu/lb·°F",4186.8, 0.0, { });
    registerUnit("SpecificHeat", "kcal/kg·°C", 4184.0, 0.0, { });

    // ─── Density  (SI = kg/m³) ───
    registerQuantity("Density");
    registerUnit("Density", "kg/m³",  1.0,       0.0, { "kg/m3" });
    registerUnit("Density", "g/cm³",  1000.0,    0.0, { "g/cm3", "g/cc" });
    registerUnit("Density", "lb/ft³", 16.01846,  0.0, { "lb/ft3", "pcf" });
    registerUnit("Density", "lb/gal", 119.8264,  0.0, { });
    registerUnit("Density", "g/L",    1.0,       0.0, { });

    // ─── Viscosity  (SI = Pa·s, Stream stores cP) ───
    registerQuantity("Viscosity");
    registerUnit("Viscosity", "Pa·s",   1.0,    0.0, { "pa.s", "pa s" });
    registerUnit("Viscosity", "cP",     0.001,  0.0, { "cp", "centipoise", "mPa·s", "mpa.s" });
    registerUnit("Viscosity", "P",      0.1,    0.0, { "poise" });
    registerUnit("Viscosity", "lb/ft·s",1.488164, 0.0, { "lb/ft.s" });

    // ─── ThermalConductivity  (SI = W/(m·K)) ───
    registerQuantity("ThermalConductivity");
    registerUnit("ThermalConductivity", "W/m·K",     1.0,         0.0, { "w/m.k", "w/m-k" });
    registerUnit("ThermalConductivity", "kW/m·K",    1000.0,      0.0, { });
    registerUnit("ThermalConductivity", "Btu/h·ft·°F",1.730735,   0.0, { "btu/h.ft.f" });
    registerUnit("ThermalConductivity", "cal/s·cm·°C", 418.4,     0.0, { });

    // ─── SurfaceTension  (SI = N/m) ───
    registerQuantity("SurfaceTension");
    registerUnit("SurfaceTension", "N/m",    1.0,     0.0, { });
    registerUnit("SurfaceTension", "dyn/cm", 0.001,   0.0, { "mN/m" });
    registerUnit("SurfaceTension", "lbf/ft", 14.5939, 0.0, { });

    // ─── MolarMass  (SI = kg/mol, common = kg/kmol = g/mol) ───
    registerQuantity("MolarMass");
    registerUnit("MolarMass", "kg/mol",  1.0,    0.0, { });
    registerUnit("MolarMass", "kg/kmol", 0.001,  0.0, { "g/mol", "g/gmol" });
    registerUnit("MolarMass", "lb/lbmol",0.001,  0.0, { });   // numerically same as g/mol

    // ─── Time  (used for elapsed-time displays, not strictly needed yet) ───
    registerQuantity("Time");
    registerUnit("Time", "s",   1.0,    0.0, { "sec" });
    registerUnit("Time", "min", 60.0,   0.0, { });
    registerUnit("Time", "h",   3600.0, 0.0, { "hr", "hour" });

    // ─── Dimensionless  (Vapour fraction, Watson K, Cp/Cv ratio, SG, mole fraction) ───
    registerQuantity("Dimensionless");
    registerUnit("Dimensionless", "—", 1.0, 0.0, { "-", "" });

    // ─── VapourFraction  (alias quantity for 0..1 fractions, so QML bindings using
    //      quantity:"VapourFraction" can round-trip through parseInline. Format
    //      registry already has a dedicated 4-decimal formatter for this name.) ───
    registerQuantity("VapourFraction");
    registerUnit("VapourFraction", "—", 1.0, 0.0, { "-", "" });

    // ─── API gravity (a real "unit" in petroleum, but it's a transform of SG) ───
    // We expose it as its own quantity so the panel can bind separately.
    registerQuantity("APIGravity");
    registerUnit("APIGravity", "°API", 1.0, 0.0, { "API" });

    // ─── Unit Sets ───────────────────────────────────────────────────────
    // SI (Process)  — what you'd find in HYSYS's "SI" set
    registerUnitSet("SI", {
        { "Temperature",          "°C"     },     // °C is SI's "process default" — pure K is a separate "Strict SI" toggle if needed
        { "Pressure",             "bar"    },
        { "MassFlow",             "kg/h"   },
        { "MolarFlow",            "kmol/h" },
        { "VolumeFlow",           "m³/h"   },
        { "Power",                "kW"     },
        { "Energy",               "kJ"     },
        { "SpecificEnthalpy",     "kJ/kg"  },
        { "SpecificEntropy",      "kJ/kg·K"},
        { "SpecificHeat",         "kJ/kg·K"},
        { "Density",              "kg/m³"  },
        { "Viscosity",            "cP"     },
        { "ThermalConductivity",  "W/m·K"  },
        { "SurfaceTension",       "N/m"    },
        { "MolarMass",            "kg/kmol"},
        { "Time",                 "s"      },
        { "Dimensionless",        "—"      },
        { "APIGravity",           "°API"   },
    });

    // Field (US Customary) — what HYSYS calls "Field"
    registerUnitSet("Field", {
        { "Temperature",          "°F"      },
        { "Pressure",             "psia"    },
        { "MassFlow",             "lb/h"    },
        { "MolarFlow",            "lbmol/h" },
        { "VolumeFlow",           "ft³/h"   },
        { "Power",                "Btu/h"   },
        { "Energy",               "Btu"     },
        { "SpecificEnthalpy",     "Btu/lb"  },
        { "SpecificEntropy",      "Btu/lb·°F" },
        { "SpecificHeat",         "Btu/lb·°F" },
        { "Density",              "lb/ft³"  },
        { "Viscosity",            "cP"      },
        { "ThermalConductivity",  "Btu/h·ft·°F" },
        { "SurfaceTension",       "dyn/cm"  },
        { "MolarMass",            "lb/lbmol"},
        { "Time",                 "min"     },
        { "Dimensionless",        "—"       },
        { "APIGravity",           "°API"    },
    });

    // British — UK process / oil-and-gas convention
    //   kPa absolute (rather than bar) is the historical UK process default;
    //   °C for temperature; mass and molar flow stay metric;
    //   energy/duty in kJ and kW (no Btu).  cP and N/m kept for direct
    //   comparison with vendor data sheets (most UK suppliers report cP).
    registerUnitSet("British", {
        { "Temperature",          "°C"      },
        { "Pressure",             "kPa"     },     // UK process default — kPa absolute
        { "MassFlow",             "kg/h"    },
        { "MolarFlow",            "kmol/h"  },
        { "VolumeFlow",           "m³/h"    },
        { "Power",                "kW"      },
        { "Energy",               "kJ"      },
        { "SpecificEnthalpy",     "kJ/kg"   },
        { "SpecificEntropy",      "kJ/kg·K" },
        { "SpecificHeat",         "kJ/kg·K" },
        { "Density",              "kg/m³"   },
        { "Viscosity",            "cP"      },
        { "ThermalConductivity",  "W/m·K"   },
        { "SurfaceTension",       "N/m"     },
        { "MolarMass",            "kg/kmol" },
        { "Time",                 "s"       },
        { "Dimensionless",        "—"       },
        { "APIGravity",           "°API"    },
    });

    m_activeSet = "SI";   // default
}


UnitRegistry* UnitRegistry::instance()
{
   return s_instance;
}

QJsonObject UnitRegistry::saveProjectSettings() const
{
   QJsonObject out;
   out[QStringLiteral("activeSet")] = m_activeSet;

   QJsonObject customSets;
   for (auto it = m_unitSets.constBegin(); it != m_unitSets.constEnd(); ++it) {
      if (m_builtinUnitSets.contains(it.key()))
         continue;

      QJsonObject setObj;
      for (auto qit = it.value().constBegin(); qit != it.value().constEnd(); ++qit)
         setObj[ qit.key() ] = qit.value();
      customSets[it.key()] = setObj;
   }
   out[QStringLiteral("customSets")] = customSets;
   return out;
}

void UnitRegistry::loadProjectSettings(const QJsonObject& obj)
{
   // Remove existing custom sets; keep built-ins.
   QStringList toRemove;
   for (auto it = m_unitSets.constBegin(); it != m_unitSets.constEnd(); ++it) {
      if (!m_builtinUnitSets.contains(it.key()))
         toRemove.push_back(it.key());
   }
   for (const QString& name : toRemove)
      m_unitSets.remove(name);

   const QJsonObject customSets = obj.value(QStringLiteral("customSets")).toObject();
   for (auto sit = customSets.constBegin(); sit != customSets.constEnd(); ++sit) {
      const QString setName = sit.key().trimmed();
      if (setName.isEmpty() || m_builtinUnitSets.contains(setName))
         continue;

      QHash<QString, QString> defaults;
      const QJsonObject setObj = sit.value().toObject();
      for (auto qit = setObj.constBegin(); qit != setObj.constEnd(); ++qit) {
         const QString quantity = qit.key();
         const QString unit = qit.value().toString();
         if (isCompatible(quantity, unit))
            defaults.insert(quantity, unit);
      }
      if (!defaults.isEmpty())
         registerUnitSet(setName, defaults, false);
   }

   const QString requestedActive = obj.value(QStringLiteral("activeSet")).toString();
   if (!requestedActive.isEmpty() && m_unitSets.contains(requestedActive))
      m_activeSet = requestedActive;
   else if (!m_unitSets.contains(m_activeSet))
      m_activeSet = QStringLiteral("SI");

   emit activeUnitSetChanged();
   emit unitsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Internal registration helpers
// ─────────────────────────────────────────────────────────────────────────────
void UnitRegistry::registerQuantity(const QString& q) {
    if (!m_quantities.contains(q)) m_quantities.insert(q, Quantity{ q, {} });
}

void UnitRegistry::registerUnit(const QString& quantity,
                                const QString& name,
                                double scale, double offset,
                                const QStringList& aliases,
                                const QString& display)
{
    auto it = m_quantities.find(quantity);
    if (it == m_quantities.end()) return;
    Unit u; u.name = name; u.scale = scale; u.offset = offset; u.aliases = aliases;
    u.display = display.isEmpty() ? name : display;
    it->units.append(u);
}

void UnitRegistry::registerUnitSet(const QString& set, const QHash<QString,QString>& defaults, bool builtIn) {
    m_unitSets.insert(set, defaults);
    if (builtIn)
        m_builtinUnitSets.insert(set);
}

const UnitRegistry::Unit*
UnitRegistry::findUnit(const QString& quantity, const QString& unit) const {
    auto qit = m_quantities.constFind(quantity);
    if (qit == m_quantities.constEnd()) return nullptr;
    const QString needle = unit.trimmed();
    for (const Unit& u : qit->units) {
        if (u.name.compare(needle, Qt::CaseInsensitive) == 0) return &u;
        for (const QString& a : u.aliases)
            if (a.compare(needle, Qt::CaseInsensitive) == 0) return &u;
    }
    return nullptr;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Conversion API
// ─────────────────────────────────────────────────────────────────────────────
double UnitRegistry::toSI(const QString& q, double display, const QString& unit) const {
    const Unit* u = findUnit(q, unit);
    if (!u) return display;             // graceful fallback: no conversion
    return display * u->scale + u->offset;
}

double UnitRegistry::fromSI(const QString& q, double siValue, const QString& unit) const {
    const Unit* u = findUnit(q, unit);
    if (!u || u->scale == 0.0) return siValue;
    return (siValue - u->offset) / u->scale;
}

QStringList UnitRegistry::unitsFor(const QString& q) const {
    QStringList out;
    auto it = m_quantities.constFind(q);
    if (it == m_quantities.constEnd()) return out;
    for (const Unit& u : it->units) out.append(u.name);
    return out;
}

QStringList UnitRegistry::knownQuantities() const {
   QStringList out = m_quantities.keys();
   out.sort(Qt::CaseInsensitive);
   return out;
}

QString UnitRegistry::defaultUnit(const QString& q) const {
    return unitForSet(m_activeSet, q);
}

QString UnitRegistry::unitForSet(const QString& setName, const QString& q) const {
    auto sit = m_unitSets.constFind(setName);
    if (sit == m_unitSets.constEnd()) return QString();
    auto qit = sit->constFind(q);
    if (qit == sit->constEnd()) return QString();
    return *qit;
}

bool UnitRegistry::isCompatible(const QString& q, const QString& unit) const {
    return findUnit(q, unit) != nullptr;
}

QString UnitRegistry::format(const QString& q, double siValue, const QString& unit, int decimals) const {
    if (!std::isfinite(siValue)) return QStringLiteral("—");
    const double v = fromSI(q, siValue, unit);
    if (!std::isfinite(v)) return QStringLiteral("—");

    // decimals < 0  →  consult gFormats for the per-quantity spec.
    // decimals >= 0 →  caller wants explicit fixed-N formatting (back-compat).
    if (decimals < 0) {
        if (m_formats)
            return FormatRegistry::formatWithSpec(v, m_formats->specFor(q));
        // No FormatRegistry injected — use a 3-dp fallback.  This path is hit
        // in pure-C++ unit-test contexts where main.cpp's injection didn't run.
        return QString::number(v, 'f', 3);
    }
    return QString::number(v, 'f', decimals);
}

QVariantList UnitRegistry::unitOptionsFor(const QString& q, double siValue, int decimals) const {
    QVariantList out;
    auto it = m_quantities.constFind(q);
    if (it == m_quantities.constEnd()) return out;

    const FormatRegistry::Spec spec = (decimals < 0 && m_formats)
        ? m_formats->specFor(q)
        : FormatRegistry::Spec{};

    for (const Unit& u : it->units) {
        QVariantMap m;
        m["unit"] = u.name;
        if (!std::isfinite(siValue)) {
            m["preview"] = QStringLiteral("—");
        } else {
            const double v = fromSI(q, siValue, u.name);
            if (decimals >= 0) {
                m["preview"] = QString::number(v, 'f', decimals);
            } else if (m_formats) {
                m["preview"] = FormatRegistry::formatWithSpec(v, spec);
            } else {
                m["preview"] = QString::number(v, 'f', 3);
            }
        }
        out.append(m);
    }
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Inline parser   "145 psia"  →  { ok, valueSI, unit, error }
//
//  Rules:
//    - Bare number  → interpret as `assumeUnit`
//    - Number + unit token → parse unit against the quantity, convert
//    - Unparseable / unknown unit → ok=false with error string
//    - Decimal commas accepted (replace , with .)
// ─────────────────────────────────────────────────────────────────────────────
QVariantMap UnitRegistry::parseInline(const QString& q,
                                      const QString& text,
                                      const QString& assumeUnit) const
{
    QVariantMap r;
    r["ok"]      = false;
    r["valueSI"] = 0.0;
    r["unit"]    = assumeUnit;
    r["error"]   = QString();

    QString s = text.trimmed();
    if (s.isEmpty()) { r["error"] = "empty"; return r; }
    s.replace(',', '.');                                   // EU decimal

    static const QRegularExpression re(QStringLiteral(
        R"(^\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*(.*?)\s*$)"));
    QRegularExpressionMatch m = re.match(s);
    if (!m.hasMatch()) { r["error"] = "could not parse number"; return r; }

    bool numOk = false;
    const double display = m.captured(1).toDouble(&numOk);
    if (!numOk) { r["error"] = "invalid number"; return r; }

    const QString typed = m.captured(2).trimmed();
    const QString unit  = typed.isEmpty() ? assumeUnit : typed;

    const Unit* u = findUnit(q, unit);
    if (!u) {
        r["error"] = QStringLiteral("unit '%1' not compatible with %2").arg(unit, q);
        return r;
    }

    r["ok"]      = true;
    r["valueSI"] = display * u->scale + u->offset;
    r["unit"]    = u->name;
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Unit Set switch
// ─────────────────────────────────────────────────────────────────────────────
QStringList UnitRegistry::availableUnitSets() const {
    return unitSetNames();
}

QStringList UnitRegistry::unitSetNames() const {
    auto names = m_unitSets.keys();
    names.sort();
    return names;
}

bool UnitRegistry::isBuiltInUnitSet(const QString& name) const {
    return m_builtinUnitSets.contains(name);
}

void UnitRegistry::setActiveUnitSet(const QString& name) {
    if (!m_unitSets.contains(name) || m_activeSet == name) return;
    m_activeSet = name;
    emit activeUnitSetChanged();
    emit unitsChanged();
}

bool UnitRegistry::cloneUnitSet(const QString& sourceName, const QString& newName) {
    const QString trimmed = newName.trimmed();
    if (trimmed.isEmpty() || m_unitSets.contains(trimmed) || !m_unitSets.contains(sourceName))
        return false;
    m_unitSets.insert(trimmed, m_unitSets.value(sourceName));
    return true;
}

bool UnitRegistry::setUnitForQuantity(const QString& setName, const QString& quantity, const QString& unit) {
    if (m_builtinUnitSets.contains(setName) || !m_unitSets.contains(setName) || !isCompatible(quantity, unit))
        return false;
    m_unitSets[setName][quantity] = unit;
    if (setName == m_activeSet)
        emit unitsChanged();
    return true;
}
