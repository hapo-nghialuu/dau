# Dấu macOS 0.1.6 → 0.1.7 — Fix Log (để session mới tiếp tục)

> **Mục đích:** Ghi lại toàn bộ quá trình lặp `cài → không gõ được → killall lại được → cài lại lại không được` và các vá `0.1.7` để session mới không cần đọc lại chat.

## 1. Triệu chứng ban đầu (0.1.5 → 0.1.6)

- Sau `brew upgrade`/`cp -R` bản ad-hoc mới (`codesign -s -` mỗi build hash khác), app vẫn chạy nhưng `aa` → `aa` (không ra `â`), dù `System Settings → Accessibility` đã bật xanh.
- `killall Dau && open -a Dau` thì lại gõ được.
- `defaults read` lúc `hasCompleted=0/1` đảo, `ps` lúc `build/Release/Dau.app` lúc `/Applications/Dau.app`.

**Nguyên nhân gốc:**
1. **Ad-hoc hash đổi** → TCC lưu theo hash cũ, `AXIsProcessTrusted()` với binary mới `false` cho đến khi tắt/bật lại toggle.
2. **Onboarding 3 phase cũ** (`needsPermission/ready/setupFailed`) chỉ `NSPanel` 2 nút, không tự restart. Sau khi bật Accessibility phải bấm tay `Khởi động lại` mới `sleep 0.5; open` relaunch. Nếu đóng cửa sổ → `hasCompletedOnboarding=0` → `AppDelegate` không `startEngine()` → `eventTap` chưa `running`.
3. **TypingSession budget 12ms** quá chật cho `CGEventPost` handshake đầu tiên `10-14ms` (WindowServer) → `phase=timeout`/`fail-open` cho phím đi qua thô. GoNhanh block `5-20ms` không timeout nên chữ đầu luôn ra dấu.

## 2. Soi GoNhanh (`~/Desktop/gonhanh.org`)

- `OnboardingView.swift` 5-step `Welcome→Permission→Ready→Success→Setup` + `Timer 1s` poll `AXIsProcessTrusted`, `Ready` có nút `Khởi động lại` làm `sleep 0.5 && open "BundlePath"` + `terminate`.
- `MenuBar.swift` gating `hasCompleted && AX → startEngine else showOnboarding`, `startEngine` mới wire `RustBridge/KeyboardHookManager`.
- `RustBridge.TextInjector.injectSync` dùng `semaphore.wait()` block tới khi xong, không `fail-open` 12ms.

## 3. Port onboarding 100% (Herdr)

- **Worker** `dau-onboarding-impl` (`muse-spark` + `settings.impl.json`, `w5:p3S` 6m15s) rewrite `onboarding-view.swift` 363d AppKit → 334d SwiftUI 5-step + `hasAutoRestarted`/`onChange` auto-restart 0.9s sau `1→2`, `app-state.swift` thêm `hasCompleted/permissionGranted` + `registerDefaultSettings`, `app-delegate.swift` gating `hasCompleted&&AX` + `bundleWatcher` + `pendingRestart`. **Reviewer** `dau-reviewer` (`openai.gpt-5.6-luna`, `w5:p3T` 9m59s) `7.4/10` fix `P1` injection `'` + `P2` window retain. `345 tests 0 fail`.

**Files đổi:** `onboarding-view.swift`, `app-state.swift`, `app-delegate.swift`, `Tests/*`, `project.pbxproj`, `Casks/dau.rb`, `core/Cargo.toml`.

## 4. Vòng lặp 0.1.6 (3 lần)

- Build `0.1.6 arm64` `eea37...` → `cp -R` lên `/Applications` → `brew install` lại tải `universal` `60ca...` → `Cask` sha lệch `60ca` vs `eea37` → `brew` lỗi `SHA mismatch` → `ps` nhảy giữa `build/Release` và `/Applications` → `defaults` lúc `completed=0` lúc `1` → `eventTap` lúc `running` lúc `stopped`.
- Fix bằng `killall` + `open` thì lại `gen=1 running` và `aa`→`â` được, nhưng cài lại thì lại `stopped`.

## 5. Vá dứt điểm 0.1.7 (commit `52544e2`, `0f9b1c6`, `9ce1b06`, `15aff2b`)

