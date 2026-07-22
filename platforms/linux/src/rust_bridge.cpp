// SPDX-License-Identifier: MIT
#include "rust_bridge.h"

namespace dau {

namespace {

DauResult emptyResult() {
    DauResult r{};
    r.action = DauAction_None;
    r.len = 0;
    r.capitalize_next = false;
    return r;
}

} // namespace

RustBridge::RustBridge() : RustBridge(DauMethod_Telex) {}

RustBridge::RustBridge(DauMethod method) : h_(dau_engine_new(method)) {}

RustBridge::~RustBridge() {
    if (h_ != nullptr) {
        dau_engine_free(h_);
        h_ = nullptr;
    }
}

RustBridge::RustBridge(RustBridge &&other) noexcept : h_(other.h_) {
    other.h_ = nullptr;
}

RustBridge &RustBridge::operator=(RustBridge &&other) noexcept {
    if (this != &other) {
        if (h_ != nullptr) {
            dau_engine_free(h_);
        }
        h_ = other.h_;
        other.h_ = nullptr;
    }
    return *this;
}

DauResult RustBridge::processChar(uint32_t ch, bool caps) {
    if (h_ == nullptr) {
        return emptyResult();
    }
    return dau_process_char(h_, ch, caps);
}

DauResult RustBridge::onBreak(uint32_t brk) {
    if (h_ == nullptr) {
        return emptyResult();
    }
    return dau_on_break(h_, brk);
}

DauResult RustBridge::escape() {
    if (h_ == nullptr) {
        return emptyResult();
    }
    return dau_escape(h_);
}

void RustBridge::clear() {
    if (h_ != nullptr) {
        dau_clear(h_);
    }
}

void RustBridge::setMethod(bool vni) {
    if (h_ != nullptr) {
        dau_set_method(h_, vni ? DauMethod_Vni : DauMethod_Telex);
    }
}

void RustBridge::setEnabled(bool enabled) {
    if (h_ != nullptr) {
        dau_set_enabled(h_, enabled);
    }
}

void RustBridge::setAutoCapitalize(bool on) {
    if (h_ != nullptr) {
        dau_set_auto_capitalize(h_, on);
    }
}

void RustBridge::setAutoRestore(bool on) {
    if (h_ != nullptr) {
        dau_set_auto_restore(h_, on);
    }
}

DauStrategy RustBridge::strategyForApp(const std::string &app_id) {
    if (h_ == nullptr) {
        return DauStrategy_Unknown;
    }
    return dau_strategy_for_app(h_, app_id.c_str());
}

bool RustBridge::loadConfig(const char *shipped, const char *user) {
    if (h_ == nullptr) {
        return false;
    }
    return dau_load_config(h_, shipped, user);
}

std::string utf32ToUtf8(const uint32_t *chars, uint32_t len) {
    std::string out;
    if (chars == nullptr || len == 0) {
        return out;
    }
    out.reserve(static_cast<size_t>(len) * 3U);
    for (uint32_t i = 0; i < len; ++i) {
        const uint32_t cp = chars[i];
        if (cp <= 0x7FU) {
            out.push_back(static_cast<char>(cp));
        } else if (cp <= 0x7FFU) {
            out.push_back(static_cast<char>(0xC0U | (cp >> 6U)));
            out.push_back(static_cast<char>(0x80U | (cp & 0x3FU)));
        } else if (cp <= 0xFFFFU) {
            out.push_back(static_cast<char>(0xE0U | (cp >> 12U)));
            out.push_back(static_cast<char>(0x80U | ((cp >> 6U) & 0x3FU)));
            out.push_back(static_cast<char>(0x80U | (cp & 0x3FU)));
        } else if (cp <= 0x10FFFFU) {
            out.push_back(static_cast<char>(0xF0U | (cp >> 18U)));
            out.push_back(static_cast<char>(0x80U | ((cp >> 12U) & 0x3FU)));
            out.push_back(static_cast<char>(0x80U | ((cp >> 6U) & 0x3FU)));
            out.push_back(static_cast<char>(0x80U | (cp & 0x3FU)));
        }
        // Skip invalid code points silently.
    }
    return out;
}

} // namespace dau
