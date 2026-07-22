#pragma once

#include "output_sink.h"

namespace fcitx {
class InputContext;
}

namespace dau {

// OutputSink backed by an fcitx5 InputContext (preedit + commitString).
class Fcitx5Sink : public OutputSink {
public:
    explicit Fcitx5Sink(fcitx::InputContext *ic);

    void setPreedit(const std::string &utf8) override;
    void commit(const std::string &utf8) override;
    void forward() override;
    void deleteBeforeCursor(uint32_t nChars) override;

private:
    fcitx::InputContext *ic_ = nullptr;
};

} // namespace dau
