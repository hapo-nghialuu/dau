// SPDX-License-Identifier: MIT
#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/instance.h>

#include "dau_engine.h"

namespace {

class DauEngineFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new dau::DauEngine(manager->instance());
    }
};

} // namespace

FCITX_ADDON_FACTORY(DauEngineFactory);
