plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mycalendar.my_calendar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // A flutter_local_notifications megköveteli (ütemezett értesítések
        // visszafelé kompatibilitása régebbi Androidon).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mycalendar.my_calendar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release aláírás. CI-ben a RELEASE_KEYSTORE env a secretből visszaállított
    // kulcsra mutat; helyben nincs env, marad a debug kulcs. A secret a géped
    // debug kulcsát tartalmazza -> a CI UGYANAZZAL a kulccsal ír alá, ami a
    // Firebase-ben regisztrálva van és a telefonokon fut (felül-telepítés megy,
    // Google-bejelentkezés működik). A jelszavak a debug kulcs fix értékei.
    signingConfigs {
        create("release") {
            val ksPath = System.getenv("RELEASE_KEYSTORE")
            if (ksPath != null) {
                storeFile = file(ksPath)
                storePassword = System.getenv("RELEASE_STORE_PASSWORD") ?: "android"
                keyAlias = System.getenv("RELEASE_KEY_ALIAS") ?: "androiddebugkey"
                keyPassword = System.getenv("RELEASE_KEY_PASSWORD") ?: "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("RELEASE_KEYSTORE") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// ─────────────────────────────────────────────────────────────────────────────
// Plugin-lista őr — a visszatérő „shared_preferences hiányzik" / „töltőképernyőn
// ragad" hiba végleges elkapója.
//
// Ok: az Android Studio háttér-szinkronja és a parancssori `flutter` néha
// EGYSZERRE regenerálja a GeneratedPluginRegistrant.java-t. Egy rossz pillanatban
// futó regeneráció kihagy egy natív plugint; az app induláskor elszáll
// (MissingPluginException a prefs-nél), vagy a Gradle démon beragadt pillanatképe
// miatt már a build eldől. Ez az őr MINDEN buildnél (AS Run gomb ÉS parancssor) a
// legelején, hangosan elbukik — a javítással együtt. Így néma, törött APK sosem
// kerül a telefonra.
//
// A registrantot ellenőrizzük, mert AZ kerül a fordításba — ha a .flutter-plugins-
// dependencies is sérült, a kettő egyformán hibás, tehát a kettő összevetése nem
// fogná meg. A lista fix: ennek az appnak a kötelező, indításkritikus pluginjei.
val verifyFlutterPlugins by tasks.registering {
    val registrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    doFirst {
        val required = mapOf(
            "SharedPreferencesPlugin" to "shared_preferences (kategóriák, edzéstervek)",
            "FlutterFirebaseCorePlugin" to "firebase_core",
            "FlutterFirebaseAuthPlugin" to "firebase_auth (bejelentkezés)",
            "GoogleSignInPlugin" to "google_sign_in",
            "FlutterLocalNotificationsPlugin" to "flutter_local_notifications (emlékeztetők)",
        )
        val text = registrant.takeIf { it.exists() }?.readText().orEmpty()
        val missing = required.filterKeys { !text.contains(it) }.values
        if (missing.isNotEmpty()) {
            throw GradleException(
                "\n\n❌ SÉRÜLT A PLUGIN-LISTA — hiányzik: ${missing.joinToString(", ")}\n" +
                    "   (Az Android Studio háttér-szinkron és a parancssori flutter versenyhelyzete.)\n\n" +
                    "   JAVÍTÁS a projekt gyökeréből:\n" +
                    "       .\\build.ps1\n" +
                    "   Vagy kézzel (előbb zárd be az Android Studiót):\n" +
                    "       flutter pub get ; flutter build apk --debug\n",
            )
        }
    }
}
tasks.named("preBuild") { dependsOn(verifyFlutterPlugins) }
