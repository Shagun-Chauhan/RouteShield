# RouteShield mobile app (Flutter, Android-first)

STATUS: source code written but NOT yet compiled or run. It was written in a sandbox with no Flutter SDK.
Expect to fix a few small compile errors on your first `flutter analyze`. Tell Claude the output and they get fixed.

## One-time setup on your computer
1. Install Flutter (stable) + Android Studio (with Android SDK). Run `flutter doctor` until it is green.
2. In this `mobile/` folder generate the Android project files (this does NOT overwrite lib/ or pubspec.yaml):
   `flutter create --org com.routeshield --project-name routeshield --platforms android .`
3. `flutter pub get`
4. Edit `android/app/src/main/AndroidManifest.xml`:
   - Inside `<manifest>` (before `<application>`) add:
     ```xml
     <uses-permission android:name="android.permission.INTERNET"/>
     <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
     <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
     <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
     <queries>
       <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
       <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="tel"/></intent>
       <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="sms"/></intent>
     </queries>
     ```
   - Inside `<application>` add your Google Maps key (Maps SDK for Android enabled in Google Cloud):
     `<meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_KEY_HERE"/>`
5. In `android/app/build.gradle(.kts)` set `minSdk = 23` (needed by the plugins) and, for flutter_local_notifications, enable core library desugaring as its README describes.

## Run
- Emulator + backend on your PC: `flutter run` (default API URL http://10.0.2.2:4000/api)
- Real phone: `flutter run --dart-define=API_BASE_URL=http://<your-pc-ip>:4000/api`
- No backend yet? Register/log in anyway. The app switches to a clearly labelled DEMO MODE with sample data.

## Check and build
`flutter analyze` then `flutter test` (pure-Dart logic tests in test/logic_test.dart), then `flutter build apk --release`.

## Structure
lib/core (theme tokens, API client) | lib/models | lib/data (repository + labelled demo fallback) | lib/providers (Riverpod)
lib/services (location, notifications, deviation detector, safety-plan compiler) | lib/widgets (reusable UI) | lib/screens (all 17 screens + shell) | lib/router.dart
