# JavascriptInterface は Web 側から名前で呼ばれる。縮小・難読化で消えないよう残す。
-keepclassmembers class dev.cutlog.shell.** {
    @android.webkit.JavascriptInterface <methods>;
}