- `typing-session.swift:69` `12_000_000 → 100_000_000` (100ms) để `aa` đầu tiên không `timeout` — match GoNhanh.
- `onboarding-view.swift` `hasAutoRestarted` + `onChange(step 1→2)` tự `restart()` sau 0.9s (không cần bấm tay).
- `bundle-watcher.swift` mới theo dõi `Bundle.main.executablePath` (`/Applications/Dau.app/.../Dau`) bằng `DispatchSource` debounce 0.9s → `brew upgrade`/`cp -R` đè file là tự `sleep 0.5; open "$1"` relaunch.
- `Casks/dau.rb` `postflight` thêm `killall Dau; sleep 0.5; open -a Dau` + `caveats` nhắc re-enable `Accessibility` do ad-hoc.
- Bump `core 0.1.7`, `MARKETING_VERSION 0.1.7`, `Casks 0.1.7`.

**Build & Test:**
- `xcodebuild Debug` `BUILD SUCCEEDED`, `345 tests 0 fail` (2 lần verify).
- `scripts/build/macos.sh --adhoc --version 0.1.7 --arch arm64` → `platforms/macos/build/Release/Dau.app` `0.1.7` `valid on disk`.
- `strings` có `hand.raised.fill`, `onboardingCompleted`, `sleep 0.5; /usr/bin/open "$1"`, `hasAutoRestarted`, `bundleWatcher`.

## 6. Release sạch 0.1.7

- Clean: `rm -rf dist build /Applications/Dau.app`, `defaults delete`, `tccutil reset`, `rm -f /opt/homebrew/.git/index.lock`.
- `scripts/release.sh 0.1.7` universal `x86_64+arm64` → `dist/Dau-0.1.7.zip` `2.8M` `sha256 c33c6eb5db634f8ae8d2179c92c812613df475b3813d4037fc6634215b9dfd8f` → `gh release create v0.1.7` + `update-tap.sh` → tap `hapo-nghialuu/homebrew-tap` `15aff2b`.
- Local `Casks/dau.rb` và tap đều `0.1.7 / c33c...`, `git push origin main` `0f9b1c6..9ce1b06` done.
- `brew update && brew install --cask hapo-nghialuu/tap/dau` **Verified** `🍺 installed!` (sau khi `brew uninstall` 0.1.6 và `rm` lock).

**Lặp lại sau khi cài 0.1.7:** `open -a Dau` lần đầu `defaults` chỉ `lastCheckedAt`, chưa `completed`, nhưng sau khi bật Accessibility thì auto-restart 0.9s nên lần sau gõ `aa`→`â` không cần `killall` tay nữa. `BundleWatcher` lo `brew upgrade` sau này.

## 7. Cách test như người bình thường (đã verify)

```bash
brew update
brew install --cask hapo-nghialuu/tap/dau
# hoặc brew upgrade
xattr -dr com.apple.quarantine /Applications/Dau.app 2>/dev/null
open -a Dau
# Welcome → Tiếp tục → Permission → Mở Cài đặt → bật Dau xanh → đợi 1s tự nhảy Ready → tự restart → Success → Setup Telex → Hoàn tất → menu VI → TextEdit ABC gõ aa→â, dd→đ
```

Nếu `aa` vẫn `aa` thì `killall Dau && open -a Dau` 1 lần (do ad-hoc hash), và đảm bảo input `ABC` (không phải `VI` của macOS) + Dấu `VI` cam + `Telex`.

## 8. Còn lại cho session mới

- `0.1.7` hiện đã có `hasAutoRestarted`, `BundleWatcher`, `100ms`, `postflight` nhưng chưa test `brew upgrade` từ `0.1.6 → 0.1.7` trên máy sạch khác (chỉ test `install`).
- Chưa notarize (vẫn ad-hoc), nên mỗi build vẫn đổi hash — cân nhắc `Developer ID` để hết phải re-enable Accessibility.
- `typingEnabled` chưa ghi ra `plist` (chỉ `registerDefault`), `defaults read` không thấy nhưng trong memory là `true` — có thể ghi thẳng để dễ debug.
- File watcher hiện so `CFBundleShortVersionString` + `mtime`, chưa so `sha256` binary — có thể thêm.

**Refs:** `~/.claude/plans/tidy-baking-aho.md`, `memory/macos-update-restart-requirement.md`, `memory/macos-typing-budget-fix.md`, `platforms/macos/Sources/app/bundle-watcher.swift`, `typing-session.swift:69`, `Casks/dau.rb:23-26`.
