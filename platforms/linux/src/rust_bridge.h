// SPDX-License-Identifier: MIT
//
// Delta result layout (`DauDeltaResult`) derived from Gõ Nhanh
// (BSD-3-Clause, Copyright (c) 2025 Gõ Nhanh Contributors). See repo root NOTICE.
#ifndef DAU_RUST_BRIDGE_H
#define DAU_RUST_BRIDGE_H

#include <cstdint>
#include <string>

#include "dau_core.h"

namespace dau {

// RAII wrapper around the dau-core C ABI (`Engine*`).
// Non-copyable, movable. Null engine is safe for all methods (core no-ops).
class RustBridge {
public:
    RustBridge();
    explicit RustBridge(DauMethod method);
    ~RustBridge();

    RustBridge(const RustBridge &) = delete;
    RustBridge &operator=(const RustBridge &) = delete;

    RustBridge(RustBridge &&other) noexcept;
    RustBridge &operator=(RustBridge &&other) noexcept;

    DauDeltaResult processChar(uint32_t ch, bool caps);
    DauDeltaResult onBreak(uint32_t brk);
    DauDeltaResult escape();
    void clear();
    void setMethod(bool vni);
    void setEnabled(bool enabled);
    void setAutoCapitalize(bool on);
    void setAutoRestore(bool on);
    DauStrategy strategyForApp(const std::string &app_id);
    bool loadConfig(const char *shipped, const char *user);

    Engine *handle() const { return h_; }

private:
    Engine *h_ = nullptr;
};

// Encode UTF-32 code points (length `count`) into a UTF-8 std::string.
std::string utf32ToUtf8(const uint32_t *chars, uint32_t count);

// Apply a display delta to a host-visible UTF-8 string (Unicode scalar units).
// Deletes up to `backspace` trailing scalars, then appends insert code points.
std::string applyDelta(const std::string &base, uint8_t backspace,
                       const uint32_t *chars, uint8_t count);

} // namespace dau

#endif // DAU_RUST_BRIDGE_H
