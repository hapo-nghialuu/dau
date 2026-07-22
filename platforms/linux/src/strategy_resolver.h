#pragma once

#include "dau_core.h"

namespace dau {

// Runtime typing strategy (bridge-side; host-IME free).
enum class Strategy { Preedit, CommitAtom, Passthrough };

// Resolve strategy from config lookup + client capability flags.
// Precedence (design §3):
//   1. configStrategy != Unknown → map directly
//   2. else !hasPreeditCap → CommitAtom
//   3. else → Preedit (safe default)
Strategy resolveStrategy(DauStrategy configStrategy, bool hasPreeditCap);

} // namespace dau
