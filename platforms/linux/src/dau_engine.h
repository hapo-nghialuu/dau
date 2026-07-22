#ifndef DAU_ENGINE_H
#define DAU_ENGINE_H

#include <fcitx/inputmethodengine.h>
#include <fcitx/instance.h>

#include "rust_bridge.h"

namespace dau {

// Thin Fcitx5 adapter around RustBridge.
// P2.1: minimal key path (processChar → commitString). Full preedit is P2.2.
class DauEngine : public fcitx::InputMethodEngineV2 {
public:
    explicit DauEngine(fcitx::Instance *instance);
    ~DauEngine() override = default;

    void keyEvent(const fcitx::InputMethodEntry &entry,
                  fcitx::KeyEvent &keyEvent) override;
    void activate(const fcitx::InputMethodEntry &entry,
                  fcitx::InputContextEvent &event) override;
    void deactivate(const fcitx::InputMethodEntry &entry,
                    fcitx::InputContextEvent &event) override;
    void reset(const fcitx::InputMethodEntry &entry,
               fcitx::InputContextEvent &event) override;

private:
    void clearCompose();

    [[maybe_unused]] fcitx::Instance *instance_ = nullptr;
    RustBridge bridge_;
    // Unicode scalar count last committed (for temporary replace via
    // deleteSurroundingText until real preedit lands in P2.2).
    int last_commit_chars_ = 0;
};

} // namespace dau

#endif // DAU_ENGINE_H
