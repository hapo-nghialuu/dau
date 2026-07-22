// SPDX-License-Identifier: MIT
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

    DauResult processChar(uint32_t ch, bool caps);
    DauResult onBreak(uint32_t brk);
    DauResult escape();
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

// Encode UTF-32 code points (length `len`) into a UTF-8 std::string.
std::string utf32ToUtf8(const uint32_t *chars, uint32_t len);

} // namespace dau

#endif // DAU_RUST_BRIDGE_H
