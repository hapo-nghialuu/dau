cask "dau" do
  version "0.1.0"
  sha256 "6d1474faba3116e6457d04d235bad989e3fd3bb44e1a0f7869b6431ae8765028"

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

  # Ad-hoc signed, no notarization: gatekeeper will prompt/block; see
  # docs/release-macos.md for how to open after first download.
  caveats <<~EOS
    This build is ad-hoc signed and not notarized. On first open, right-click
    Dau.app in Finder → Open (or xattr -dr com.apple.quarantine) to allow it.
    Grant Accessibility + Input Monitoring in System Settings → Privacy & Security.
  EOS
end
