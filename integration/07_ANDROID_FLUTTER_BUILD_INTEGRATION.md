# Android / Flutter Build Integration

The source package contains Brain2 Android application source and native integration assets. If your checkout does not contain a complete Flutter-generated Gradle shell, generate/repair it with the installed Flutter SDK rather than guessing Gradle plugin versions.

Recommended safe procedure from a backup/clean branch:

```bash
flutter create . --platforms=android --org com.brain2 --project-name brain2_ai_miner_mobile
```

Then preserve/restore the Brain2-owned files from this ZIP:

```text
lib/
test/
integration/
native/contextvault/
scripts/
pubspec.yaml
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/com/brain2/aiminer/MainActivity.kt
android/app/src/main/jniLibs/
```

Why this approach is preferred: Flutter pins Android Gradle/Kotlin versions appropriate to the installed Flutter toolchain. Shipping guessed Gradle plugin pins inside the Brain2 source would be less reliable across Flutter releases.

## Android package identity

Current MainActivity package:

```text
com.brain2.aiminer
```

Keep `namespace`/`applicationId` consistent with that package unless intentionally migrating app identity.

## Required permissions

The manifest already declares:

```text
android.permission.INTERNET
android.permission.CAMERA
```

Camera is used for pairing QR. Internet is used for provider/network/P2P signaling and any model download/runtime integration that requires it.

## Release build sequence

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
bash scripts/build_and_install_contextvault_android.sh
bash scripts/verify_contextvault_android.sh
flutter build apk --release
bash scripts/verify_contextvault_in_apk.sh build/app/outputs/flutter-apk/app-release.apk
```
