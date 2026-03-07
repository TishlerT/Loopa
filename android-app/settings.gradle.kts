pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Loopa"

include(":app")
include(":core:model")
include(":core:looper")
include(":core:storage")
include(":audio")
include(":feature:looper")
include(":feature:tracks")
include(":feature:editor")
