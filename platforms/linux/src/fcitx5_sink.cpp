#include "fcitx5_sink.h"

// Core headers first (always on Fcitx5::Core include path).
#include <fcitx/inputcontext.h>
#include <fcitx/inputpanel.h>
#include <fcitx/userinterface.h>
// fcitx::Text lives in Core (fcitx/text.h on Ubuntu); TextFormatFlag in Utils.
#include <fcitx/text.h>
#include <fcitx-utils/textformatflags.h>

namespace dau {

Fcitx5Sink::Fcitx5Sink(fcitx::InputContext *ic) : ic_(ic) {}

void Fcitx5Sink::setPreedit(const std::string &utf8) {
    if (ic_ == nullptr) {
        return;
    }

    // Pattern from fcitx5 quickphrase: Text + TextFormatFlags{Underline}.
    fcitx::Text preedit;
    if (!utf8.empty()) {
        preedit.append(utf8,
                       fcitx::TextFormatFlags{fcitx::TextFormatFlag::Underline});
        preedit.setCursor(static_cast<int>(utf8.size()));
    }

    // Prefer client-side preedit when the app supports it; otherwise panel.
    if (ic_->capabilityFlags().test(fcitx::CapabilityFlag::Preedit)) {
        ic_->inputPanel().setClientPreedit(preedit);
    } else {
        ic_->inputPanel().setPreedit(preedit);
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
