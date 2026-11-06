# Veil

<p align="center">
  <img src="Assets/veil-icon.png" alt="Veil logo" width="128">
</p>

Veil is a free macOS app for presenting on screen: choose the windows or
apps you want to show, arrange the canvas and camera, then share the
Capture Area window in Zoom, Google Meet, or Microsoft Teams. Veil is
written from scratch with SwiftUI and ScreenCaptureKit, with original
code.

The idea behind the name: a veil sits between your desktop and your
audience. Only what you lift the veil for is seen. Everything else —
other windows, notifications, private chats — stays behind it. Panic
drops the veil instantly.

## Features

- **Sources**: windows grouped by app, with search, Allow List and
  Block List modes, plus Reset All Sources and Refresh. The list shows
  on-screen windows (at least 20 pt on each side) and refreshes every
  time Sources is opened. Windows with an empty title are shown under
  their app name. Selecting a background app brings it forward so its
  first live frame appears right away. Reset All Sources also closes
  the file mode.
- **Display**: choose the display to capture, with Full Display and
  Isolated explanations inside the popup. The built-in display is the
  default; the display is chosen only manually and is never changed by
  a preset or by clearing one. Choosing No Display pauses the output.
- **Framing & Canvas**: framing Screen (the whole display) or Dynamic
  (the capture area follows the combined frames of the selected
  windows); canvas Full Display (the whole display, menu bar and Dock
  included) or Isolated/Sanitized (only the selected windows over a
  chosen background: black, white, gray, or a custom image). The
  positioned canvas follows a window that reaches under the Dock, and
  a fullscreen source fills the display without the menu bar.
- **Presets**: two built-in presets, Presentation and Meeting (both
  Sanitized, Screen, black background, camera on), plus any presets
  you create yourself. A new preset saves your current setup
  automatically. Presets can be applied, overwritten with the current
  setup, reset, renamed, reordered, and deleted. The X on a preset
  only clears the selection — sharing keeps running. A preset stores
  the mode, framing, canvas, windows, camera, and the active file (a
  file counts as a source). Presets are stored in UserDefaults under
  the key `Veil.presets`.
- **Camera**: camera overlay with 9 positions, 3 shapes (circle,
  square, rounded), size 50%–300%,
  position margins, a mirror option, and a device picker. The camera
  is on by default at size 110. A camera toggle sits at the
  bottom-right of the Preview.
- **Files**: PDF sources (full page navigation via PDFKit, with
  neighboring pages pre-rendered so next/previous feels instant) and
  PPT/PPTX sources (first-slide preview via QuickLook). A file
  controller pill — previous, page number, next, file list, close —
  sits at the bottom-right of the Preview and below the Capture Area
  window, where it never appears in the shared output. Slide pages
  can also be changed with the keyboard: Right/Down/PageDown/Space
  for next, Left/Up/PageUp for previous. Picking a new file replaces
  the file list; closing a file empties it. Picking a PDF from
  Sources closes the active preset first; clearing a preset whose
  source is a file closes the file too.
- **Capture Area (Output)**: the window you share in Zoom, Meet, or
  Teams ("Veil Output — share this window"). Its size and ratio always
  match the Preview at the same width, and it grows downward when a
  source window reaches under the Dock. Open and close it with the
  Capture Area button in the panel header.
- **Preview**: embedded above the panel in the same window (no
  separate Preview window), draggable with the panel, with the same
  content and ratio as the Capture Area. It shows the file controller
  pill and the camera toggle; it is never shared.
- **Panic**: the Panic button and the `Cmd+Shift+P` shortcut blank the
  output instantly (plain black) and stop capture. While Panic is on,
  the Preview shows an eye-slash message and the Panic box reads Play
  / Output Off. Turning Panic off resumes the stream.
- **Always-on streaming**: there is no Start or Stop button. The
  stream starts automatically on launch (restoring your last session),
  and selecting a source, a preset, a display, or a canvas mode
  starts or updates it. Deselecting all sources does not stop the
  stream.
- **Always on Top**: the control window floats by default, while the
  Capture Area window stays normal so it does not cover other work.
- **Stage Manager**: when Stage Manager is on, opening Veil moves
  other apps to Stage Manager, except the apps of your selected
  sources.
- **Session restore**: Veil remembers your last setup (mode, framing,
  canvas, display, windows, camera, preset) and restores it on the
  next launch, then starts sharing automatically.

## Download

Download the latest release from the
[Releases page](https://github.com/aidilaryanto/veil/releases):
get the latest Veil DMG file, open it, and drag `Veil.app` into
Applications.

## "Veil is damaged and can't be opened"

If macOS refuses to open the app with "Veil is damaged and can't be
opened" or ""Veil" can't be opened because Apple cannot check it for
malicious software", do not delete it. This happens because the
GitHub Actions build is ad-hoc signed, not Developer ID signed and
notarized. Fix it with one of these:

**Option 1 — Terminal (fastest):**

1. Open Terminal.
2. Run:

   `xattr -dr com.apple.quarantine /Applications/Veil.app`

   (If Veil.app is somewhere else, use that path instead.)
3. Double-click Veil.app. It should now open normally.

**Option 2 — System Settings:**

1. Click Done on the error dialog.
2. Open System Settings > Privacy & Security.
3. Scroll down to the Veil message and click Open Anyway, then Open
   in the confirmation dialog.

Notes:

- On macOS Sequoia and later, right-click > Open does not bypass
  this check. Use one of the options above.
- You only need to do this once per downloaded build.
- A build made directly on your Mac (via Xcode or `swift build`)
  does not need any of this.

## How to build with Xcode

1. Open this project folder in Xcode, or run from Terminal:
   `swift build -c release`
2. Allow Screen Recording and Camera when the app first asks for them
   (System Settings > Privacy & Security).
3. The stream starts automatically. Choose windows in the Sources
   popup, then share the Capture Area window in Zoom/Meet/Teams.

## How to build with GitHub Actions

Every push to the `main` branch (or a manual trigger) runs the workflow
`.github/workflows/build-macos.yml`: it builds in release mode, wraps
the binary as `Veil.app` (bundle id `com.veil.app`, with the Veil icon
generated from `Assets/veil-icon.png`), signs it ad-hoc, then uploads
an artifact named `Veil-macOS`. Download that artifact from the Actions
tab of the repository and extract it.

## How to use

1. Choose windows in the Sources popup (or a PDF/PPT file).
2. Adjust Display, Framing, Canvas, and Camera if needed, or apply
   a preset.
3. Open the Capture Area with the Capture Area button in the header
   (the stream is already running).
4. In Zoom/Meet/Teams, choose Share Screen > Window > "Veil Output —
   share this window", not the whole display.
5. To hide the output instantly, press Panic (`Cmd+Shift+P`).
   Press Panic again (or the Play box) to resume.
6. For a PDF, change slides from the file controller pill, or with
   the keyboard: Right/Down/PageDown/Space for next,
   Left/Up/PageUp for previous.

## What is deliberately not included

- **No license system**: the app is free, with no license validation,
  keys, activation, or paid preset limits.
- **No virtual camera / DriverKit**: there is no virtual camera.
  What is shared is a regular Capture Area window.
- **No copied assets or branding from a reference app**: the name,
  icon, assets, and wording of other apps are not used here.
  Only the functional idea is reimplemented, with original code.
- **PPT is first-slide preview only**: macOS has no built-in
  per-slide renderer for PPT/PPTX, so what is shown is the QuickLook
  thumbnail. For full slide navigation, convert the PPT to PDF first,
  then add the PDF as a file source.
