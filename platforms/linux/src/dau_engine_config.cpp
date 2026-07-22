#include "dau_engine.h"

#include <cstdlib>
#include <string>

#include "output_sink.h"

namespace dau {

namespace {

// Null sink used when we only need to clear compose state without an IC.
struct NullSink : OutputSink {
    void setPreedit(const std::string &) override {}
    void commit(const std::string &) override {}
    void forward() override {}
    void deleteBeforeCursor(uint32_t) override {}
};

const char *methodLabel(DauConfigMethod m) {
    return m == DauConfigMethod::VNI ? "VNI" : "Telex";
}

} // namespace

void DauEngine::loadTomlConfig() {
    const char *home = std::getenv("HOME");
    std::string userPath;
    if (home != nullptr && home[0] != '\0') {
        userPath = std::string(home) + "/.config/dau/config.toml";
    }
    const char *userCStr = userPath.empty() ? nullptr : userPath.c_str();
    const bool ok = bridge_.loadConfig(/*shipped=*/nullptr, userCStr);
    FCITX_LOGC(dau_log, Info)
        << "toml load " << (ok ? "ok" : "skip/fail")
        << " path=" << (userCStr != nullptr ? userCStr : "(none)");
}

void DauEngine::applyGuiConfig() {
    const DauConfigMethod method = *config_.method;
    const bool enabled = *config_.enabled;
    const bool autoCap = *config_.autoCapitalize;
    const bool autoRestore = *config_.autoRestore;

    bridge_.setMethod(method == DauConfigMethod::VNI);
    bridge_.setEnabled(enabled);
    cfg_auto_cap_ = autoCap;
    bridge_.setAutoCapitalize(autoCap);
    bridge_.setAutoRestore(autoRestore);

    FCITX_LOGC(dau_log, Info)
        << "gui config applied method=" << methodLabel(method)
        << " enabled=" << enabled << " autoCap=" << autoCap
        << " autoRestore=" << autoRestore;
}

void DauEngine::resetComposeSilent() {
    NullSink sink;
    controller_.resetCompose(sink);
}

void DauEngine::reloadConfig() {
    // 1) fcitx5 GUI conf (defaults if file missing)
    readAsIni(config_, "conf/dau.conf");
    // 2) TOML: shortcuts + per-app strategy
    loadTomlConfig();
    // 3) GUI wins for method / enabled / auto*
    applyGuiConfig();
    // Safe to call repeatedly: loadConfig + set* are idempotent enough for v1.
    FCITX_LOGC(dau_log, Info) << "reloadConfig done";
}

const fcitx::Configuration *DauEngine::getConfig() const { return &config_; }

void DauEngine::setConfig(const fcitx::RawConfig &rawConfig) {
    config_.load(rawConfig, true);
    applyGuiConfig();
    resetComposeSilent();
    safeSaveAsIni(config_, "conf/dau.conf");
    FCITX_LOGC(dau_log, Info) << "setConfig saved conf/dau.conf";
}

} // namespace dau
