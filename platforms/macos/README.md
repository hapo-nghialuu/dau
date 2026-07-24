# Dấu — macOS bridge

CGEventTap + Swift menu-bar app over the shared `dau-core` C ABI.

## Layout

```text
platforms/macos/
├── Dau.xcodeproj/          # schemes: Dau, DauTests
├── Sources/
│   ├── app/                # @main, AppDelegate, AppState
│   ├── bridge/             # DauCoreBridge, mapper, MacKeyPipeline
│   ├── config/             # injection profiles + resolver
│   ├── input/              # EventTap, classifier, focus, input-source
│   ├── output/             # TextInjector, methods, AX helpers
│   └── ui/                 # menu bar, Accessibility onboarding
├── Support/dau-bridging-header.h
├── Resources/              # Info.plist, entitlements, profiles.toml
└── Tests/                  # unit tests (no live CGEvent posts)
```

## Build

```bash
./scripts/build/macos.sh --debug
./scripts/build/macos.sh --adhoc
```

```bash
xcodebuild test \
  -project platforms/macos/Dau.xcodeproj \
  -scheme Dau \
  -destination 'platform=macOS'
```

Artifacts: `platforms/macos/build/Debug/Dau.app` (or Release).

## Run (dev)

1. Build Debug.
2. Launch `platforms/macos/build/Debug/Dau.app`.
3. Grant **Accessibility** when prompted (menu bar shows `Dấu?` until trusted).
4. Menu bar: **VI/EN**, **Telex/VNI**, restart tap, quit.
5. Type Telex in Terminal (`tieengs` → `tiếng`).

## Runtime path

```text
CGEventTap → KeyClassifier → profile resolve (cached)
  → MacKeyPipeline (dau-core) → BridgeResult
  → TextInjector (backspace + Unicode, synthetic marker)
```

Toggle EN, focus change, tap restart, and non-Latin / Vietnamese IME input sources clear compose state.

## Entitlements

| File | Notes |
|------|--------|
| `Dau.entitlements.dev` | no sandbox; `get-task-allow` (Debug) |
| `Dau.entitlements.production` | no sandbox; no `get-task-allow` |

Accessibility is a **TCC user grant**, not an entitlement. This app never writes the TCC database.

## Bundle id (placeholder)

`io.github.hapo-nghialuu.dau` — change only with release-owner approval (TCC re-auth).

## Out of scope (later WPs)

- Full P3 injection matrix (selection / empty prefix / syncProxy / axDirect product paths)
- Advanced settings UI / profile editor
- Developer ID + notarize (P4)
- Core / Linux changes
