[app]
title = Krutoi Calculator
package.name = ceiling_calculator
package.domain = org.test
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,db
version = 0.1
requirements = python3,kivy==2.1.0,kivymd==1.1.1,sqlite3,android,pillow==9.5.0
orientation = portrait
android.arch = arm64-v8a
android.permissions = INTERNET,WRITE_EXTERNAL_STORAGE,READ_EXTERNAL_STORAGE,ACCESS_NETWORK_STATE

[android]
# Target Android API (should be as high as possible)
android.api = 34
# Minimum API your APK will support
android.minapi = 21
# Android SDK version to use
android.sdk = 34
# Android NDK version to use
android.ndk = 25b
android.gradle_dependencies = 'com.google.android.material:material:1.8.0'
android.enable_androidx = True

[buildozer]
log_level = 2
warn_on_root = 1
