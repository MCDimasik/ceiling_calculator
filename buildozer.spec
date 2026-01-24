[app]
title = Ceiling Calculator
package.name = ceiling_calculator
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,ttf,db
version = 0.1
requirements = python3,kivy,kivymd,sqlite3,android
orientation = portrait
osx.python_version = 3
osx.kivy_version = 2.1.0
fullscreen = 1
android.arch = arm64-v8a
android.permissions = INTERNET,WRITE_EXTERNAL_STORAGE,READ_EXTERNAL_STORAGE
android.api = 31
android.minapi = 21
android.ndk = 23b
android.gradle_dependencies = 'com.google.android.material:material:1.4.0'
android.enable_androidx = True
p4a.branch = master
debug = 1
[buildozer]
log_level = 2
warn_on_root = 1