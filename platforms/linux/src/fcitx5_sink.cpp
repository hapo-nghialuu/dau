#include "fcitx5_sink.h"

#include <fcitx-utils/text.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputpanel.h>
#include <fcitx/userinterface.h>

namespace dau {

Fcitx5Sink::Fcitx5Sink(fcitx::InputContext *ic) : ic_(ic) {}

void Fcitx5Sink::setPreedit(const std::string &utf8) {
    if (ic_ == nullptr) {
        return;
    }

    fcitx::Text text;
    if (!utf8.empty()) {
        text.append(utf8, fcitx::TextFormatFlag::Underline);
        // Cursor after the preedit string (UTF-8 length is accepted by fcitx Text).
        text.setCursor(static_cast<int>(utf8.size()));
    }

    // Prefer client-side preedit when the app supports it; otherwise use panel.
    if (ic_->capabilityFlags().test(fcitx::CapabilityFlag::Preedit)) {
        ic_->inputPanel().setClientPreedit(text);
    } else {
        ic_->inputPanel().setPreedit(text);
    }
    ic_->updatePreedit();
    ic_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

void Fcitx5Sink::commit(const std::string &utf8) {
    if (ic_ == nullptr || utf8.empty()) {
        return;
    }
    ic_->commitString(utf8);
}

void Fcitx5Sink::forward() {
    // No-op: caller skips filterAndAccept so the original key reaches the app.
}

} // namespace dau
