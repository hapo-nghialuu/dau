#include "dau_engine.h"

#include <fcitx-utils/key.h>
#include <fcitx-utils/macros.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputmethodentry.h>

#include "keycode_map.h"

namespace dau {

DauEngine::DauEngine(fcitx::Instance *instance)
    : instance_(instance), bridge_() {}

void DauEngine::clearCompose() {
    bridge_.clear();
    last_commit_chars_ = 0;
}

void DauEngine::activate(const fcitx::InputMethodEntry &entry,
                         fcitx::InputContextEvent &event) {
    FCITX_UNUSED(entry);
    FCITX_UNUSED(event);
    clearCompose();
}

void DauEngine::deactivate(const fcitx::InputMethodEntry &entry,
                           fcitx::InputContextEvent &event) {
    FCITX_UNUSED(entry);
    FCITX_UNUSED(event);
    clearCompose();
}

void DauEngine::reset(const fcitx::InputMethodEntry &entry,
                      fcitx::InputContextEvent &event) {
    FCITX_UNUSED(entry);
    FCITX_UNUSED(event);
    clearCompose();
}

void DauEngine::keyEvent(const fcitx::InputMethodEntry &entry,
                         fcitx::KeyEvent &keyEvent) {
    FCITX_UNUSED(entry);

    // Ignore key releases.
    if (keyEvent.isRelease()) {
        return;
    }

    const fcitx::Key &key = keyEvent.key();
    fcitx::InputContext *ic = keyEvent.inputContext();
    if (ic == nullptr) {
        return;
    }

    // Ctrl / Alt / Super chords: clear compose buffer and let the key through.
    if (key.states().testAny(fcitx::KeyState::Ctrl | fcitx::KeyState::Alt |
                             fcitx::KeyState::Super)) {
        clearCompose();
        return;
    }

    const fcitx::KeySym sym = key.sym();

    // Word-break keys: clear and pass through (space/enter/punct/arrows).
    if (isBreakKey(sym)) {
        clearCompose();
        return;
    }

    const uint32_t ch = keysymToChar(sym);
    if (ch == 0) {
        // Non-printable (BackSpace, Escape, F-keys, ...): pass through.
        // Escape could restore later (P2.2); for P2.1 just clear buffer.
        if (sym == FcitxKey_Escape) {
            clearCompose();
        }
        return;
    }

    // Caps = Shift held for this keystroke (core uses it for CompChar flags).
    const bool caps = key.states().test(fcitx::KeyState::Shift);
    const DauResult result = bridge_.processChar(ch, caps);

    // P2.1 temporary path: replace previous commit with current buffer text.
    // P2.2 will switch to real preedit (updatePreedit / client preedit).
    if (last_commit_chars_ > 0) {
        ic->deleteSurroundingText(-last_commit_chars_,
                                  static_cast<unsigned int>(last_commit_chars_));
        last_commit_chars_ = 0;
    }

    if (result.len > 0) {
        const std::string text = utf32ToUtf8(result.chars, result.len);
        if (!text.empty()) {
            ic->commitString(text);
            last_commit_chars_ = static_cast<int>(result.len);
        }
    }

    keyEvent.filterAndAccept();
}

} // namespace dau
