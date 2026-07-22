#pragma once

#include <string>

namespace dau {

// Pure output surface for typing actions. Host-IME free — mockable in unit tests.
struct OutputSink {
    virtual ~OutputSink() = default;

    // Draw underlined preedit (empty string clears preedit).
    virtual void setPreedit(const std::string &utf8) = 0;

    // Commit real text into the document.
    virtual void commit(const std::string &utf8) = 0;

    // Let the original key pass through (engine will not filterAndAccept).
    virtual void forward() = 0;
};

} // namespace dau
