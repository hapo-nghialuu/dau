// SPDX-License-Identifier: MIT
//
// Consumes core `DauDeltaResult` (display delta). Layout derived from Gõ Nhanh
// (BSD-3-Clause, Copyright (c) 2025 Gõ Nhanh Contributors). See repo root NOTICE.
#include "typing_controller.h"

#include <algorithm>

namespace dau {

TypingController::TypingController(RustBridge *bridge) : bridge_(bridge) {}

void TypingController::setStrategy(Strategy s, OutputSink &out) {
    if (s == strategy_) {
        return;
    }
    resetCompose(out);
    strategy_ = s;
}

void TypingController::resetCompose(OutputSink &out) {
    if (strategy_ == Strategy::Preedit) {
        if (composing_ || !last_preedit_.empty()) {
            out.setPreedit("");
        }
    }
    // CommitAtom: drop provisional length only (text already in document).
    last_preedit_.clear();
    composing_ = false;
    prov_len_ = 0;
    if (bridge_ != nullptr) {
        bridge_->clear();
    }
}

bool TypingController::handle(KeyKind kind, uint32_t ch, bool caps,
                              uint32_t breakChar, OutputSink &out) {
    if (bridge_ == nullptr && strategy_ != Strategy::Passthrough) {
        return false;
    }

    switch (strategy_) {
    case Strategy::Preedit:
        return handlePreedit(kind, ch, caps, breakChar, out);
    case Strategy::CommitAtom:
        return handleCommitAtom(kind, ch, caps, breakChar, out);
    case Strategy::Passthrough:
        return handlePassthrough(kind, ch, caps, breakChar, out);
    }
    return false;
}

bool TypingController::handlePreedit(KeyKind kind, uint32_t ch, bool caps,
                                     uint32_t breakChar, OutputSink &out) {
    switch (kind) {
    case KeyKind::Printable: {
        const DauDeltaResult result = bridge_->processChar(ch, caps);
        if (result.action == DauAction_UpdatePreedit) {
            // Reconstruct full preedit from core delta, then draw it.
            last_preedit_ = applyDelta(last_preedit_, result.backspace,
                                       result.chars, result.count);
            out.setPreedit(last_preedit_);
            composing_ = true;
            return true;
        }
        // Engine disabled / null / invalid → do not consume; let key through.
        return false;
    }

    case KeyKind::Break: {
        const DauDeltaResult result = bridge_->onBreak(breakChar);
        // Apply commit delta onto last preedit to recover final text, then
        // clear preedit surface and commit into the document.
        const bool had = composing_ || !last_preedit_.empty() ||
                         result.backspace > 0 || result.count > 0;
        if (had) {
            const std::string final_text =
                applyDelta(last_preedit_, result.backspace, result.chars,
                           result.count);
            out.setPreedit("");
            if (!final_text.empty()) {
                out.commit(final_text);
            }
        }
        last_preedit_.clear();
        composing_ = false;
        // Space/enter/punct must still reach the application.
        return false;
    }

    case KeyKind::Escape: {
        const bool was_composing = composing_ || !last_preedit_.empty();
        const DauDeltaResult result = bridge_->escape();
        if (result.backspace > 0 || result.count > 0 || was_composing) {
            const std::string raw = applyDelta(last_preedit_, result.backspace,
                                               result.chars, result.count);
            out.setPreedit("");
            if (!raw.empty()) {
                out.commit(raw);
            }
            // Word is done in the document; drop core buffer so next keys start fresh.
            bridge_->clear();
            last_preedit_.clear();
            composing_ = false;
            return true; // swallow ESC while (or after) a compose session
        }
        return false;
    }

    case KeyKind::Modifier: {
        resetCompose(out);
        return false;
    }

    case KeyKind::Other: {
        if (!composing_) {
            return false;
        }
        // Commit current composed text, then let the key forward.
        out.setPreedit("");
        if (!last_preedit_.empty()) {
            out.commit(last_preedit_);
        }
        bridge_->clear();
        last_preedit_.clear();
        composing_ = false;
        return false;
    }
    }

    return false;
}

bool TypingController::handleCommitAtom(KeyKind kind, uint32_t ch, bool caps,
                                        uint32_t breakChar, OutputSink &out) {
    switch (kind) {
    case KeyKind::Printable: {
        const DauDeltaResult result = bridge_->processChar(ch, caps);
        if (result.action == DauAction_UpdatePreedit) {
            // Only delete/insert the changed suffix — core-owned delta.
            if (result.backspace > 0) {
                out.deleteBeforeCursor(result.backspace);
            }
            if (result.count > 0) {
                out.commit(utf32ToUtf8(result.chars, result.count));
            }
            // Update host-visible provisional length (Unicode scalars).
            const uint32_t drop = std::min(static_cast<uint32_t>(result.backspace),
                                           prov_len_);
            prov_len_ = prov_len_ - drop + static_cast<uint32_t>(result.count);
            last_preedit_ = applyDelta(last_preedit_, result.backspace,
                                       result.chars, result.count);
            composing_ = prov_len_ > 0 || !last_preedit_.empty();
            // Consume when core produced a delta or is composing; pure no-op
            // (empty delta while already composing) still consumes the key.
            return result.backspace > 0 || result.count > 0 || composing_;
        }
        return false;
    }

    case KeyKind::Break: {
        const DauDeltaResult result = bridge_->onBreak(breakChar);
        if (prov_len_ > 0 || result.backspace > 0 || result.count > 0) {
            if (result.backspace > 0) {
                out.deleteBeforeCursor(result.backspace);
            }
            if (result.count > 0) {
                out.commit(utf32ToUtf8(result.chars, result.count));
            }
        }
        prov_len_ = 0;
        last_preedit_.clear();
        composing_ = false;
        // Break key must still reach the application.
        return false;
    }

    case KeyKind::Escape: {
        const bool was_composing = composing_ || prov_len_ > 0;
        const DauDeltaResult result = bridge_->escape();
        if (result.backspace > 0 || result.count > 0 || was_composing) {
            if (result.backspace > 0) {
                out.deleteBeforeCursor(result.backspace);
            }
            if (result.count > 0) {
                out.commit(utf32ToUtf8(result.chars, result.count));
            }
            bridge_->clear();
            prov_len_ = 0;
            last_preedit_.clear();
            composing_ = false;
            return true;
        }
        return false;
    }

    case KeyKind::Modifier: {
        resetCompose(out);
        return false;
    }

    case KeyKind::Other: {
        if (!composing_ && prov_len_ == 0) {
            return false;
        }
        // Provisional text already lives in the document — just drop compose state.
        bridge_->clear();
        prov_len_ = 0;
        last_preedit_.clear();
        composing_ = false;
        return false;
    }
    }

    return false;
}

bool TypingController::handlePassthrough(KeyKind /*kind*/, uint32_t /*ch*/,
                                         bool /*caps*/,
                                         uint32_t /*breakChar*/,
                                         OutputSink & /*out*/) {
    // Every key forwards. Do not call the bridge so compose state stays empty.
    return false;
}

} // namespace dau
