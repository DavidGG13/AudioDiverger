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
3. un IOProc real-time copiază sunetul din tap pe dispozitivul ales, cu volum separat pentru fiecare aplicație.

Aplicațiile fără setare redau în continuare pe ieșirea implicită a sistemului.

## Cerințe

- macOS **14.2** sau mai nou
- Xcode sau Command Line Tools (Swift 6), doar pentru compilare

## Instalare

```bash
git clone https://github.com/DavidGG13/AudioDiverger.git
cd AudioDiverger
./scripts/build_app.sh --install     # compilează și copiază în /Applications
```

Fără `--install`, aplicația ajunge în `build/AudioDiverger.app`.

## Utilizare

1. Deschide **AudioDiverger**. Apare o fereastră și o iconiță în bara de meniu.
2. Pornește redarea în aplicațiile dorite. Apar în listă (cele care redau acum sunt marcate cu punct verde).
3. Alege din meniul de lângă fiecare aplicație dispozitivul pe care vrei să o auzi.
4. La prima rutare, macOS cere permisiunea de **înregistrare audio a sistemului**. Acceptă.

Alegerile se salvează pentru fiecare aplicație (după bundle ID) și se aplică automat data viitoare, sau când reconectezi dispozitivul.

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
  AudioDivergerApp.swift   # app entry: fereastră + meniu în bara de sus
  Views.swift              # UI SwiftUI
  AudioModel.swift         # stare, persistență, sincronizare rute
  AppRoute.swift           # tap + aggregate device + IOProc (motorul audio)
  AudioApp.swift           # enumerare procese audio, grupare pe aplicații
  OutputDevice.swift       # enumerare dispozitive de ieșire
  CoreAudioHelpers.swift   # wrappers Core Audio
Resources/                 # Info.plist, AppIcon.icns
scripts/                   # build_app.sh, make_icon.swift
```

## Licență

MIT © EAZYIT
