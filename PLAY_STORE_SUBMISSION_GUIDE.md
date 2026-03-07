# Loopa — Play Store Submission Guide

## Prerequisites
1. A Google Play Developer account ($25 one-time fee)
2. A signing keystore for the release build
3. An Android device or emulator for screenshot capture

## Step 1: Generate Signing Keystore

```bash
keytool -genkey -v -keystore loopa-release.keystore \
    -alias loopa -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass <your-store-password> -keypass <your-key-password>
```

## Step 2: Configure Signing in Gradle

Edit `android-app/app/build.gradle.kts`:

```kotlin
android {
    signingConfigs {
        create("release") {
            storeFile = file("../loopa-release.keystore")
            storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            keyAlias = "loopa"
            keyPassword = System.getenv("KEY_PASSWORD") ?: ""
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // ... existing config
        }
    }
}
```

## Step 3: Build Release Bundle

```bash
cd android-app
./gradlew bundleRelease
```

The AAB will be at `app/build/outputs/bundle/release/app-release.aab` (~6.8 MB).

## Step 4: Capture Screenshots

On a device or emulator, install the debug APK and capture screenshots for:
1. Main screen (looper with keyboard)
2. Drum pad mode
3. Tracks mixer
4. Piano roll editor
5. Drum grid editor
6. BPM editor
7. Vocal recording mode

Recommended sizes:
- Phone: 1920×1080 or 2560×1440
- Tablet: 2560×1600
- Feature graphic: 1024×500

## Step 5: Create Play Console Listing

1. Go to https://play.google.com/console
2. Create new app → "Loopa"
3. Fill in store listing from `android-app/store/listing.md`
4. Upload screenshots
5. Upload feature graphic

## Step 6: Content Rating

Complete the content rating questionnaire. Loopa:
- Has no violence, sexual content, or gambling
- Has no ads or in-app purchases
- Does not collect user data
- Rating: Everyone

## Step 7: Data Safety

Answer the data safety questionnaire:
- Does the app collect data? **No**
- Does the app share data? **No**
- Data encrypted in transit: **N/A** (no network calls)
- Data deletion: **N/A** (no data collected)

## Step 8: Upload AAB

1. Go to Production → Create new release
2. Upload `app-release.aab`
3. Add release notes (e.g., "Initial release - Loop-based music creation with 9 instruments")
4. Review and rollout

## Step 9: Privacy Policy

Host the contents of `PRIVACY_POLICY.md` at a public URL and add it to the store listing.

## App Size

The release bundle is approximately 6.8 MB. The majority is the GM.sf2 SoundFont file (~6 MB). This is well within Play Store limits.

## Pricing

Free, no ads, no in-app purchases.
