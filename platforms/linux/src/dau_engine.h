#ifndef DAU_ENGINE_H
#define DAU_ENGINE_H

#include <fcitx-config/iniparser.h>
#include <fcitx-config/rawconfig.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/instance.h>

#include "dau_config.h"
#include "rust_bridge.h"
#include "typing_controller.h"

namespace dau {

// Fcitx5 adapter: classifies keys, drives TypingController + Fcitx5Sink.
// Owns GUI config (DauConfig) and applies it over TOML-loaded bridge state.
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

    // AddonInstance / configtool: reload from disk (fcitx5 conf + TOML).
    void reloadConfig() override;
    const fcitx::Configuration *getConfig() const override;
    void setConfig(const fcitx::RawConfig &config) override;

private:
    // Resolve per-app strategy + safe auto-capitalize for this InputContext.
    void applyStrategyForIc(fcitx::InputContext *ic);

    // Apply GUI config_ to bridge_ (GUI wins over TOML for these toggles).
    void applyGuiConfig();

    // Load TOML shortcuts/apps into bridge_ (does not touch GUI fields).
    void loadTomlConfig();

    // Clear compose without requiring a live InputContext.
    void resetComposeSilent();

    [[maybe_unused]] fcitx::Instance *instance_ = nullptr;
    RustBridge bridge_;
    TypingController controller_;
    DauConfig config_;
    // Cached from GUI; used by applyStrategyForIc (default false, design §5b).
    bool cfg_auto_cap_ = false;
};

} // namespace dau

#endif // DAU_ENGINE_H
