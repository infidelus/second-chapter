# Plan

## Aims

1. **A tablet that feels like an e-reader.** It opens straight into the
   books and remembers the place.
2. **Less e-waste.** Old tablets get a second life instead of a drawer or a
   skip.
3. **Long battery life.** Well beyond two or three days of normal reading.
4. **More than one tablet.** The Nexus 7 (2012) first, then others.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Reading app | KOReader | Built for e-readers, fast on old hardware, reads EPUB and PDF, works offline |
| Library | Calibre-Web, through OPDS (optional) | Books download once and then work offline |
| Books with DRM (Kindle, Google) | The official web readers | DRM removal isn't part of this project |
| Nexus 7 system | Nura (formerly postmarketOS), "console" image, with a patched kernel | Light and well supported; the kernel patches fix deep sleep, switching off and colours |
| Nexus 7 display | KOReader's Kobo build drawing straight on the framebuffer, with a Second Chapter device profile | No display server or software OpenGL needed |
| Fire 7 system | LineageOS 20 (Android 13) as a generic system image | No Linux port exists for it; Android 14 needs kernel changes that aren't published |
| Building | A script on a PC builds a ready-made Nexus 7 image | The tablet has no on-screen keyboard for setting up |

## Status (November 2026)

| Device | State |
|---|---|
| Nexus 7 (2012), Wi-Fi | **Working.** Deep sleep about 1.6% an hour, about 30 seconds to start, Power menu, Calibre-Web |
| Fire 7 (2022) | **Working.** LineageOS 20 with KOReader; about 0.16% an hour asleep, 3.6% an hour reading |

Development notes: [level2-plan.md](level2-plan.md) (the Nexus 7 kernel and
start-up work) and the device notes in [devices/](devices/).

## Ideas for later

- A KOReader add-on with shortcuts to the Kindle and Google web readers, for
  the Nexus 7 (it would need a web viewer, which is heavy for this tablet).
- A progress sync server, for reading on more than one device.
- More tablets. Good candidates have an unlockable bootloader and either a
  Nura port or a Treble-compatible Android vendor. Each needs someone with
  the tablet to test it, or a tablet lent or given to the project: none will
  be bought for this.
