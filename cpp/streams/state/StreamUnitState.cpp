#include "streams/state/StreamUnitState.h"

StreamUnitState::StreamUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , stream_(this)
{
    setType(QStringLiteral("stream"));
    setIconKey(QStringLiteral("stream"));
    setName(QStringLiteral("stream_1"));
    stream_.setStreamName(QStringLiteral("Standalone material stream"));
    stream_.setStreamType(MaterialStreamState::StreamType::Feed);
    stream_.setIsCrudeFeed(true);
}
