# ChatGPT5 ADT Simulator — Qt 6 (QML) Visual Studio project (UI-first port)

This is a **UI-first** Qt 6 / QML port of your React app. It keeps the *conceptual* structure (Specs → Diagnostics → Column View + Material Balance, with Run Log on the right) and exposes the same kind of state through a C++ `AppState` object.

## What’s included

- Qt Quick UI recreating the layout and feel:
  - Specs panel (crude selection, feed inputs, condenser/reboiler type + 5 spec inputs on one line)
  - Solver diagnostics (scrollable, ~3 lines tall)
  - Column view with per-tray V/L bar and **equal spacing** for the meta fields
  - Material Balance card
  - Run log panel
- C++ models (so you can later wire in the real solver):
  - `TrayModel` (32 rows by default)
  - `DiagnosticsModel`
  - `RunLogModel`
  - `MaterialBalanceModel`
- A stub `solve()` in `AppState` that generates plausible demo data so you can confirm the UI...

## Open in Visual Studio (Qt Visual Studio Tools)

1. Install Qt 6.x (Desktop, MSVC kit)
2. Install **Qt Visual Studio Tools** extension
3. Open folder in Visual Studio (CMake)
4. Configure with the Qt toolchain (MSVC)
5. Build & run

## Where to start wiring the real solver

- `cpp/AppState::solve()` is the current hook.
- Replace the stub with:
  - your thermo + column solver translated into C++
  - or a first step: keep solver in JS and call it via `QJSEngine` while gradually moving code

## Files you’ll mostly edit

- QML:
  - `qml/Main.qml`
  - `qml/components/SpecsPanel.qml`
  - `qml/components/DiagnosticsPanel.qml`
  - `qml/components/ColumnView.qml`
  - `qml/components/MaterialBalanceView.qml`
  - `qml/components/RunLogView.qml`
- C++:
  - `cpp/AppState.*`
  - `cpp/models/*`
