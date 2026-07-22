#include "typing_controller.h"

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
        const DauResult result = bridge_->processChar(ch, caps);
        if (result.action == DauAction_UpdatePreedit) {
            const std::string utf8 = utf32ToUtf8(result.chars, result.len);
            out.setPreedit(utf8);
            last_preedit_ = utf8;
            composing_ = true;
            return true;
        }
        // Engine disabled / null / invalid → do not consume; let key through.
        return false;
    }

    case KeyKind::Break: {
        const DauResult result = bridge_->onBreak(breakChar);
        // Clear preedit then commit the finished word (break key itself passes).
        if (composing_ || result.len > 0) {
            out.setPreedit("");
            if (result.len > 0) {
                out.commit(utf32ToUtf8(result.chars, result.len));
            }
        }
        last_preedit_.clear();
        composing_ = false;
        // Space/enter/punct must still reach the application.
        return false;
    }

    case KeyKind::Escape: {
        const bool was_composing = composing_ || !last_preedit_.empty();
        const DauResult result = bridge_->escape();
        if (result.len > 0 || was_composing) {
            out.setPreedit("");
            if (result.len > 0) {
                out.commit(utf32ToUtf8(result.chars, result.len));
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
        const DauResult result = bridge_->processChar(ch, caps);
        if (result.action == DauAction_UpdatePreedit && result.len > 0) {
            const std::string utf8 = utf32ToUtf8(result.chars, result.len);
            out.deleteBeforeCursor(prov_len_);
            out.commit(utf8);
            prov_len_ = result.len;
            last_preedit_ = utf8;
            composing_ = true;
            return true;
        }
        return false;
    }

    case KeyKind::Break: {
        const DauResult result = bridge_->onBreak(breakChar);
        if (prov_len_ > 0 || result.len > 0) {
            out.deleteBeforeCursor(prov_len_);
            if (result.len > 0) {
                out.commit(utf32ToUtf8(result.chars, result.len));
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
        const DauResult result = bridge_->escape();
        if (result.len > 0 || was_composing) {
            out.deleteBeforeCursor(prov_len_);
            if (result.len > 0) {
                out.commit(utf32ToUtf8(result.chars, result.len));
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
