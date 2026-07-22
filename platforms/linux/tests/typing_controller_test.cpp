// Unit tests for TypingController + MockSink (no fcitx5).
// Build: target `dau_typing_test` (links rust_bridge + typing_controller + libdau_core.a).

#include "typing_controller.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

int g_failures = 0;

void expect(bool cond, const char *msg) {
    if (!cond) {
        std::cerr << "FAIL: " << msg << "\n";
        ++g_failures;
    }
}

void expectEq(const std::string &got, const std::string &want, const char *msg) {
    if (got != want) {
        std::cerr << "FAIL: " << msg << "\n  got:  \"" << got << "\"\n  want: \""
                  << want << "\"\n";
        ++g_failures;
    }
}

// Records OutputSink calls as "op:arg" strings for sequence assertions.
struct MockSink : dau::OutputSink {
    std::vector<std::string> ops;

    void setPreedit(const std::string &utf8) override {
        ops.push_back("setPreedit:" + utf8);
    }
    void commit(const std::string &utf8) override {
        ops.push_back("commit:" + utf8);
    }
    void forward() override { ops.push_back("forward"); }
    void deleteBeforeCursor(uint32_t nChars) override {
        ops.push_back("delete:" + std::to_string(nChars));
    }

    void clear() { ops.clear(); }

    bool hasOp(const std::string &op) const {
        for (const auto &o : ops) {
            if (o == op) {
                return true;
            }
        }
        return false;
    }

    bool hasAnyPrefix(const char *prefix) const {
        const std::string p(prefix);
        for (const auto &o : ops) {
            if (o.rfind(p, 0) == 0) {
                return true;
            }
        }
        return false;
    }

    std::string lastPreedit() const {
        for (auto it = ops.rbegin(); it != ops.rend(); ++it) {
            if (it->rfind("setPreedit:", 0) == 0) {
                return it->substr(std::string("setPreedit:").size());
            }
        }
        return "";
    }

    std::string lastCommit() const {
        for (auto it = ops.rbegin(); it != ops.rend(); ++it) {
            if (it->rfind("commit:", 0) == 0) {
                return it->substr(std::string("commit:").size());
            }
        }
        return "";
    }
};

void typeAscii(dau::TypingController &ctl, MockSink &sink, const char *s) {
    for (const char *p = s; *p; ++p) {
        const auto ch = static_cast<uint32_t>(static_cast<unsigned char>(*p));
        const bool consumed =
            ctl.handle(dau::KeyKind::Printable, ch, false, 0, sink);
        expect(consumed, "printable key should be consumed while engine on");
    }
}

// Fresh bridge with auto-cap off so preedit matches lowercase Telex fixtures.
dau::RustBridge makeBridge() {
    dau::RustBridge bridge;
    bridge.setAutoCapitalize(false);
    bridge.setAutoRestore(false);
    return bridge;
}

// Telex: t,i,e,e,n,g,s → preedit grows to "tiếng"
void test_telex_tieengs_preedit() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    typeAscii(ctl, sink, "tieengs");

    expectEq(sink.lastPreedit(), "tiếng",
             "after tieengs preedit should be tiếng");
    expect(ctl.isComposing(), "should be composing after printable keys");
    expect(sink.hasOp("setPreedit:tiếng"), "final setPreedit(tiếng) recorded");
    // Incremental preedits should have been emitted (at least one per key).
    expect(sink.ops.size() >= 7, "expect one setPreedit per key (7 keys)");
    // No commit yet — still composing.
    for (const auto &o : sink.ops) {
        expect(o.rfind("commit:", 0) != 0, "no commit during preedit phase");
    }
}

// Break(space) → clear preedit + commit("tiếng"), return false (space passes).
void test_break_commits_word() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    typeAscii(ctl, sink, "tieengs");
    sink.clear();

    const bool consumed =
        ctl.handle(dau::KeyKind::Break, 0, false, static_cast<uint32_t>(' '),
                   sink);
    expect(!consumed, "break must return false so space reaches the app");
    expect(sink.hasOp("setPreedit:"), "preedit cleared on break");
    expect(sink.hasOp("commit:tiếng"), "commit finished word tiếng");
    expect(!ctl.isComposing(), "not composing after break");

    // Order: setPreedit("") then commit("tiếng")
    expect(sink.ops.size() >= 2, "break emits clear + commit");
    if (sink.ops.size() >= 2) {
        expectEq(sink.ops[0], "setPreedit:", "first op clears preedit");
        expectEq(sink.ops[1], "commit:tiếng", "second op commits word");
    }
}

