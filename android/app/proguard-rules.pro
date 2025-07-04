# Keep all ML Kit text recognition classes
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**

# Optional: Keep Flutter plugin registrars
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.plugin.**
