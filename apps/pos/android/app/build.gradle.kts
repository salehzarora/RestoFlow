import java.io.FileInputStream
import java.security.KeyStore
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// RELEASE-KEY-AND-PIPELINE-001 — FAIL-CLOSED production signing.
//
// Until this ticket the release buildType carried the stock Flutter template
// line `signingConfig = signingConfigs.getByName("debug")`. Every "release"
// APK the pilot ever produced was therefore signed with the shared Android
// DEBUG key: not an identity anyone controls, not one that can own an app on a
// device long-term, and one that any machine can reproduce. That is fine for
// sideloading a prototype and unacceptable for an official fleet.
//
// The replacement is deliberately fail-closed. Signing material lives OUTSIDE
// this repository, in a properties file whose path arrives through the
// RESTOFLOW_ANDROID_SIGNING_PROPERTIES environment variable (or the
// `restoflow.android.signingProperties` Gradle property). When anything about
// that chain is missing or wrong, the release build STOPS. It never quietly
// falls back to debug signing, because a fallback is exactly how an unsigned
// or wrongly-signed build reaches a restaurant unnoticed.
//
// Debug builds are untouched and keep the normal debug signing config.
//
// This block is duplicated verbatim in apps/kds. A shared script plugin was
// considered and rejected: configuring the AGP `android` extension from an
// external .gradle.kts requires internal AGP types (no type-safe accessors
// outside the module), which is more fragile than a reviewed copy. The two
// copies are kept honest by tools/android_release/check_signing_identity.ps1,
// which fails if they drift.
// ---------------------------------------------------------------------------

val restoflowSigningPropsPath: String? =
    System.getenv("RESTOFLOW_ANDROID_SIGNING_PROPERTIES")
        ?: (project.findProperty("restoflow.android.signingProperties") as String?)

val restoflowSigningProps: Properties? =
    restoflowSigningPropsPath
        ?.takeIf { it.isNotBlank() }
        ?.let { File(it) }
        ?.takeIf { it.isFile }
        ?.let { f -> Properties().apply { f.inputStream().use { load(it) } } }

/**
 * Null when production signing is fully usable; otherwise a SHORT, NON-SECRET
 * reason. Never returns a password, a path, or an exception message — a build
 * log is not a place to widen the blast radius of a misconfiguration.
 */
fun restoflowSigningProblem(): String? {
    if (restoflowSigningPropsPath.isNullOrBlank()) return "signing properties path is not set"
    val props = restoflowSigningProps ?: return "signing properties file is not readable"
    val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    if (required.any { props.getProperty(it).isNullOrBlank() }) {
        return "signing properties are incomplete"
    }
    val store = File(props.getProperty("storeFile"))
    if (!store.isFile) return "keystore file is missing"
    return try {
        val keyStore = KeyStore.getInstance("PKCS12")
        FileInputStream(store).use { keyStore.load(it, props.getProperty("storePassword").toCharArray()) }
        val alias = props.getProperty("keyAlias")
        if (!keyStore.containsAlias(alias)) {
            "signing alias is not present in the keystore"
        } else {
            // Proves the key itself unlocks, not merely that the store opens.
            keyStore.getKey(alias, props.getProperty("keyPassword").toCharArray())
            null
        }
    } catch (_: Exception) {
        "keystore could not be opened with the supplied credentials"
    }
}

android {
    namespace = "com.restoflow.pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // RestoFlow POS — pilot Android package (ANDROID-001).
        applicationId = "com.restoflow.pos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Created ONLY when the whole chain resolves. Its absence is what makes
        // the release buildType below resolve to null instead of to debug.
        if (restoflowSigningProblem() == null) {
            val props = restoflowSigningProps!!
            create("release") {
                storeFile = File(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // NEVER `signingConfigs.getByName("debug")`. `findByName` yields null
            // when production signing is unavailable, and the guard task below
            // fails the build before anything is compiled.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

/**
 * The fail-closed gate. Wired into `preReleaseBuild` so it runs BEFORE the
 * release variant compiles, and additionally onto the package/assemble/bundle
 * tasks so no release path can reach packaging unguarded.
 */
val restoflowValidateReleaseSigning =
    tasks.register("restoflowValidateReleaseSigning") {
        group = "verification"
        description = "Refuses a release build unless production signing is fully usable."
        doLast {
            val problem = restoflowSigningProblem()
            if (problem != null) {
                throw GradleException(
                    "Production Android signing configuration is unavailable ($problem). " +
                        "This release build is refused - RestoFlow never signs a release with " +
                        "the debug key. See docs/ANDROID_RELEASE_SIGNING.md."
                )
            }
        }
    }

tasks.matching {
    it.name == "preReleaseBuild" ||
        it.name == "packageRelease" ||
        it.name == "assembleRelease" ||
        it.name == "bundleRelease"
}.configureEach { dependsOn(restoflowValidateReleaseSigning) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
