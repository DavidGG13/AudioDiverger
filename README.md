<div align="center">

<img src="docs/icon.png" width="112" alt="AudioDiverger icon">

# AudioDiverger

**Fiecare aplicație, pe difuzorul ei.**
DaVinci în căști, browserul pe difuzoarele laptopului, totul în același timp.

[![Download](https://img.shields.io/github/v/release/DavidGG13/AudioDiverger?label=Descarc%C4%83&color=7c5cfa)](https://github.com/DavidGG13/AudioDiverger/releases/latest)
![macOS 14.2+](https://img.shields.io/badge/macOS-14.2%2B-1ab8f2)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
[![License: MIT](https://img.shields.io/badge/licen%C8%9B%C4%83-MIT-lightgrey)](LICENSE)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img src="docs/screenshot-light.png" width="400" alt="AudioDiverger: fiecare aplicație e un track, cu destinația ei, buton de mute și meter live">
</picture>

</div>

---

macOS trimite tot sunetul pe o singură ieșire. Când editezi în DaVinci Resolve cu căștile pe urechi și vrei ca un tutorial, muzica sau un call să se audă pe difuzoarele laptopului (sau invers), nu ai de ales.

**AudioDiverger** îți lasă să alegi, pentru fiecare aplicație, unde se aude. Stă discret în bara de meniu și nu instalează niciun driver.

## Ce face

- 🎧 **Destinație per aplicație.** Fiecare aplicație e un *track*, ca în timeline-ul DaVinci. Alegi căștile, difuzoarele, placa de sunet sau orice alt dispozitiv.
- 🔀 **Mai multe ieșiri deodată.** Aceeași aplicație poate suna simultan în căști *și* pe difuzoare.
- 🔇 **Mute și volum** separat pentru fiecare aplicație.
- 📈 **Meter live** pe fiecare track, în culoarea dispozitivului pe care sună.
- 🎬 **Scene.** Salvezi setup-uri precum „Editare” sau „Call” și le schimbi dintr-un click sau cu **⌃⌥⌘1 … ⌃⌥⌘9**, din orice aplicație.
- 🪶 **Aproape zero resurse.** Rulează doar în bara de meniu, fără Dock și fără polling. Când nu rutează nimic, consumul de CPU e ~0%.
- 🔌 **Își amintește tot.** Setările se reaplică automat când deschizi aplicația sau reconectezi căștile. Dacă un dispozitiv dispare, sunetul revine pe ieșirea implicită și nu se pierde.

## Instalare

1. Descarcă **`AudioDiverger-x.y.z.dmg`** din [Releases](https://github.com/DavidGG13/AudioDiverger/releases/latest).
2. Trage **AudioDiverger** în **Applications**.
3. La prima deschidere: **click dreapta → Open → Open**. Aplicația e gratuită și nu e notarizată de Apple.
4. La prima rutare, macOS îți cere permisiunea de **înregistrare audio a sistemului**. Acceptă: așa poate AudioDiverger să preia sunetul unei aplicații.

> Merge pe macOS **14.2 sau mai nou**, pe Apple silicon și Intel.

## Cum se folosește

1. Apasă pe iconița din bara de meniu.
2. Pornește redarea într-o aplicație. Apare ca track, iar aplicațiile care nu sună stau la „Inactive”.
3. Apasă pe destinația track-ului și bifează unul sau mai multe dispozitive. Tot acolo e și volumul.
4. **M** oprește sunetul aplicației.
5. **+** salvează rutele curente ca scenă. Click dreapta pe o scenă ca să o actualizezi sau să o ștergi.

**Exemplu:** ieșirea sistemului rămâne pe *MacBook Speakers*, DaVinci Resolve merge pe *căști*, iar browserul rămâne pe *Implicit*.

## Cum funcționează

AudioDiverger folosește **Core Audio Process Taps**, API-ul nativ Apple din macOS 14.2. Nu folosește kernel extensions sau drivere virtuale (de tip BlackHole sau Loopback).

Pentru fiecare aplicație rutată:

1. un **process tap** preia sunetul aplicației și îl oprește pe ieșirea ei inițială;
2. un **aggregate device** privat unește tap-ul cu dispozitivul sau dispozitivele alese;
3. un IOProc real-time copiază sunetul acolo, aplicând volumul și calculând nivelul pentru meter.

Mute-ul fără rutare e doar un tap „muted”, fără niciun IO. Meterele rulează doar cât e deschis meniul.

## Limitări cunoscute

- **Căști Bluetooth cu microfon (AirPods etc.).** AudioDiverger oprește stream-ul de microfon ca să păstreze calitatea înaltă. Unele modele pot trece totuși în modul „headset”.
- Rutarea adaugă o latență mică (câteva milisecunde).
- Sunetul merge stereo pe primele două canale ale fiecărui dispozitiv.
- Interfața e în limba română.

## Compilare din sursă

Ai nevoie de Xcode sau de Command Line Tools (Swift 6).

```bash
git clone https://github.com/DavidGG13/AudioDiverger.git
cd AudioDiverger
./scripts/build_app.sh --install      # --universal pentru Apple silicon + Intel
./scripts/make_dmg.sh                 # opțional: build/AudioDiverger-<versiune>.dmg
```

Un tag `v*` urcat pe GitHub construiește și publică automat un release ([`.github/workflows/release.yml`](.github/workflows/release.yml)).

<details>
<summary>Structura proiectului</summary>

```
Sources/AudioDiverger/
  AudioDivergerApp.swift   # meniu în bara de sus + fereastră opțională
  Views.swift              # UI SwiftUI (track-uri, scene, meter)
  AudioModel.swift         # stare, persistență, scene, sincronizarea rutelor
  AppRoute.swift           # tap + aggregate device + IOProc (motorul audio)
  AudioApp.swift           # procese audio grupate pe aplicații
  OutputDevice.swift       # dispozitive de ieșire
  HotKeys.swift            # scurtături globale pentru scene
  CoreAudioHelpers.swift   # wrappers Core Audio
  Snapshot.swift           # randare offscreen a UI-ului (dezvoltare)
```

</details>

---

<details>
<summary>🇬🇧 English</summary>

**AudioDiverger** is a tiny macOS menu bar app for **per-app audio output routing**. For example, you can hear DaVinci Resolve in your headphones while the browser plays on the laptop speakers.

- Pick an output device per app, or several at once.
- Per-app mute, volume and live level meters.
- Scenes with global hotkeys (⌃⌥⌘1…9).
- Event-driven, so it sits at ~0% CPU when idle.
- Built on Apple's **Core Audio process taps** (macOS 14.2+), with no virtual audio drivers.

Download the `.dmg` from [Releases](https://github.com/DavidGG13/AudioDiverger/releases/latest), drag it to Applications, right-click → Open on first launch, and allow *System Audio Recording* when asked. The UI is in Romanian.

</details>

<div align="center">

MIT © <a href="https://github.com/DavidGG13">EAZYIT</a>

</div>
