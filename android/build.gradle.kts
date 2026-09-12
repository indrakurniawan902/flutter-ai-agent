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
    pluginManager.withPlugin("com.android.library") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
    // Force JVM 17 on all subprojects to match the app's compileOptions.
    // Kotlin 2.2.x defaults to JVM 21, causing mismatch in plugin modules.
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        project.extensions.findByType(
            org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java
        )?.compilerOptions?.jvmTarget?.set(
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        )
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
