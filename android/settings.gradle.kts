// cutlog のネイティブ殻。Web 本体（リポジトリのルート）とはビルドを分けてある。
// ルート側の Node/npm ビルドに一切触らせないため、Gradle のルートはこの android/ に閉じている。
pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    // サブプロジェクト側でリポジトリを足せないようにして、依存の出所を一箇所に固定する
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "cutlog-shell"
include(":app")
