// Unit tests for resolveStrategy (no fcitx5).

#include "strategy_resolver.h"

#include <cstdlib>
#include <iostream>

namespace {

int g_failures = 0;

void expect(bool cond, const char *msg) {
    if (!cond) {
        std::cerr << "FAIL: " << msg << "\n";
        ++g_failures;
    }
}

void expectEq(dau::Strategy got, dau::Strategy want, const char *msg) {
    if (got != want) {
        std::cerr << "FAIL: " << msg << "\n  got:  " << static_cast<int>(got)
                  << "\n  want: " << static_cast<int>(want) << "\n";
        ++g_failures;
    }
}

void test_unknown_with_preedit() {
    expectEq(dau::resolveStrategy(DauStrategy_Unknown, true),
             dau::Strategy::Preedit,
             "Unknown + hasPreedit → Preedit");
}

void test_unknown_without_preedit() {
    expectEq(dau::resolveStrategy(DauStrategy_Unknown, false),
             dau::Strategy::CommitAtom,
             "Unknown + !hasPreedit → CommitAtom");
}

void test_config_commit_atom_overrides_cap() {
    expectEq(dau::resolveStrategy(DauStrategy_CommitAtom, true),
             dau::Strategy::CommitAtom,
             "config CommitAtom wins even when hasPreedit");
}

void test_config_passthrough() {
    expectEq(dau::resolveStrategy(DauStrategy_Passthrough, true),
             dau::Strategy::Passthrough,
             "Passthrough + hasPreedit → Passthrough");
    expectEq(dau::resolveStrategy(DauStrategy_Passthrough, false),
             dau::Strategy::Passthrough,
             "Passthrough + !hasPreedit → Passthrough");
}

void test_config_preedit() {
    expectEq(dau::resolveStrategy(DauStrategy_Preedit, false),
             dau::Strategy::Preedit,
             "config Preedit wins even when !hasPreedit");
}

} // namespace

int main() {
    test_unknown_with_preedit();
    test_unknown_without_preedit();
    test_config_commit_atom_overrides_cap();
    test_config_passthrough();
    test_config_preedit();

    if (g_failures != 0) {
        std::cerr << g_failures << " assertion(s) failed\n";
        return 1;
    }
    std::cout << "All strategy_resolver tests passed\n";
    return 0;
}
