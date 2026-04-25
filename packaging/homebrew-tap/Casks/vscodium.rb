cask "vscodium" do
  version "0.0.0-placeholder"

  arch arm: "arm64", intel: "x64"

  on_arm do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end
  on_intel do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end

  url "https://github.com/hisgarden/vscodium/releases/download/#{version}/VSCodium.#{arch}.#{version}.dmg",
      verified: "github.com/hisgarden/vscodium/"
  name "VSCodium"
  desc "Binary releases of VS Code without MS branding/telemetry/licensing (hisgarden fork)"
  homepage "https://github.com/hisgarden/vscodium"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  conflicts_with cask: [
    "vscodium",
    "vscodium@insiders",
  ]

  app "VSCodium.app"

  binary "#{appdir}/VSCodium.app/Contents/Resources/app/bin/codium"

  zap trash: [
    "~/.vscode-oss",
    "~/Library/Application Support/VSCodium",
    "~/Library/Caches/VSCodium",
    "~/Library/Caches/VSCodium.ShipIt",
    "~/Library/Preferences/com.vscodium.plist",
    "~/Library/Preferences/com.visualstudio.code.oss.plist",
    "~/Library/Saved Application State/com.visualstudio.code.oss.savedState",
  ]
end
