# Loopa ProGuard Rules
# Keep kotlinx.serialization classes
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}

-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.loopa.**$$serializer { *; }
-keepclassmembers class com.loopa.** {
    *** Companion;
}
-keepclasseswithmembers class com.loopa.** {
    kotlinx.serialization.KSerializer serializer(...);
}
