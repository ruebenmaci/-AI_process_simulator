#include "ComponentRecord.h"

#include <QJsonDocument>

namespace sim {
   namespace {

      static std::optional<double> parseOptionalDouble(const QJsonValue& v)
      {
         if (v.isDouble()) return v.toDouble();
         if (v.isString()) {
            bool ok = false;
            const double d = v.toString().toDouble(&ok);
            if (ok) return d;
         }
         return std::nullopt;
      }

      static std::optional<double> parseOptionalDouble(const QVariant& v)
      {
         if (!v.isValid() || v.isNull()) return std::nullopt;
         bool ok = false;
         const double d = v.toDouble(&ok);
         if (ok) return d;
         return std::nullopt;
      }

      static void putOptional(QJsonObject& obj, const char* key, const std::optional<double>& value)
      {
         if (value.has_value()) obj.insert(QString::fromUtf8(key), *value);
         else obj.insert(QString::fromUtf8(key), QJsonValue::Null);
      }

      static QVariant optionalToVariant(const std::optional<double>& value)
      {
         return value.has_value() ? QVariant(*value) : QVariant();
      }

      static QStringList jsonArrayToStringList(const QJsonValue& v)
      {
         QStringList out;
         for (const auto& item : v.toArray()) out.push_back(item.toString());
         return out;
      }

      static QJsonArray stringListToJsonArray(const QStringList& list)
      {
         QJsonArray arr;
         for (const auto& s : list) arr.append(s);
         return arr;
      }

   } // namespace

   QString componentTypeToString(ComponentType type)
   {
      switch (type) {
      case ComponentType::Pure: return QStringLiteral("pure");
      case ComponentType::PseudoComponent: return QStringLiteral("pseudo-component");
      case ComponentType::Ion: return QStringLiteral("ion");
      case ComponentType::Salt: return QStringLiteral("salt");
      case ComponentType::Solid: return QStringLiteral("solid");
      case ComponentType::UserDefined: return QStringLiteral("user-defined");
      }
      return QStringLiteral("pure");
   }

   ComponentType componentTypeFromString(const QString& value)
   {
      const QString normalized = value.trimmed().toLower();
      if (normalized == QStringLiteral("pseudo-component") || normalized == QStringLiteral("pseudocomponent")) return ComponentType::PseudoComponent;
      if (normalized == QStringLiteral("ion")) return ComponentType::Ion;
      if (normalized == QStringLiteral("salt")) return ComponentType::Salt;
      if (normalized == QStringLiteral("solid")) return ComponentType::Solid;
      if (normalized == QStringLiteral("user-defined") || normalized == QStringLiteral("userdefined")) return ComponentType::UserDefined;
      return ComponentType::Pure;
   }

   QVariantMap ComponentRecord::toVariantMap() const
   {
      QVariantMap out;
      out.insert(QStringLiteral("id"), id);
      out.insert(QStringLiteral("name"), name);
      out.insert(QStringLiteral("formula"), formula);
      out.insert(QStringLiteral("cas"), cas);
      out.insert(QStringLiteral("family"), family);
      out.insert(QStringLiteral("componentType"), componentTypeToString(componentType));
      out.insert(QStringLiteral("aliases"), aliases);
      out.insert(QStringLiteral("tags"), tags);
      out.insert(QStringLiteral("phaseCapabilities"), phaseCapabilities);
      out.insert(QStringLiteral("molarMass"), optionalToVariant(molarMass));
      out.insert(QStringLiteral("normalBoilingPointK"), optionalToVariant(normalBoilingPointK));
      out.insert(QStringLiteral("criticalTemperatureK"), optionalToVariant(criticalTemperatureK));
      out.insert(QStringLiteral("criticalPressurePa"), optionalToVariant(criticalPressurePa));
      out.insert(QStringLiteral("acentricFactor"), optionalToVariant(acentricFactor));
      out.insert(QStringLiteral("criticalVolumeM3PerKmol"), optionalToVariant(criticalVolumeM3PerKmol));
      out.insert(QStringLiteral("criticalCompressibility"), optionalToVariant(criticalCompressibility));
      out.insert(QStringLiteral("specificGravity60F"), optionalToVariant(specificGravity60F));
      out.insert(QStringLiteral("watsonK"), optionalToVariant(watsonK));
      out.insert(QStringLiteral("volumeShiftDelta"), optionalToVariant(volumeShiftDelta));
      out.insert(QStringLiteral("source"), source);
      out.insert(QStringLiteral("notes"), notes);
      out.insert(QStringLiteral("isPseudoComponent"), isPseudoComponent());
      return out;
   }

