# typed: false
# frozen_string_literal: true

class Tennis < Formula
  desc "Stylish CSV tables in your terminal."
  homepage "https://github.com/{{repo}}"
  version "{{version}}"

  on_macos do
    if Hardware::CPU.intel?
      url "https://github.com/{{repo}}/releases/download/v{{version}}/tennis_{{version}}_darwin_amd64.tar.gz"
      sha256 "{{darwin_amd64_sha256}}"
    end
    if Hardware::CPU.arm?
      url "https://github.com/{{repo}}/releases/download/v{{version}}/tennis_{{version}}_darwin_arm64.tar.gz"
      sha256 "{{darwin_arm64_sha256}}"
    end
  end

  on_linux do
    if Hardware::CPU.intel? && Hardware::CPU.is_64_bit?
      url "https://github.com/{{repo}}/releases/download/v{{version}}/tennis_{{version}}_linux_amd64.tar.gz"
      sha256 "{{linux_amd64_sha256}}"
    end
  end

  def install
    bin.install "tennis"
    man1.install "extra/tennis.1"
    bash_completion.install "extra/tennis.bash" => "tennis"
    zsh_completion.install "extra/_tennis" => "_tennis"
  end

  test do
    system bin/"tennis", "--version"
  end
end
