# Trying KOReader on any Android tablet

Before replacing a tablet's system, KOReader can be tried as an ordinary
app. This only installs an app: it doesn't change the system, and KOReader
can be uninstalled at any time. It works on most Android tablets, including
Amazon Fire tablets running Fire OS.

## 1. Allow apps from outside the app store

KOReader is installed from a file (an "APK") rather than from an app store.

- **Most Android tablets:** Android asks for permission the first time the
  APK is opened. Tap **Settings**, then turn on **Allow from this source** for
  the browser or file manager being used.
- **Amazon Fire:** go to **Settings → Security & Privacy → Apps from Unknown
  Sources**, then turn it on for **Silk Browser** (or the app used to open
  the file).

## 2. Download and install KOReader

1. On the tablet, open the browser and go to
   **https://github.com/koreader/koreader/releases/latest**
2. Under **Assets**, tap the file for the tablet's processor, ending in
   **`.apk`**: `android-arm64` for most tablets from about 2016 onwards,
   `android-arm` for older 32-bit ones (such as the Nexus 7 2012). If unsure,
   `arm` works on both.
3. When the download finishes, open it and tap **Install**.

KOReader is also available from
[F-Droid](https://f-droid.org/packages/org.koreader.launcher.fdroid/), which
keeps it up to date.

## 3. Add a Calibre-Web library (optional)

KOReader can browse a [Calibre-Web](https://github.com/janeczku/calibre-web)
library through OPDS.

1. Open KOReader. If it asks where your books are, pick any folder for now.
2. Tap the **top of the screen** to show the menu.
3. Tap the **magnifying glass** icon, then **OPDS catalog**.
4. Tap the **+** in the top corner and enter:
   - **Catalog name:** `Calibre-Web`
   - **Catalog URL:** `http://YOUR-SERVER:8083/opds`, replacing
     `YOUR-SERVER` with the name or address of the computer running
     Calibre-Web (8083 is its usual port)
   - **Username** and **Password:** your Calibre-Web login
5. Tap **Save**, then tap **Calibre-Web** in the list.

The library appears. Browse it or search, tap a book and choose **EPUB** to
download it. It's saved to the tablet, so it works with Wi-Fi off.

> **If it doesn't connect:** check the tablet is on the same network, and
> that `http://YOUR-SERVER:8083` opens in the tablet's browser. Calibre-Web
> must allow OPDS: as an admin, look under **Admin → Edit Basic
> Configuration → Feature Configuration**.

## 4. Settings worth trying

While reading, tap the top of the screen for the menu, or the bottom for the
font and layout settings.

- **Font and size:** bottom menu, **Aa** icon
- **Margins and line spacing:** bottom menu
- **Night mode:** top menu, cog icon → **Night mode**
- **Page turns:** tap the right side to go forward, the left side to go
  back, or swipe
- **Brightness:** top menu, cog icon → **Frontlight**. Lower brightness is the
  single biggest battery saver

## 5. Battery test

To see how long the battery lasts when reading:

1. Download a few books while on Wi-Fi.
2. Turn **Wi-Fi off** (or switch on aeroplane mode).
3. Set the screen timeout short: **Settings → Display → Screen timeout**.
4. Read as normal for a few days and note the battery percentage each day.

If KOReader suits you and the tablet is a Nexus 7 (2012) or Fire 7 (2022),
the install guides in the [README](../README.md) turn it into a dedicated
reader.
