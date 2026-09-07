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

    // Plugin-Module, deren eigenes Gradle noch compileSdk < 34 festlegt
    // (z. B. onnxruntime 1.4.1 mit android-33), auf das App-SDK-Level
    // heben. Sonst schlägt checkReleaseAarMetadata fehl (AndroidX
    // verlangt 34+). WICHTIG: afterEvaluate muss VOR
    // evaluationDependsOn registriert werden - sonst rennt der Block in
    // bereits evaluierte Projekte.
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            val androidExt = project.extensions.findByName("android")
                as? com.android.build.api.dsl.LibraryExtension
            if (androidExt != null) {
                val currentCompileSdk = androidExt.compileSdk ?: 0
                if (currentCompileSdk in 1..36) {
                    androidExt.compileSdk = 37
                }
            }
        }
    }

    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
