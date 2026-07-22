#ifndef DAU_ENGINE_H
#define DAU_ENGINE_H

#include <fcitx/inputmethodengine.h>
#include <fcitx/instance.h>

#include "rust_bridge.h"
#include "typing_controller.h"

namespace dau {

// Fcitx5 adapter: classifies keys, drives TypingController + Fcitx5Sink.
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
    [[maybe_unused]] fcitx::Instance *instance_ = nullptr;
    RustBridge bridge_;
    TypingController controller_;
};

} // namespace dau

#endif // DAU_ENGINE_H
