cask "vscodium-insiders" do
  version "0.0.0-placeholder"

  arch arm: "arm64", intel: "x64"

  on_arm do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end
  on_intel do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end

  url "https://github.com/hisgarden/vscodium-insiders/releases/download/#{version}/VSCodium-Insiders.#{arch}.#{version}.dmg",
      verified: "github.com/hisgarden/vscodium-insiders/"
  name "VSCodium Insiders"
  desc "Insiders build of VSCodium (hisgarden fork)"
  homepage "https://github.com/hisgarden/vscodium-insiders"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  conflicts_with cask: [
    "vscodium-insiders",
    "vscodium",
  ]

  app "VSCodium - Insiders.app"

  binary "#{appdir}/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders"

  zap trash: [
    "~/.vscode-oss-insiders",
    "~/Library/Application Support/VSCodium - Insiders",
    "~/Library/Caches/VSCodium - Insiders",
    "~/Library/Caches/VSCodium - Insiders.ShipIt",
    "~/Library/Preferences/com.vscodium-insiders.plist",
  ]
end
