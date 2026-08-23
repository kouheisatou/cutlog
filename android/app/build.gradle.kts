import java.util.Properties

plugins {
    // AGP 9 から Kotlin のサポートが AGP に取り込まれたので、
    // org.jetbrains.kotlin.android は付けない（付けるとエラーになる）。
    alias(libs.plugins.android.application)
}

/**
 * つなぐ先はビルドのときに埋め込む。アプリの中で入力させない。
 *
 * 読む順番: リポジトリのルートの native.env → 無ければ native.env.example。
 * どちらも無いときは、黙って空を埋め込まずにビルドを止める
 * （どこにもつながらない APK を作っても誰も気づけないため）。
 */
fun readNativeEnv(): Properties {
    val env = rootProject.file("../native.env")
    val example = rootProject.file("../native.env.example")
    val source = when {
        env.exists() -> env
        example.exists() -> example
        else -> throw GradleException(
            "native.env が見つかりません。リポジトリのルートで " +
                "`cp native.env.example native.env` を実行し、CUTLOG_BASE_URL を書いてください。",
        )
    }
    return Properties().apply { source.inputStream().use { load(it) } }
}

val nativeEnv = readNativeEnv()

/**
 * -PcutlogBaseUrl=... で一時的に上書きできる。
 * エミュレータから手元のサーバ（http://10.0.2.2:PORT）を見て動作を確かめたいときのためで、
 * native.env そのものは書き換えない。
 */
val cutlogBaseUrl: String = (
    (project.findProperty("cutlogBaseUrl") as String?)
        ?: nativeEnv.getProperty("CUTLOG_BASE_URL")
    ).orEmpty().trim().trimEnd('/').ifEmpty {
    throw GradleException("CUTLOG_BASE_URL が空です。native.env につなぐ先の URL を書いてください。")
}

val cutlogAppName: String =
    nativeEnv.getProperty("CUTLOG_APP_NAME").orEmpty().trim().ifEmpty { "cutlog" }

android {
    namespace = "dev.cutlog.shell"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.cutlog.shell"
        minSdk = 26          // CameraX の VideoCapture とアダプティブアイコンが素直に使える下限
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        // Web 側の住所。MainActivity はこれをそのまま開く。
        buildConfigField("String", "BASE_URL", "\"$cutlogBaseUrl\"")
        // ランチャーに出る名前も native.env から取る
        manifestPlaceholders["appName"] = cutlogAppName
    }

    buildTypes {
        release {
            // 殻は薄いのでまだ縮めない。難読化で WebView のブリッジ名が壊れる事故を避ける。
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            applicationIdSuffix = ""   // 実機で本番と同じ Cookie を使えるよう、あえて分けない
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        viewBinding = true
        // AGP 9 では BuildConfig が既定で作られないので、明示して有効にする
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)

    // 撮影はネイティブで行う。ブラウザの getUserMedia では端末の手ぶれ補正・画づくりが効かないため。
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.video)
    implementation(libs.androidx.camera.view)

    // 撮ったものはネイティブから直接サーバへ上げる。巨大な動画を JS 橋に通さないため。
    implementation(libs.okhttp)
}
