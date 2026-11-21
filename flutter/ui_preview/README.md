# RustDesk UI preview

A backend-free Flutter catalog for reviewing the new visual direction. It imports
the **production** `WorkspaceStyle`, `WorkspacePanel`, `WorkspaceHeading`,
`WorkspaceIcon`, and `WorkspaceSidebar` from the local `rustdesk_ui` package
(re-exported by the app's `lib/common/widgets/workspace.dart`).
The application uses those same primitives on desktop and mobile; its existing
controllers, native bridge, permission checks, and connection actions stay intact.

## Run

Use Flutter **3.24.5**, matching the repository's default CI toolchain:

```sh
cd flutter/ui_preview
flutter pub get
flutter run -d chrome --web-port 8080
# Or use the native Linux desktop renderer:
flutter create --platforms=linux --project-name=rustdesk_ui_preview .
flutter run -d linux
```

The toolbar switches between desktop/phone layouts and light/dark appearances.
Try device search, Favorites, form validation, and the Settings switches. Every
device and credential is explicitly sample data; Connect only displays a notice.
The preview never loads the Rust library and does not change real preferences.

### Desktop session and file transfer catalog

```sh
cd flutter/ui_preview
flutter run -d web-server -t lib/desktop_main.dart --web-hostname 0.0.0.0 --web-port 8081
flutter test ../test/desktop_workspace_test.dart
flutter build web -t lib/desktop_main.dart
```

This entry point shares the production session toolbar surface/menu styling,
quality-overlay frame, file-transfer panes/headings, and empty state. Its canvas,
menu contents, file rows, metrics, chat, and transfer jobs are fixtures: toolbar
collapse/docking, selection, and pause/resume/cancel only demonstrate UI states.
They do not exercise production docking persistence, input capture, file IO or
remote protocols. The catalog scrolls horizontally at narrow widths; this is a
catalog affordance, not a production window-sizing change.

## Checks

Tests live in the repository's normal Flutter test directory so CI discovers them.
The small preview package can run them without the native bridge or app plugins:

```sh
cd flutter/ui_preview
flutter test ../test/workspace_ui_test.dart
flutter analyze lib
flutter build web
```

## Verification boundary

This is a design/component preview, **not** an end-to-end RustDesk session or a
pixel-exact rendering of every existing page. Full app builds still require the
project's generated Flutter/Rust bridge and native libraries. Native macOS,
Windows, and iOS builds, and the SwiftUI iOS overlay, must be checked on their
respective platforms before release. The preview's connection form and sample
device/settings content are catalog fixtures, not replacements for those app
implementations.
