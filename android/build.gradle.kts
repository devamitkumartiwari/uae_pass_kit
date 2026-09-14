group = "com.therivanta.uae_pass_kit"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.therivanta.uae_pass_kit"

    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 28
    }
}

dependencies {
    // The official UAE Pass Android SDK (ae.sdg.libraryuaepass) is only
    // distributed as a raw .aar, vendored here under libs/ — there is no
    // Maven Central/Google artifact for it. Referenced as a direct file
    // dependency (rather than a `flatDir` repository) since a `flatDir`
    // declared in this module's own `repositories {}` isn't visible to a
    // consuming app's dependency resolution once this module is pulled in
    // as an included build by Flutter's plugin loader.
    implementation(files("libs/libraryuaepass.aar"))
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("com.squareup.retrofit2:converter-scalars:2.9.0")
    implementation("com.google.code.gson:gson:2.8.6")
    implementation("com.loopj.android:android-async-http:1.4.9")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
