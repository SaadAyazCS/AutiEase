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

subprojects {
    val fixNamespace = Action<Project> {
        if (project.name == "vosk_flutter") {
            val android = project.extensions.findByName("android") as? com.android.build.gradle.LibraryExtension
            android?.namespace = "org.vosk.vosk_flutter"
        }
    }

    if (project.state.executed) {
        fixNamespace.execute(project)
    } else {
        project.afterEvaluate(fixNamespace)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
