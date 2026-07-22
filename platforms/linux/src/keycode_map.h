// SPDX-License-Identifier: MIT
#ifndef DAU_KEYCODE_MAP_H
#define DAU_KEYCODE_MAP_H

#include <cstdint>
#include <fcitx-utils/key.h>

namespace dau {

// Map an fcitx KeySym to a printable UTF-32 code point.
// Returns 0 for non-printable / unmapped keys (K-01 neutral mapping).
uint32_t keysymToChar(fcitx::KeySym sym);

// True for word-break keys: space, enter, tab, common punctuation, arrows.
bool isBreakKey(fcitx::KeySym sym);

} // namespace dau

#endif // DAU_KEYCODE_MAP_H
