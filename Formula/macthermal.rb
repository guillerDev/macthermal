# Homebrew formula for macthermal.
#
# This file belongs in your TAP repo (github.com/USER/homebrew-tap) under
# Formula/macthermal.rb. It is staged here for convenience.
#
# Before publishing, replace USER with your GitHub username, tag a release
# (e.g. v0.1.0), then fill in the sha256 of the release tarball:
#   curl -sL https://github.com/USER/macthermal/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
#
# Test locally without a release:
#   brew install --build-from-source --HEAD ./Formula/macthermal.rb
class Macthermal < Formula
  desc "macOS temperature & fan-speed analyzer (reads the SMC via IOKit)"
  homepage "https://github.com/USER/macthermal"
  url "https://github.com/USER/macthermal/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/USER/macthermal.git", branch: "main"

  depends_on :macos

  def install
    system "make", "build"
    bin.install "macthermal"
  end

  test do
    assert_match "macthermal", shell_output("#{bin}/macthermal --help")
  end
end
