# Homebrew cask. Install with:
#   brew tap ericrisco/memslop https://github.com/ericrisco/mem-slop
#   brew install --cask memslop
# The release workflow bumps version and sha256 on every release.
cask "memslop" do
  version "1.2.0"
  sha256 "c1cfef3e383d03dc4cb9164194fccd0da7ff5eafabf25bb1127863af065712a3"

  url "https://github.com/ericrisco/mem-slop/releases/download/v#{version}/MemSlop-#{version}.zip"
  name "MemSlop"
  desc "Menu bar CPU and RAM monitor that cleans up dev slop left by AI agents"
  homepage "https://github.com/ericrisco/mem-slop"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "MemSlop.app"
  binary "#{appdir}/MemSlop.app/Contents/Helpers/memslop"

  # Ad-hoc signed, not notarized: drop the quarantine flag like the curl installer does.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/MemSlop.app"]
  end

  uninstall quit: "com.ericrisco.memslop"

  zap trash: [
    "~/Library/Application Support/MemSlop",
    "~/Library/Preferences/com.ericrisco.memslop.plist",
  ]
end
