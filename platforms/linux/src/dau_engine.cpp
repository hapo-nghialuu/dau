// SPDX-License-Identifier: MIT
#include "dau_engine.h"

#include <string>

#include <fcitx-utils/key.h>
#include <fcitx-utils/macros.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputmethodentry.h>

#include "fcitx5_sink.h"
#include "keycode_map.h"
#include "strategy_resolver.h"

// Log category definition (declare in dau_config.h).
FCITX_DEFINE_LOG_CATEGORY(dau_log, "dau");

namespace dau {

namespace {

const char *strategyLabel(Strategy s) {
    switch (s) {
    case Strategy::Preedit:
        return "Preedit";
    case Strategy::CommitAtom:
        return "CommitAtom";
    case Strategy::Passthrough:
        return "Passthrough";
    }
    return "?";
}

} // namespace

DauEngine::DauEngine(fcitx::Instance *instance)
    : instance_(instance), bridge_(), controller_(&bridge_) {
    // Load fcitx5 conf + TOML, then apply GUI over bridge (GUI wins).
    reloadConfig();
    FCITX_LOGC(dau_log, Info) << "addon initialized";
}

void DauEngine::applyStrategyForIc(fcitx::InputContext *ic) {
    if (ic == nullptr) {
        return;
    }

    const std::string program = ic->program();
    const bool hasPreedit =
        ic->capabilityFlags().test(fcitx::CapabilityFlag::Preedit);
    const DauStrategy cfgStrat = bridge_.strategyForApp(program);
    const Strategy strat = resolveStrategy(cfgStrat, hasPreedit);

    Fcitx5Sink sink(ic);
    controller_.setStrategy(strat, sink);

    // Preedit/CommitAtom: auto-cap only when config explicitly enables it.
    // Passthrough: still leave auto-cap off so a later strategy switch is safe.
    if (strat == Strategy::Preedit || strat == Strategy::CommitAtom) {
        bridge_.setAutoCapitalize(cfg_auto_cap_);
    } else {
        bridge_.setAutoCapitalize(false);
    }

    // Privacy: log app id + strategy only — never key content.
    FCITX_LOGC(dau_log, Info)
        << "strategy app=" << (program.empty() ? "(empty)" : program)
        << " hasPreedit=" << hasPreedit << " -> " << strategyLabel(strat);
}

void DauEngine::activate(const fcitx::InputMethodEntry &entry,
                         fcitx::InputContextEvent &event) {
    FCITX_UNUSED(entry);
    fcitx::InputContext *ic = event.inputContext();
    if (ic != nullptr) {
        applyStrategyForIc(ic);
        Fcitx5Sink sink(ic);
        controller_.resetCompose(sink);
    } else {
        resetComposeSilent();
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
        resetComposeSilent();
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
        resetComposeSilent();
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
        const uint32_t brk =
            breakChar != 0 ? breakChar : static_cast<uint32_t>(' ');
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
