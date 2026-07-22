#pragma once

#include <cstdint>
#include <string>

#include "output_sink.h"
#include "rust_bridge.h"

namespace dau {

enum class KeyKind { Printable, Break, Escape, Modifier, Other };

// Pure preedit strategy: maps DauResult → OutputSink. Host-IME free (testable).
class TypingController {
public:
    explicit TypingController(RustBridge *bridge);

    // Handle one pre-classified key event. Returns true if the key was consumed
    // (caller should filterAndAccept; do not forward the original key).
    bool handle(KeyKind kind, uint32_t ch, bool caps, uint32_t breakChar,
                OutputSink &out);

    // Clear preedit surface + core compose buffer.
    void resetCompose(OutputSink &out);

    bool isComposing() const { return composing_; }

private:
    RustBridge *bridge_ = nullptr;
    bool composing_ = false;
    std::string last_preedit_;
};

} // namespace dau