   QJsonObject ComponentRecord::toJson() const
   {
      QJsonObject obj;
      obj.insert(QStringLiteral("id"), id);
      obj.insert(QStringLiteral("name"), name);
      obj.insert(QStringLiteral("formula"), formula);
      obj.insert(QStringLiteral("cas"), cas);
      obj.insert(QStringLiteral("family"), family);
      obj.insert(QStringLiteral("componentType"), componentTypeToString(componentType));
      obj.insert(QStringLiteral("aliases"), stringListToJsonArray(aliases));
      obj.insert(QStringLiteral("tags"), stringListToJsonArray(tags));
      obj.insert(QStringLiteral("phaseCapabilities"), stringListToJsonArray(phaseCapabilities));
      putOptional(obj, "molarMass", molarMass);
      putOptional(obj, "normalBoilingPointK", normalBoilingPointK);
      putOptional(obj, "criticalTemperatureK", criticalTemperatureK);
      putOptional(obj, "criticalPressurePa", criticalPressurePa);
      putOptional(obj, "acentricFactor", acentricFactor);
      putOptional(obj, "criticalVolumeM3PerKmol", criticalVolumeM3PerKmol);
      putOptional(obj, "criticalCompressibility", criticalCompressibility);
      putOptional(obj, "specificGravity60F", specificGravity60F);
      putOptional(obj, "watsonK", watsonK);
      putOptional(obj, "volumeShiftDelta", volumeShiftDelta);
      obj.insert(QStringLiteral("source"), source);
      obj.insert(QStringLiteral("notes"), notes);
      return obj;
   }

   ComponentRecord ComponentRecord::fromVariantMap(const QVariantMap& map)
   {
      ComponentRecord rec;
      rec.id = map.value(QStringLiteral("id")).toString();
      rec.name = map.value(QStringLiteral("name")).toString();
      rec.formula = map.value(QStringLiteral("formula")).toString();
      rec.cas = map.value(QStringLiteral("cas")).toString();
      rec.family = map.value(QStringLiteral("family")).toString();
      rec.componentType = componentTypeFromString(map.value(QStringLiteral("componentType")).toString());
      rec.aliases = map.value(QStringLiteral("aliases")).toStringList();
      rec.tags = map.value(QStringLiteral("tags")).toStringList();
      rec.phaseCapabilities = map.value(QStringLiteral("phaseCapabilities")).toStringList();
      rec.molarMass = parseOptionalDouble(map.value(QStringLiteral("molarMass")));
      rec.normalBoilingPointK = parseOptionalDouble(map.value(QStringLiteral("normalBoilingPointK")));
      rec.criticalTemperatureK = parseOptionalDouble(map.value(QStringLiteral("criticalTemperatureK")));
      rec.criticalPressurePa = parseOptionalDouble(map.value(QStringLiteral("criticalPressurePa")));
      rec.acentricFactor = parseOptionalDouble(map.value(QStringLiteral("acentricFactor")));
      rec.criticalVolumeM3PerKmol = parseOptionalDouble(map.value(QStringLiteral("criticalVolumeM3PerKmol")));
      rec.criticalCompressibility = parseOptionalDouble(map.value(QStringLiteral("criticalCompressibility")));
      rec.specificGravity60F = parseOptionalDouble(map.value(QStringLiteral("specificGravity60F")));
      rec.watsonK = parseOptionalDouble(map.value(QStringLiteral("watsonK")));
      rec.volumeShiftDelta = parseOptionalDouble(map.value(QStringLiteral("volumeShiftDelta")));
      rec.source = map.value(QStringLiteral("source")).toString();
      rec.notes = map.value(QStringLiteral("notes")).toString();
      return rec;
   }

   ComponentRecord ComponentRecord::fromJson(const QJsonObject& obj)
   {
      ComponentRecord rec;
      rec.id = obj.value(QStringLiteral("id")).toString();
      rec.name = obj.value(QStringLiteral("name")).toString();
      rec.formula = obj.value(QStringLiteral("formula")).toString();
      rec.cas = obj.value(QStringLiteral("cas")).toString();
      rec.family = obj.value(QStringLiteral("family")).toString();
      rec.componentType = componentTypeFromString(obj.value(QStringLiteral("componentType")).toString());
      rec.aliases = jsonArrayToStringList(obj.value(QStringLiteral("aliases")));
      rec.tags = jsonArrayToStringList(obj.value(QStringLiteral("tags")));
      rec.phaseCapabilities = jsonArrayToStringList(obj.value(QStringLiteral("phaseCapabilities")));
      rec.molarMass = parseOptionalDouble(obj.value(QStringLiteral("molarMass")));
      rec.normalBoilingPointK = parseOptionalDouble(obj.value(QStringLiteral("normalBoilingPointK")));
      rec.criticalTemperatureK = parseOptionalDouble(obj.value(QStringLiteral("criticalTemperatureK")));
      rec.criticalPressurePa = parseOptionalDouble(obj.value(QStringLiteral("criticalPressurePa")));
      rec.acentricFactor = parseOptionalDouble(obj.value(QStringLiteral("acentricFactor")));
      rec.criticalVolumeM3PerKmol = parseOptionalDouble(obj.value(QStringLiteral("criticalVolumeM3PerKmol")));
      rec.criticalCompressibility = parseOptionalDouble(obj.value(QStringLiteral("criticalCompressibility")));
      rec.specificGravity60F = parseOptionalDouble(obj.value(QStringLiteral("specificGravity60F")));
      rec.watsonK = parseOptionalDouble(obj.value(QStringLiteral("watsonK")));
      rec.volumeShiftDelta = parseOptionalDouble(obj.value(QStringLiteral("volumeShiftDelta")));
      rec.source = obj.value(QStringLiteral("source")).toString();
      rec.notes = obj.value(QStringLiteral("notes")).toString();
      return rec;
   }