// Escape after "user" → commit raw "user", swallow ESC.
void test_escape_restores_raw() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    typeAscii(ctl, sink, "user");
    sink.clear();

    const bool consumed =
        ctl.handle(dau::KeyKind::Escape, 0, false, 0, sink);
    expect(consumed, "ESC while composing should be swallowed");
    expect(sink.hasOp("setPreedit:"), "preedit cleared on escape");
    expect(sink.hasOp("commit:user"), "escape commits raw user");
    expect(!ctl.isComposing(), "not composing after escape");
}

// Escape with empty buffer → not consumed.
void test_escape_idle() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    const bool consumed =
        ctl.handle(dau::KeyKind::Escape, 0, false, 0, sink);
    expect(!consumed, "ESC with no compose should pass through");
    expect(sink.ops.empty(), "idle escape emits no sink ops");
}

// Modifier → resetCompose (preedit cleared).
void test_modifier_resets() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    typeAscii(ctl, sink, "abc");
    sink.clear();

    const bool consumed =
        ctl.handle(dau::KeyKind::Modifier, 0, false, 0, sink);
    expect(!consumed, "modifier must not be consumed by controller");
    expect(sink.hasOp("setPreedit:"), "modifier clears preedit");
    expect(!ctl.isComposing(), "not composing after modifier");
    for (const auto &o : sink.ops) {
        expect(o.rfind("commit:", 0) != 0,
               "modifier reset should not commit text");
    }
}

// Other while composing → commit current preedit, then forward (return false).
void test_other_commits_then_forward() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    typeAscii(ctl, sink, "aa");
    // Telex "aa" → "â"
    expectEq(sink.lastPreedit(), "â", "aa should compose to â");
    sink.clear();

    const bool consumed =
        ctl.handle(dau::KeyKind::Other, 0, false, 0, sink);
    expect(!consumed, "Other returns false (key forwards after commit)");
    expect(sink.hasOp("setPreedit:"), "Other clears preedit");
    expect(sink.hasOp("commit:â"), "Other commits current preedit");
    expect(!ctl.isComposing(), "not composing after Other");
}

// CommitAtom: each printable → delete provisional + commit growing word.
void test_commit_atom_tieengs() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    ctl.setStrategy(dau::Strategy::CommitAtom, sink);
    expect(ctl.strategy() == dau::Strategy::CommitAtom, "strategy is CommitAtom");

    typeAscii(ctl, sink, "tieengs");

    // No preedit in commit-atom mode.
    for (const auto &o : sink.ops) {
        expect(o.rfind("setPreedit:", 0) != 0,
               "CommitAtom must not use setPreedit");
    }

    // Growing delete+commit pairs: 7 keys → at least 7 delete + 7 commit.
    expect(sink.ops.size() >= 14, "expect delete+commit per key");
    expectEq(sink.lastCommit(), "tiếng", "final provisional commit is tiếng");
    expect(sink.hasOp("commit:tiếng"), "commit tiếng recorded");

    // First key: delete:0 then commit:t
    expect(sink.ops.size() >= 2, "first key emits at least 2 ops");
    if (sink.ops.size() >= 2) {
        expectEq(sink.ops[0], "delete:0", "first key deletes 0 provisional");
        expectEq(sink.ops[1], "commit:t", "first key commits t");
    }

    // Alternating delete/commit pattern for all printable keys.
    size_t deleteCount = 0;
    size_t commitCount = 0;
    for (const auto &o : sink.ops) {
        if (o.rfind("delete:", 0) == 0) {
            ++deleteCount;
        } else if (o.rfind("commit:", 0) == 0) {
            ++commitCount;
        }
    }
    expect(deleteCount == 7, "one delete per printable key");
    expect(commitCount == 7, "one commit per printable key");

    // Break space → delete provisional + commit final "tiếng", space passes.
    sink.clear();
    const bool consumed =
        ctl.handle(dau::KeyKind::Break, 0, false, static_cast<uint32_t>(' '),
                   sink);
    expect(!consumed, "CommitAtom break returns false");
    expect(sink.hasOp("delete:5"), "delete 5 code points of tiếng");
    expect(sink.hasOp("commit:tiếng"), "break re-commits final tiếng");
    expect(!ctl.isComposing(), "not composing after CommitAtom break");
    for (const auto &o : sink.ops) {
        expect(o.rfind("setPreedit:", 0) != 0,
               "CommitAtom break must not use setPreedit");
    }
    // Order: delete then commit
    if (sink.ops.size() >= 2) {
        expectEq(sink.ops[0], "delete:5", "break first deletes provisional");
        expectEq(sink.ops[1], "commit:tiếng", "break then commits final");
    }
}

