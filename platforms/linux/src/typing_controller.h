// SPDX-License-Identifier: MIT
#pragma once

#include <cstdint>
#include <string>

#include "output_sink.h"
#include "rust_bridge.h"
#include "strategy_resolver.h"

namespace dau {

enum class KeyKind { Printable, Break, Escape, Modifier, Other };

// Maps DauResult → OutputSink under the active typing strategy. Host-IME free.
class TypingController {
public:
    explicit TypingController(RustBridge *bridge);

    // Handle one pre-classified key event. Returns true if the key was consumed
    // (caller should filterAndAccept; do not forward the original key).
    bool handle(KeyKind kind, uint32_t ch, bool caps, uint32_t breakChar,
                OutputSink &out);

    // Switch strategy; resets compose state when the strategy actually changes.
    void setStrategy(Strategy s, OutputSink &out);

    Strategy strategy() const { return strategy_; }

    // Clear preedit surface / provisional length + core compose buffer.
    void resetCompose(OutputSink &out);

    bool isComposing() const { return composing_; }

private:
    bool handlePreedit(KeyKind kind, uint32_t ch, bool caps, uint32_t breakChar,
                       OutputSink &out);
    bool handleCommitAtom(KeyKind kind, uint32_t ch, bool caps,
                          uint32_t breakChar, OutputSink &out);
    bool handlePassthrough(KeyKind kind, uint32_t ch, bool caps,
                           uint32_t breakChar, OutputSink &out);

    RustBridge *bridge_ = nullptr;
    Strategy strategy_ = Strategy::Preedit;
    bool composing_ = false;
    std::string last_preedit_;
    // CommitAtom: length (UTF-32 code points) of provisional text already committed.
    uint32_t prov_len_ = 0;
};

} // namespace dau
