class Rhyper < Formula
  desc "Turn the Right Command key into a Hyper key (Ctrl+Opt+Shift+Cmd)"
  homepage "https://github.com/mtak/rhyper"
  head "https://github.com/mtak/rhyper.git", branch: "main"

  depends_on :macos

  def install
    system "make", "test"
    system "make", "install", "PREFIX=#{prefix}"
  end

  service do
    run opt_bin/"rhyper"
    keep_alive crashed: true
    process_type :interactive
    log_path var/"log/rhyper.log"
    error_log_path var/"log/rhyper.log"
  end

  def caveats
    <<~EOS
      rhyper needs Accessibility permission:
        System Settings → Privacy & Security → Accessibility
      Add #{opt_bin}/rhyper (⌘⇧G in the file picker to type the path).

      The grant is tied to the binary's code signature. After every
      `brew upgrade rhyper`, remove the entry, add it again, then run:
        brew services restart rhyper
    EOS
  end

  test do
    assert_path_exists bin/"rhyper"
  end
end