   ComponentRecord ComponentRecord::fromPseudoComponent(const Component& c,
      const QString& sourceFluidName,
      const QString& inferredFamily)
   {
      ComponentRecord rec;
      // Namespace the ID with a slug of the source fluid name so that PC01–PC30
      // from different crudes don't collide and overwrite each other in the
      // ComponentManager store (e.g. "wcs-pc01", "brent-pc01", "venezuelan-heavy-pc01").
      QString fluidSlug = sourceFluidName.trimmed().toLower();
      fluidSlug.replace(' ', '-');
      fluidSlug.replace('\'', QString());        // strip apostrophes
      QString componentSlug = QString::fromStdString(c.name).trimmed().toLower();
      componentSlug.replace(' ', '-');
      rec.id = fluidSlug + QStringLiteral("-") + componentSlug;
      rec.name = QString::fromStdString(c.name);
      rec.family = inferredFamily;
      rec.componentType = ComponentType::PseudoComponent;
      rec.phaseCapabilities = { QStringLiteral("vapor"), QStringLiteral("liquid") };
      rec.tags = { QStringLiteral("pseudo-component"), QStringLiteral("petroleum"), sourceFluidName };
      if (c.MW > 0.0) rec.molarMass = c.MW;
      if (c.Tb > 0.0) rec.normalBoilingPointK = c.Tb;
      if (c.Tc > 0.0) rec.criticalTemperatureK = c.Tc;
      if (c.Pc > 0.0) rec.criticalPressurePa = c.Pc;
      if (c.omega != 0.0) rec.acentricFactor = c.omega;
      if (c.SG > 0.0) rec.specificGravity60F = c.SG;
      if (c.delta != 0.0) rec.volumeShiftDelta = c.delta;
      rec.source = QStringLiteral("pseudo-fluid:%1").arg(sourceFluidName);
      rec.notes = QStringLiteral("Imported from existing pseudo-component fluid definition");
      return rec;
   }

   QVariantMap BinaryInteractionRecord::toVariantMap() const
   {
      QVariantMap out;
      out.insert(QStringLiteral("method"), method);
      out.insert(QStringLiteral("componentA"), componentA);
      out.insert(QStringLiteral("componentB"), componentB);
      out.insert(QStringLiteral("parameters"), parameters);
      out.insert(QStringLiteral("source"), source);
      out.insert(QStringLiteral("notes"), notes);
      return out;
   }

   QJsonObject BinaryInteractionRecord::toJson() const
   {
      QJsonObject obj;
      obj.insert(QStringLiteral("method"), method);
      obj.insert(QStringLiteral("componentA"), componentA);
      obj.insert(QStringLiteral("componentB"), componentB);
      obj.insert(QStringLiteral("parameters"), QJsonObject::fromVariantMap(parameters));
      obj.insert(QStringLiteral("source"), source);
      obj.insert(QStringLiteral("notes"), notes);
      return obj;
   }

   BinaryInteractionRecord BinaryInteractionRecord::fromVariantMap(const QVariantMap& map)
   {
      BinaryInteractionRecord rec;
      rec.method = map.value(QStringLiteral("method")).toString();
      rec.componentA = map.value(QStringLiteral("componentA")).toString();
      rec.componentB = map.value(QStringLiteral("componentB")).toString();
      rec.parameters = map.value(QStringLiteral("parameters")).toMap();
      rec.source = map.value(QStringLiteral("source")).toString();
      rec.notes = map.value(QStringLiteral("notes")).toString();
      return rec;
   }

   BinaryInteractionRecord BinaryInteractionRecord::fromJson(const QJsonObject& obj)
   {
      BinaryInteractionRecord rec;
      rec.method = obj.value(QStringLiteral("method")).toString();
      rec.componentA = obj.value(QStringLiteral("componentA")).toString();
      rec.componentB = obj.value(QStringLiteral("componentB")).toString();
      rec.parameters = obj.value(QStringLiteral("parameters")).toObject().toVariantMap();
      rec.source = obj.value(QStringLiteral("source")).toString();
      rec.notes = obj.value(QStringLiteral("notes")).toString();
      return rec;
   }

} // namespace sim