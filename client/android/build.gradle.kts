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
// AJUSTE A MANO (no lo genera flutter create): tflite_flutter 0.12.1 compila su
// Java para 11 pero deja Kotlin en el JDK de la maquina (21), y Gradle se niega a
// compilar con los dos distintos. Se iguala Kotlin a 11 solo en ese plugin. Si se
// regenera android/ o el plugin lo arregla, revisar si sigue haciendo falta.
subprojects {
    if (name == "tflite_flutter") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
