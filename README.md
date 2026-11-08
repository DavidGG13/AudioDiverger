# AudioDiverger

Trimite audio-ul fiecărei aplicații pe alt dispozitiv de ieșire, pe macOS.
De exemplu: **DaVinci Resolve în căști** și **browser-ul pe difuzoarele laptopului**, în același timp.

*Per-app audio output routing for macOS: send each app's sound to a different output device. No virtual drivers required.*

---

## Cum funcționează

AudioDiverger folosește **Core Audio Process Taps**, API-ul nativ Apple din macOS 14.2. Nu instalează niciun driver virtual (BlackHole, Loopback etc.).

Pentru fiecare aplicație căreia îi alegi un dispozitiv:

1. se creează un **process tap** care preia sunetul aplicației și îl oprește pe ieșirea ei inițială;
2. se creează un **aggregate device** privat format din tap și dispozitivul ales;
3. un IOProc real-time copiază sunetul din tap pe dispozitivul ales (sau pe mai multe deodată), cu volum separat pentru fiecare aplicație.

Mute-ul fără rutare folosește doar un tap „muted”, fără niciun IO.

Aplicațiile fără setare redau în continuare pe ieșirea implicită a sistemului.

## Funcții

- **Destinație per aplicație.** Fiecare aplicație apare ca un „track”, ca în timeline-ul DaVinci. Alegi unde se aude.
- **Mai multe dispozitive simultan.** Bifezi, de exemplu, căștile *și* difuzoarele.
- **Mute (M) și volum** separat pentru fiecare aplicație.
- **Meter live** pe fiecare track, în culoarea dispozitivului. Rulează doar cât meniul e deschis.
- **Scene (preseturi).** Salvezi toate rutele, de exemplu „Editare” sau „Call”, și le schimbi dintr-un click sau cu **⌃⌥⌘1 … ⌃⌥⌘9**, de oriunde.
- **Rulează în background.** Stă doar în bara de meniu, fără iconiță în Dock. E bazată complet pe evenimente, fără polling, deci ~0% CPU când nu rutează nimic.
- Alegerile se țin minte per aplicație și se reaplică automat, inclusiv când reconectezi căștile.

## Cerințe

- macOS **14.2** sau mai nou

## Instalare

### Descarcă

Ia `.dmg`-ul din [Releases](https://github.com/DavidGG13/AudioDiverger/releases/latest) și trage AudioDiverger în Applications.
Aplicația nu e notarizată de Apple, deci la prima deschidere: **click dreapta → Open → Open**.

### Din sursă (Xcode sau Command Line Tools)

```bash
git clone https://github.com/DavidGG13/AudioDiverger.git
cd AudioDiverger
./scripts/build_app.sh --install     # compilează și copiază în /Applications
```

Ai și `--universal` pentru Apple silicon + Intel. `./scripts/make_dmg.sh` face `.dmg`-ul.
Un tag `v*` urcat pe GitHub pornește automat build-ul și publică release-ul (`.github/workflows/release.yml`).

## Utilizare

1. Deschide **AudioDiverger**. Apare iconița în bara de meniu.
2. Pornește redarea în aplicațiile dorite. Apar ca track-uri, iar cele care nu redau stau la „Inactive”.
3. Apasă pe destinația unui track și bifează unul sau mai multe dispozitive. Tot de acolo setezi volumul.
4. La prima rutare, macOS cere permisiunea de **înregistrare audio a sistemului**. Acceptă.
5. Apasă **+** sus ca să salvezi rutele ca scenă. Click dreapta pe o scenă ca să o actualizezi sau ștergi.

### Exemplu: DaVinci în căști, browserul pe difuzoare

- Ieșirea implicită a sistemului: **MacBook Speakers**
- DaVinci Resolve → **căștile tale**
- Browserul rămâne pe **Implicit**

## Permisiuni

Dacă nu se aude nimic după rutare, verifică **System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only** și activează AudioDiverger.

> Aplicația e semnată ad-hoc. După o recompilare, macOS poate cere din nou permisiunea.

## Limitări cunoscute

- **Căști Bluetooth cu microfon (AirPods etc.):** aplicația dezactivează stream-urile de microfon ale dispozitivului ca să rămână în modul de calitate înaltă (A2DP), dar unele modele pot trece totuși în modul „headset”.
- **Latență:** rutarea adaugă o latență mică (câteva ms) față de redarea directă.
- **Canale:** sunetul se trimite stereo pe primele două canale ale dispozitivului.
- Dacă dispozitivul ales se deconectează, aplicația revine automat pe ieșirea implicită. Ruta se reface când dispozitivul revine.

## Structură

```
Sources/AudioDiverger/
  AudioDivergerApp.swift   # app entry: meniu în bara de sus + fereastră opțională
  Views.swift              # UI SwiftUI
  AudioModel.swift         # stare, persistență, sincronizare rute
  AppRoute.swift           # tap + aggregate device + IOProc (motorul audio, meter)
  HotKeys.swift            # scurtături globale pentru scene
  Snapshot.swift           # randare offscreen a UI-ului (dezvoltare)
  AudioApp.swift           # enumerare procese audio, grupare pe aplicații
  OutputDevice.swift       # enumerare dispozitive de ieșire
  CoreAudioHelpers.swift   # wrappers Core Audio
Resources/                 # Info.plist, AppIcon.icns
scripts/                   # build_app.sh, make_icon.swift
```

## Licență

MIT © EAZYIT
