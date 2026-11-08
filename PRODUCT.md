# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos (native SwiftUI menu bar app; not one of web/ios/android/adaptive)

## Users

Video editors and content creators on a Mac who run several audio apps at once. The core scene: editing in DaVinci Resolve with headphones on, while a browser, music player or call plays on the laptop speakers (or the other way round). The primary user is the author (EasyInfoTech). The app is also published for other creators.

## Product Purpose

Route each app's audio to the output device the user picks, per app, without virtual drivers. Success means the user sets it once, forgets it's there, and every app keeps coming out of the right device, even after replugging headphones or restarting.

## Positioning

Uses Apple's native Core Audio process taps (macOS 14.2+). There is nothing to install: no kernel extension, no virtual driver. It is free and open source (MIT).

## Operating Context

- Lives in the menu bar as a background utility. There is no Dock icon. An optional larger window opens from the menu.
- Opened briefly to change a route, then closed for hours.
- Must use as few resources as possible when idle. The design is event-driven, with no polling, and live meters run only while the UI is visible.

## Capabilities and Constraints

- Per-app output to one or more devices at the same time.
- Per-app volume and mute.
- Live per-app level meter, shown only while the UI is visible.
- Presets ("scenes") that switch every route at once, with global keyboard shortcuts.
- Remembers assignments by bundle ID and re-applies them automatically when an app starts or a device reconnects.
- Requires the System Audio Recording permission.
- Signed ad-hoc only. Releases ship as an unsigned .dmg built by GitHub Actions, with no Apple Developer account.
- UI language: English (for a worldwide audience).

## Brand Commitments

- Name: AudioDiverger, by EasyInfoTech.
- Icon motif: a branching arrow (`arrow.triangle.branch`) on a violet-to-cyan gradient (Resources/AppIcon.icns).

## Evidence on Hand

There are no testimonials, user counts or benchmarks. None should be invented.

## Product Principles

1. Invisible when idle: zero work and zero UI noise unless something is being routed or the menu is open.
2. One glance, one click: every app's destination is readable at a glance and changeable in one interaction.
3. Never lose sound silently: if a device disappears, fall back to the system default and say so.
4. Native first: behave like a macOS system utility (Control Center, Sound settings), not a web app in a box.

## Accessibility & Inclusion

Standard macOS expectations: VoiceOver labels on every control, keyboard operability, Dynamic Type isn't a macOS concept but text must respect system font sizing, and color must never be the only status signal.
