cask "dau" do
  version "0.1.13"
  sha256 "e0ba561276f11d1bb4921298509246be93d8b3a94b9667cc6f0fe67c5c123fc4"

  url "https://github.com/hapo-nghialuu/dau/releases/download/v#{version}/Dau-#{version}.zip"
  name "Dấu"
  desc "Vietnamese input method (Telex & VNI) for macOS, offline and private"
  homepage "https://github.com/hapo-nghialuu/dau"

  depends_on macos: :ventura

  livecheck do
    url :homepage
    strategy :github_latest_release
  end

  app "Dau.app"

  # Ad-hoc signed, not notarized. postflight strips the Gatekeeper quarantine
  # flag so a Homebrew install can open without Right-click → Open. This does
  # NOT grant Accessibility / Input Monitoring, which users must still enable
  # manually in System Settings (docs/release-macos.md).
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{staged_path}/Dau.app"]
    # Auto-restart after install/upgrade so the new binary's event-tap is used.
    # The old process holds the previous ad-hoc code signature; without restart typing fails.
    system_command "/bin/sh",
                   args: ["-c", "killall Dau 2>/dev/null; sleep 0.5; open -a Dau 2>/dev/null || open \"#{staged_path}/Dau.app\" 2>/dev/null || true"]
  end

  caveats <<~EOS
    This build is ad-hoc signed and not notarized. Gatekeeper quarantine is
    cleared automatically by the cask postflight; if the app still won't open,
    right-click Dau.app in Finder → Open.

    After install/upgrade the app is automatically restarted so the new binary's
    event-tap is used. Because ad-hoc signatures change each build, macOS may
    require re-enabling Accessibility for the new binary:
      System Settings → Privacy & Security → Accessibility → toggle Dau off/on.
    If typing still fails, run: killall Dau && open -a Dau
  EOS
end
