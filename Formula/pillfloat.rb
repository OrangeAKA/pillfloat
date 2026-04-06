class Pillfloat < Formula
  desc "Reposition the Wispr Flow dictation pill anywhere on your screen"
  homepage "https://github.com/OrangeAKA/pillfloat"
  url "https://github.com/OrangeAKA/pillfloat.git",
      tag:      "v1.0.0",
      revision: "PLACEHOLDER"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    app_bundle = buildpath/"PillFloat.app/Contents"
    (app_bundle/"MacOS").mkpath
    (app_bundle/"Resources").mkpath
    cp ".build/release/PillFloat", app_bundle/"MacOS/PillFloat"
    cp "Resources/Info.plist", app_bundle/"Info.plist"

    prefix.install "PillFloat.app"
    bin.write_exec_script prefix/"PillFloat.app/Contents/MacOS/PillFloat"
  end

  def caveats
    <<~EOS
      PillFloat requires Accessibility permission.
      On first launch, grant access in:
        System Settings -> Privacy & Security -> Accessibility

      The app has been installed to:
        #{prefix}/PillFloat.app

      You can also run it from the command line:
        pillfloat
    EOS
  end

  test do
    assert_predicate bin/"PillFloat", :executable?
  end
end
