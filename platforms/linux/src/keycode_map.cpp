#include "keycode_map.h"

#include <fcitx-utils/key.h>

namespace dau {

uint32_t keysymToChar(fcitx::KeySym sym) {
    // X11 Latin-1 keysyms in [0x20, 0x7e] map 1:1 onto Unicode (printable ASCII).
    // Covers a-z, A-Z, 0-9, and basic punctuation.
    const auto code = static_cast<uint32_t>(sym);
    if (code >= 0x20U && code <= 0x7eU) {
        return code;
    }
    return 0;
}

bool isBreakKey(fcitx::KeySym sym) {
    switch (sym) {
    case FcitxKey_space:
    case FcitxKey_Return:
    case FcitxKey_KP_Enter:
    case FcitxKey_Tab:
    case FcitxKey_ISO_Left_Tab:
    case FcitxKey_comma:
    case FcitxKey_period:
    case FcitxKey_semicolon:
    case FcitxKey_colon:
    case FcitxKey_exclam:
    case FcitxKey_question:
    case FcitxKey_slash:
    case FcitxKey_backslash:
    case FcitxKey_bar:
    case FcitxKey_parenleft:
    case FcitxKey_parenright:
    case FcitxKey_bracketleft:
    case FcitxKey_bracketright:
    case FcitxKey_braceleft:
    case FcitxKey_braceright:
    case FcitxKey_less:
    case FcitxKey_greater:
    case FcitxKey_quotedbl:
    case FcitxKey_apostrophe:
    case FcitxKey_grave:
    case FcitxKey_asciitilde:
    case FcitxKey_at:
    case FcitxKey_numbersign:
    case FcitxKey_dollar:
    case FcitxKey_percent:
    case FcitxKey_asciicircum:
    case FcitxKey_ampersand:
    case FcitxKey_asterisk:
    case FcitxKey_minus:
    case FcitxKey_underscore:
    case FcitxKey_equal:
    case FcitxKey_plus:
    case FcitxKey_Left:
    case FcitxKey_Right:
    case FcitxKey_Up:
    case FcitxKey_Down:
    case FcitxKey_Home:
    case FcitxKey_End:
    case FcitxKey_Page_Up:
    case FcitxKey_Page_Down:
    case FcitxKey_KP_Left:
    case FcitxKey_KP_Right:
    case FcitxKey_KP_Up:
    case FcitxKey_KP_Down:
    case FcitxKey_KP_Home:
    case FcitxKey_KP_End:
    case FcitxKey_KP_Page_Up:
    case FcitxKey_KP_Page_Down:
        return true;
    default:
        return false;
    }
}

} // namespace dau
