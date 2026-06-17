allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// device_info_plus (pulled in transitively by supabase_flutter) requires every
// consumer module to compile against Android API 36, but some plugin modules
// still pin the Flutter default (35). Force compileSdk 36 on the plugin modules.
// (:app already sets 36 in its own build file and is evaluated early by the
// evaluationDependsOn above, so skip any already-evaluated project.)
subprojects {
    if (!state.executed) {
        afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                (ext as com.android.build.gradle.BaseExtension).compileSdkVersion(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
