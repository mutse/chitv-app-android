allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Workaround for AGP/Lint crash in better_player_plus:
// IncompatibleClassChangeError from androidx.lifecycle lint detector
// (NullSafeMutableLiveData) during :better_player_plus:lintVitalAnalyzeRelease.
subprojects {
    if (name == "better_player_plus") {
        tasks.matching { it.name.contains("lint", ignoreCase = true) }
            .configureEach {
                enabled = false
            }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
