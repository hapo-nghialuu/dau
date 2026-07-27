// SPDX-License-Identifier: MIT
//
// Delta result layout (`DauDeltaResult`) derived from Gõ Nhanh
// (BSD-3-Clause, Copyright (c) 2025 Gõ Nhanh Contributors). See repo root NOTICE.
#include "rust_bridge.h"

#include <algorithm>
#include <string>
#include <vector>

namespace dau {

namespace {

DauDeltaResult emptyResult() {
    DauDeltaResult r{};
    r.action = DauAction_None;
    r.count = 0;
    r.backspace = 0;
    r.capitalize_next = false;
    return r;
}

// Decode UTF-8 into Unicode scalar values (UTF-32 code points). Invalid
// sequences are skipped (defensive; host strings come from our own encoder).
std::vector<uint32_t> utf8ToScalars(const std::string &utf8) {
    std::vector<uint32_t> out;
    out.reserve(utf8.size());
    const auto *p = reinterpret_cast<const unsigned char *>(utf8.data());
    const auto *end = p + utf8.size();
    while (p < end) {
        const unsigned char c = *p;
        if (c < 0x80U) {
            out.push_back(c);
            ++p;
        } else if ((c >> 5U) == 0x6U && p + 1 < end) {
            out.push_back((static_cast<uint32_t>(c & 0x1FU) << 6U) |
                          (p[1] & 0x3FU));
            p += 2;
        } else if ((c >> 4U) == 0xEU && p + 2 < end) {
            out.push_back((static_cast<uint32_t>(c & 0x0FU) << 12U) |
                          (static_cast<uint32_t>(p[1] & 0x3FU) << 6U) |
                          (p[2] & 0x3FU));
            p += 3;
        } else if ((c >> 3U) == 0x1EU && p + 3 < end) {
            out.push_back((static_cast<uint32_t>(c & 0x07U) << 18U) |
                          (static_cast<uint32_t>(p[1] & 0x3FU) << 12U) |
                          (static_cast<uint32_t>(p[2] & 0x3FU) << 6U) |
                          (p[3] & 0x3FU));
            p += 4;
        } else {
            ++p; // skip invalid
        }
    }
    return out;
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

DauDeltaResult RustBridge::processChar(uint32_t ch, bool caps) {
    if (h_ == nullptr) {
        return emptyResult();
    }
    return dau_process_char(h_, ch, caps);
}

DauDeltaResult RustBridge::onBreak(uint32_t brk) {
    if (h_ == nullptr) {
        return emptyResult();
    }
    return dau_on_break(h_, brk);
}

DauDeltaResult RustBridge::escape() {
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

std::string utf32ToUtf8(const uint32_t *chars, uint32_t count) {
    std::string out;
    if (chars == nullptr || count == 0) {
        return out;
    }
    out.reserve(static_cast<size_t>(count) * 3U);
    for (uint32_t i = 0; i < count; ++i) {
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

std::string applyDelta(const std::string &base, uint8_t backspace,
                       const uint32_t *chars, uint8_t count) {
    auto scalars = utf8ToScalars(base);
    const size_t drop =
        std::min(static_cast<size_t>(backspace), scalars.size());
    if (drop > 0) {
        scalars.resize(scalars.size() - drop);
    }
    if (chars != nullptr && count > 0) {
        for (uint8_t i = 0; i < count; ++i) {
            scalars.push_back(chars[i]);
        }
    }
    return utf32ToUtf8(scalars.data(), static_cast<uint32_t>(scalars.size()));
}

} // namespace dau
