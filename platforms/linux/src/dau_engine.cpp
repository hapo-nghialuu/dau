#include "dau_engine.h"

#include <fcitx-utils/key.h>
#include <fcitx-utils/macros.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputmethodentry.h>

#include "fcitx5_sink.h"
#include "keycode_map.h"

namespace dau {

namespace {

// Null sink used when we only need to clear compose state without an IC.
struct NullSink : OutputSink {
    void setPreedit(const std::string &) override {}
    void commit(const std::string &) override {}
    void forward() override {}
};

} // namespace

DauEngine::DauEngine(fcitx::Instance *instance)
    : instance_(instance), bridge_(), controller_(&bridge_) {}

void DauEngine::activate(const fcitx::InputMethodEntry &entry,
                         fcitx::InputContextEvent &event) {
    FCITX_UNUSED(entry);
    fcitx::InputContext *ic = event.inputContext();
    if (ic != nullptr) {
        Fcitx5Sink sink(ic);
        controller_.resetCompose(sink);
    } else {
        NullSink sink;
        controller_.resetCompose(sink);
    }
}

void DauEngine::deactivate(const fcitx::InputMethodEntry &entry,
                           fcitx::InputContextEvent &event) {
    FCITX_UNUSED(entry);
    fcitx::InputContext *ic = event.inputContext();
    if (ic != nullptr) {
        Fcitx5Sink sink(ic);
        controller_.resetCompose(sink);
    } else {
        NullSink sink;
        controller_.resetCompose(sink);
    }
}

void DauEngine::reset(const fcitx::InputMethodEntry &entry,
                      fcitx::InputContextEvent &event) {
    FCITX_UNUSED(entry);
    fcitx::InputContext *ic = event.inputContext();
    if (ic != nullptr) {
        Fcitx5Sink sink(ic);
        controller_.resetCompose(sink);
    } else {
        NullSink sink;
        controller_.resetCompose(sink);
    }
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

    Fcitx5Sink sink(ic);
    const auto states = key.states();
    const fcitx::KeySym sym = key.sym();

    // Ctrl / Alt / Super chords: reset compose and let the key through.
    if (states.test(fcitx::KeyState::Ctrl) ||
        states.test(fcitx::KeyState::Alt) ||
        states.test(fcitx::KeyState::Super)) {
        controller_.handle(KeyKind::Modifier, 0, false, 0, sink);
        return;
    }

    if (sym == FcitxKey_Escape) {
        if (controller_.handle(KeyKind::Escape, 0, false, 0, sink)) {
            keyEvent.filterAndAccept();
        }
        return;
    }

    if (isBreakKey(sym)) {
        // breakChar: printable ASCII for space/punct; 0 for arrows / non-print.
        const uint32_t breakChar = keysymToChar(sym);
        const uint32_t brk = breakChar != 0 ? breakChar : static_cast<uint32_t>(' ');
        // Always returns false — break key must reach the application.
        controller_.handle(KeyKind::Break, 0, false, brk, sink);
        return;
    }

    const uint32_t ch = keysymToChar(sym);
    if (ch == 0) {
        // Non-printable (BackSpace, F-keys, ...).
        if (controller_.handle(KeyKind::Other, 0, false, 0, sink)) {
            keyEvent.filterAndAccept();
        }
        return;
    }

    const bool caps = states.test(fcitx::KeyState::Shift);
    if (controller_.handle(KeyKind::Printable, ch, caps, 0, sink)) {
        keyEvent.filterAndAccept();
    }
}

} // namespace dau
