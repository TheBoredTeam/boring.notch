cask "boring-notch-lyrics" do
  version "1.0.0-lyrics-fork"
  sha256 "ab236a5f54bd003a6e0316e546d6c89d608551152889d6267e477da4e925db6c"

  url "https://github.com/AusafMo/boring.notch/releases/download/v#{version}/boringNotch.dmg"
  name "Boring Notch - Lyrics Fork"
  desc "Fork of Boring Notch with scrolling lyrics features"
  homepage "https://github.com/AusafMo/boring.notch"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "boringNotch.app"

  zap trash: [
    "~/Library/Application Scripts/theboringteam.boringnotch/",
    "~/Library/Containers/theboringteam.boringnotch/",
  ]

  caveats <<~EOS
    This is an unsigned build. On first launch:
    1. macOS will show "app from unidentified developer"
    2. Go to System Settings → Privacy & Security
    3. Click "Open Anyway" next to the warning
  EOS
end