// Passthrough: every key returns false; no bridge side-effects on sink.
void test_passthrough_forwards_all() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    ctl.setStrategy(dau::Strategy::Passthrough, sink);

    // Printable
    expect(!ctl.handle(dau::KeyKind::Printable, 'a', false, 0, sink),
           "passthrough printable forwards");
    // Break
    expect(!ctl.handle(dau::KeyKind::Break, 0, false, ' ', sink),
           "passthrough break forwards");
    // Escape
    expect(!ctl.handle(dau::KeyKind::Escape, 0, false, 0, sink),
           "passthrough escape forwards");
    // Modifier
    expect(!ctl.handle(dau::KeyKind::Modifier, 0, false, 0, sink),
           "passthrough modifier forwards");
    // Other
    expect(!ctl.handle(dau::KeyKind::Other, 0, false, 0, sink),
           "passthrough other forwards");

    expect(sink.ops.empty(), "passthrough emits no sink ops");
    expect(!ctl.isComposing(), "passthrough never composes");

    // Ensure bridge was not left in a composing state: a subsequent Preedit
    // session after switch must start clean (no leftover buffer).
    // (setStrategy will resetCompose)
    ctl.setStrategy(dau::Strategy::Preedit, sink);
    sink.clear();
    typeAscii(ctl, sink, "a");
    expectEq(sink.lastPreedit(), "a", "fresh preedit after passthrough");
}

// Mid-session Preedit → CommitAtom must resetCompose (clear preedit).
void test_set_strategy_resets_preedit() {
    dau::RustBridge bridge = makeBridge();
    dau::TypingController ctl(&bridge);
    MockSink sink;

    typeAscii(ctl, sink, "ti");
    expect(ctl.isComposing(), "composing in Preedit before switch");
    expect(sink.hasAnyPrefix("setPreedit:"), "had preedit ops");
    sink.clear();

    ctl.setStrategy(dau::Strategy::CommitAtom, sink);
    expect(sink.hasOp("setPreedit:"),
           "setStrategy Preedit→CommitAtom clears preedit");
    expect(!ctl.isComposing(), "not composing after strategy switch");
    expect(ctl.strategy() == dau::Strategy::CommitAtom,
           "strategy is now CommitAtom");

    // Next key should use commit-atom path (delete+commit, no preedit).
    sink.clear();
    expect(ctl.handle(dau::KeyKind::Printable, 'a', false, 0, sink),
           "first CommitAtom key consumed");
    expect(sink.hasOp("delete:0"), "CommitAtom starts with delete:0");
    expect(sink.hasOp("commit:a"), "CommitAtom commits a");
    for (const auto &o : sink.ops) {
        expect(o.rfind("setPreedit:", 0) != 0,
               "no preedit after switch to CommitAtom");
    }
}

} // namespace

int main() {
    test_telex_tieengs_preedit();
    test_break_commits_word();
    test_escape_restores_raw();
    test_escape_idle();
    test_modifier_resets();
    test_other_commits_then_forward();
    test_commit_atom_tieengs();
    test_passthrough_forwards_all();
    test_set_strategy_resets_preedit();

    if (g_failures != 0) {
        std::cerr << g_failures << " assertion(s) failed\n";
        return 1;
    }
    std::cout << "All typing_controller tests passed\n";
    return 0;
}
