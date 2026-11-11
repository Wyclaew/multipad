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

    if (project.name == "file_picker") {
        val builtInKotlinEnabled =
            (project.findProperty("android.builtInKotlin")?.toString() ?: "true").toBoolean()
        if (!builtInKotlinEnabled) {
            project.plugins.withId("com.android.library") {
                if (!project.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
                    project.plugins.apply("org.jetbrains.kotlin.android")
                }
                project.plugins.withId("org.jetbrains.kotlin.android") {
                    project.extensions.findByType(
                        org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java
                    )?.compilerOptions?.jvmTarget?.set(
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                    )
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
