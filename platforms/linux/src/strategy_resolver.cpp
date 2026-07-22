#include "strategy_resolver.h"

namespace dau {

Strategy resolveStrategy(DauStrategy configStrategy, bool hasPreeditCap) {
    switch (configStrategy) {
    case DauStrategy_Preedit:
        return Strategy::Preedit;
    case DauStrategy_CommitAtom:
        return Strategy::CommitAtom;
    case DauStrategy_Passthrough:
        return Strategy::Passthrough;
    case DauStrategy_Unknown:
    default:
        if (!hasPreeditCap) {
            return Strategy::CommitAtom;
        }
        return Strategy::Preedit;
    }
}

} // namespace dau
