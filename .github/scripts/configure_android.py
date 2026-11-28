
from pathlib import Path
import re

root = Path("android/app/src/main")
manifest = root / "AndroidManifest.xml"

if not manifest.exists():
    raise SystemExit("AndroidManifest.xml bulunamadı")

xml = manifest.read_text(encoding="utf-8")

# Telefonda görünen uygulama adı
if re.search(r'<application\b[^>]*\bandroid:label=', xml):
    xml = re.sub(
        r'(<application\b[^>]*\bandroid:label=")[^"]*(")',
        r'\1Karadağ Ortaokulu\2',
        xml,
        count=1
    )
else:
    xml = re.sub(
        r'(<application\b)',
        r'\1 android:label="Karadağ Ortaokulu"',
        xml,
        count=1
    )

permissions = [
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
    "android.permission.SCHEDULE_EXACT_ALARM",
]

for name in permissions:
    if name not in xml:
        xml = xml.replace(
            "<application",
            f'    <uses-permission android:name="{name}" />\n    <application',
            1
        )

receiver_block = """
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" android:exported="false" />
        <receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver" android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
        <receiver android:name=".SchoolDayAlarmReceiver" android:exported="false" />
        <receiver android:name=".SchoolDayBootReceiver" android:enabled="true" android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
        <service android:name=".SchoolDayNotificationService" android:exported="false" android:stopWithTask="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="School timetable persistent reminder during school hours" />
        </service>
"""

if "SchoolDayAlarmReceiver" not in xml:
    xml = xml.replace(
        "</application>",
        receiver_block + "\n    </application>",
        1
    )

manifest.write_text(xml, encoding="utf-8")

# Android Kotlin kaynak klasörü
package_dir = (
    root / "kotlin" / "tr" / "k12" / "karadag" /
    "karadag_ortaokulu"
)
package_dir.mkdir(parents=True, exist_ok=True)

# Bildirim simgesi
drawable = root / "res" / "drawable"
drawable.mkdir(parents=True, exist_ok=True)

notification_icon = """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M1,17 L7,9 L10,13 L15,4 L23,17 Z M3,19 L21,19 L19,21 L5,21 Z" />
</vector>
"""

(drawable / "ic_notification.xml").write_text(
    notification_icon,
    encoding="utf-8"
)

# Kotlin dosyalarını projeye aktar
source_dir = Path("android_src")

for filename in [
    "MainActivity.kt",
    "PersistentSchoolNotification.kt"
]:
    source = source_dir / filename

    if not source.exists():
        raise SystemExit(f"{filename} bulunamadı")

    (package_dir / filename).write_text(
        source.read_text(encoding="utf-8"),
        encoding="utf-8"
    )

# Android Gradle ayarları
kts = Path("android/app/build.gradle.kts")
groovy = Path("android/app/build.gradle")

if kts.exists():
    gradle = kts.read_text(encoding="utf-8")

    if "isCoreLibraryDesugaringEnabled = true" not in gradle:
        gradle = re.sub(
            r"(compileOptions\s*\{)",
            r"\1\n        isCoreLibraryDesugaringEnabled = true",
            gradle,
            count=1
        )

    if "desugar_jdk_libs:2.1.4" not in gradle:
        if re.search(r"dependencies\s*\{", gradle):
            gradle = re.sub(
                r"(dependencies\s*\{)",
                r'\1\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
                gradle,
                count=1
            )
        else:
            gradle += """
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
"""

    kts.write_text(gradle, encoding="utf-8")

elif groovy.exists():
    gradle = groovy.read_text(encoding="utf-8")

    if "coreLibraryDesugaringEnabled true" not in gradle:
        gradle = re.sub(
            r"(compileOptions\s*\{)",
            r"\1\n        coreLibraryDesugaringEnabled true",
            gradle,
            count=1
        )

    if "desugar_jdk_libs:2.1.4" not in gradle:
        if re.search(r"dependencies\s*\{", gradle):
            gradle = re.sub(
                r"(dependencies\s*\{)",
                r'\1\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"',
                gradle,
                count=1
            )
        else:
            gradle += """
dependencies {
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"
}
"""

    groovy.write_text(gradle, encoding="utf-8")

else:
    raise SystemExit("Gradle app dosyası bulunamadı")

print("Android uygulama adı, bildirim simgesi ve Kotlin ayarları hazır.")
