---
version: 1
slug: "sources-audiodiverger-views-swift"
primary_target: "Sources/AudioDiverger/Views.swift"
related_targets: []
---

# Surface: menu bar popover + optional window

Mode: operate. Audience: video editors routing per-app audio while editing. Task: glance which app plays where; change destination, mute, or scene in one click. Frequent-glance, rare-change. Constraint: zero cost when hidden.

## Direction contract

seed: 2f4a544e021e6ad7e56cc6157312d8b9 (assigned index 6; challengers declined: web-native worlds cannot carry a native menu bar utility)

THESIS: Every app is a track in an editor's timeline: a header with name, M button and destination patch, its level running along the track. Refuses the Control Center list of dropdowns.

OWN-WORLD: Native macOS materials and system type. Each output device owns a stable colour drawn from the icon gradient family (violet, cyan, then amber, green, pink). That colour appears on its chip dot and in the track's meter fill, and nowhere else. Neutral rows sit on the popover material. Square M button like a track mute. Tabular numerals.

STORY: Open the popover and read the destinations immediately: colour equals device. Live meters show which track is sounding right now.

FIRST VIEWPORT: Scene chips across the top (with ⌃⌥⌘ number hints). Active tracks with live meters. Inactive tracks folded into a disclosure. A footer showing the system default device.

SIGNATURE INTERACTION: Clicking a destination chip opens a checklist of devices. Ticking a second device splits the track into two coloured chips, and the meter shows both colours.

RISK: Device colours must never be the only signal; chips always carry the device name.
