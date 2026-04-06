#include "streams/state/StreamUnitState.h"
#include "fluid/FluidPackageManager.h"

StreamUnitState::StreamUnitState(QObject* parent)
   : ProcessUnitState(parent)
   , stream_(this)
{
   setType(QStringLiteral("stream"));
   setIconKey(QStringLiteral("stream"));
   setName(QStringLiteral("stream_1"));
   stream_.setStreamName(QStringLiteral("Standalone material stream"));
   stream_.setStreamType(MaterialStreamState::StreamType::Feed);
   // Note: setIsCrudeFeed(true) removed — package identity now comes from
   // FluidPackageManager via initializeWithDefaultPackage(), called by
   // FlowsheetState immediately after construction.
}

void StreamUnitState::initializeWithDefaultPackage()
{
   auto* fpm = FluidPackageManager::instance();
   if (!fpm)
      return;
   const QString defaultId = fpm->defaultFluidPackageId();
   if (defaultId.isEmpty())
      return;
   // Always assign the default package on a new stream. There is no guard for
   // an already-assigned package here because this method is only called once,
   // immediately after construction in FlowsheetState::addStreamInternal.
   // Streams loaded from persistence set their package via setSelectedFluidPackageId
   // during load, which happens separately and does not go through this path.
   stream_.setSelectedFluidPackageId(defaultId);
}