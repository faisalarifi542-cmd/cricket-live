# Flutter / R8 release keep rules.
# Wired in android/app/build.gradle.kts release buildType via proguardFiles.

# ---- Meta / Facebook Audience Network (ads mediation) ----
# R8 failed: Missing class com.facebook.infer.annotation.Nullsafe
# (referenced from com.facebook.ads.NativeAdBase).
-keep class com.facebook.** { *; }
-dontwarn com.facebook.infer.annotation.Nullsafe
-dontwarn com.facebook.ads.**

# ---- Unity Ads (direct SDK adapter) ----
-keep class com.unity3d.ads.** { *; }
-keep class com.unity3d.services.** { *; }
-dontwarn com.unity3d.**

# ---- Google Mobile Ads (AdMob mediation host) ----
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
