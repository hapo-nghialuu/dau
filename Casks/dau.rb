cask "dau" do
  version "0.1.3"
  sha256 "f96743062516eb9364bdfb937745c52b2e62e6ceb5220fed37e578c38d9c158b"

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
  end

  caveats <<~EOS
    This build is ad-hoc signed and not notarized. Gatekeeper quarantine is
    cleared automatically by the cask postflight; if the app still won't open,
    right-click Dau.app in Finder → Open. Grant Accessibility + Input Monitoring
    in System Settings → Privacy & Security.
  EOS
end
