<p align="center">
  <img src="docs/icon.png" width="128" alt="ServiceBook app icon">
</p>

# ServiceBook — vehicle maintenance tracker for iOS

[![Build](https://github.com/deborahdore/ServiceBook/actions/workflows/build.yml/badge.svg)](https://github.com/deborahdore/ServiceBook/actions/workflows/build.yml)

ServiceBook is a free, open-source iPhone/iPad app that turns your vehicle's **owner's manual** into a live maintenance checklist. Add a car or motorcycle and the app builds the full list of checks from the manufacturer's schedule: intervals in **km and months** ("whichever comes first"), specifications, and the important notes from the manual. It then tells you what is overdue, what is due soon, and what comes next.

## Features

- **Vehicles**: cars, motorcycles, scooters, vans. Make, model, year, engine, plate, VIN and first registration.
- **Maintenance schedule from the manual**
  - **Schedule library**: 92 ready-made schedules researched from manufacturer documents, kept in this repository and downloaded only when you pick one (see [Schedule library](#schedule-library)). Model schedules cover the best sellers; a brand-wide plan covers every other model of the brand.
  - **Find the manual online (AI)**: Claude searches the web for the official owner's manual or maintenance chart of *your* vehicle, reads it, and converts every item into the checklist.
  - **Upload the manual or service booklet (AI)**: a PDF, photos of the pages or a camera scan. The app picks the maintenance pages and either Claude converts them (scanned PDFs up to 100 pages), or they are **read on the iPhone** — free, offline, nothing leaves the device — by Apple Intelligence (iOS 26, Apple Intelligence iPhone) or by a free open model downloaded once (Qwen, Llama or LFM2 with Apple's MLX: any recent iPhone, any country).
  - You always **review** the extracted items before they are added. Every item can be edited, hidden or deleted, and you can add your own.
- **Due tracking**: each item is shown as *Overdue*, *Due soon* or *Upcoming*, with "due at 24,000 km · in 3,200 km" or "due on 12 Mar 2027 · in 4 months" and a progress bar. Run-in services and other one-time items are handled too.
- **"History unknown" mode** for used vehicles: items you have never logged are counted from today's mileage instead of showing as overdue.
- **Service log**: services, **tyre changes** (position, brand/model, size, DOT), part replacements, repairs, inspections (contrôle technique / MOT / revisione), with cost, workshop and notes. Ticking the schedule items you did restarts their intervals.
- **Receipts and documents**: attach PDFs and photos, or **scan paper receipts** with the camera. Keep the owner's manual, insurance and registration papers with the vehicle. Everything previews in-app with Quick Look and can be shared.
- **Mileage log** with history.
- **Reminders**: optional notifications for date-based items (one week before, and on the day).
- **Widget** for the Home Screen (small, medium, large) and the Lock Screen: what is overdue and due soon for a vehicle you pick, or for the one that needs attention most. It updates every time you leave the app and turns date-based items due by itself, day after day.
- **Languages**: English, Italiano, Français, Español and Português. The app follows the iPhone's language, or pick one in **Settings → Language** (it applies right away). Library schedules are translated too (also on vehicles you already added), and AI imports are written in the chosen language.
- **Private by default**: all data stays on the device (SwiftData). The only network traffic is the schedule library (read from GitHub, nothing is sent), the Claude import, sent to Anthropic with *your* API key, and the one-time download of the open model from Hugging Face; reading on the iPhone sends nothing.

## Requirements

- Xcode 26.4 or later (Swift 6.3, required by the MLX packages). The project uses folder-synchronized groups, so new files dropped into `ServiceBook/` are picked up automatically.
- Swift packages (resolved by Xcode on first open): [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), [swift-transformers](https://github.com/huggingface/swift-transformers), [swift-huggingface](https://github.com/huggingface/swift-huggingface).
- iOS / iPadOS 17 or later.
- Optional, for AI import: a Claude API key from [console.anthropic.com](https://console.anthropic.com/settings/keys).

## Build and run

```bash
git clone https://github.com/deborahdore/ServiceBook.git
cd ServiceBook
open ServiceBook.xcodeproj
```

1. Select the **ServiceBook** target, open *Signing & Capabilities* and choose your team. A free Apple ID works for running on your own device.
2. If Xcode complains that the bundle identifier is taken, change it (for example `com.yourname.ServiceBook`).
   Do the same for the **ServiceBookWidget** target (keep it as `<app id>.Widget`), and change the App Group `group.io.github.deborahdore.ServiceBook` in both targets' *Signing & Capabilities* and in `Shared/WidgetSnapshot.swift`: the app and the widget share data through it.
3. Run it on a simulator or your iPhone.

## Setting up the Claude connection

AI import is optional and uses your own Anthropic account: you pay Anthropic directly, typically a few cents per import.

1. Create an API key at [console.anthropic.com](https://console.anthropic.com/settings/keys). You can also set a monthly spending limit there.
2. In the app, go to **Settings → Claude connection**, tap **Paste**, then **Save & test**. The app calls the Models API to check the key and to load the models your key can use.
3. Pick a model. **Sonnet** is the default and the best balance of accuracy and cost, **Opus** is the most thorough for hard-to-find manuals, and **Haiku** is the cheapest. Models that can't search the web are flagged.
4. Optional: change the maximum number of web searches per import (3–15), or turn off "Prefer my country's schedule". Intervals often differ between markets.

The key is stored in the iOS Keychain on this device only. It is never synced to iCloud and is sent only to `api.anthropic.com`. The same screen shows how many tokens, searches and pages your imports have used on this device.

## How the AI import works

| Mode | What happens |
|---|---|
| Find online | The app streams a Claude Messages API request with the server-side `web_search` and `web_fetch` tools. Your country is passed as the search location when enabled. Claude finds the official manual or maintenance chart for the exact make, model, year and engine, reads it, and submits the schedule. Links to manual PDFs it found can be saved to the vehicle's documents with one tap. |
| Upload, read by Claude | Photos and scans are combined into a PDF. PDFKit extracts the text and keeps the pages about maintenance, intervals and specifications (up to about 150k characters). Image-only PDFs of 100 pages or fewer are sent as a document so Claude can read the page images. |
| Upload, read by Apple Intelligence | Uses Apple's on-device model ([Foundation Models](https://developer.apple.com/documentation/foundationmodels), iOS 26+, Apple Intelligence on). Pages without a text layer are read with Vision OCR, keeping table rows on one line. The model has a 4096-token window, so the maintenance pages (all of them for a short upload, the best-scoring ~30 for a full manual) are read in chunks of about 3,000 characters, each in a new session with guided generation (`@Generable`); chunks that overflow are split in half. Items found on several pages are merged. Free and offline, but less accurate than Claude on large tables: review the result carefully. Code: [`OnDeviceReader.swift`](ServiceBook/Services/OnDeviceReader.swift). |
| Upload, read by the open model | For iPhones without Apple Intelligence. In **Settings → On-device model** you pick and download one model from Hugging Face once: Qwen3 0.6B (350 MB, older iPhones), LFM2 1.2B (660 MB), Llama 3.2 1B (710 MB), Qwen3 1.7B (about 1 GB, most iPhones), Qwen3.5 2B (1.75 GB, 6 GB iPhones) or Qwen3 4B (about 2.3 GB, 8 GB iPhones); it is stored in Application Support, outside iCloud backups, and can be deleted. It runs with [MLX Swift](https://github.com/ml-explore/mlx-swift-lm). Same page selection and OCR as above, but with chunks of about 6,000 characters; the model answers in the `submit_schedule` JSON shape (thinking off, greedy decoding) and the reply goes through the same tolerant parser as Claude's. Code: [`LocalModel.swift`](ServiceBook/Services/LocalModel.swift). |

Under the hood:

- **Structured result.** Claude returns the schedule by calling a `submit_schedule` tool marked `strict`, so the result always matches the JSON schema: one item per component and action, kilometres, km and month intervals, specs and notes. If Claude finishes without calling the tool, the app asks once more and forces the call. If the API rejects strict mode, the app retries without it.
- **Live progress.** Responses are streamed (SSE). The import screen shows each search query, each page being read, and a counter of items as Claude writes them. You can stop at any time.
- **Long turns.** `pause_turn` responses are continued automatically, sending the server-tool blocks back unchanged.
- **Reliability.** Rate limits, overloads, 5xx errors and dropped connections are retried with backoff (3 s, 10 s, 30 s). Other errors get a plain explanation: invalid key, no credit, model not available, request too large.
- **Review first.** Nothing is saved until you have reviewed and selected the items. The review screen also shows the model used, the tokens and the searches.

Code: [`ClaudeClient.swift`](ServiceBook/Services/ClaudeClient.swift) (streaming client, Models API), [`ManualImporter.swift`](ServiceBook/Services/ManualImporter.swift) (prompts, tool schema), [`AIConnectionView.swift`](ServiceBook/Views/AIConnectionView.swift) (settings).

## Tests

`ServiceBookTests` covers the stream parser (web search, tool input, errors), the error mapping, the tool schema, decoding of AI output, the schedule catalog (every file decodes, matches the index and is translated into every language), vehicle matching, and the due-date engine. CI runs them on an iPhone simulator for every push. To run them locally, press ⌘U in Xcode.

## Schedule library

The schedules live in [`catalog/`](catalog), not in the app. The app downloads the small `catalog/index.json` to list and match schedules, and a schedule file only when you choose it; both are cached, so they keep working offline. New schedules reach every user as soon as they are pushed to `main`, with no app update.

| Brand | Model schedules | Brand-wide plan |
|---|---|---|
| Honda (motorcycles) | XL750 Transalp, CRF1100L Africa Twin, NC750X, CB750 Hornet, CB650R / CBR650R, CB500X / NX500 / CB500F / CBR500R | ✓ |
| Yamaha | MT-07 (and XSR700, Tracer 7, R7), MT-09 / Tracer 9 / XSR900, Ténéré 700 | ✓ |
| BMW Motorrad | R 1300 GS, R 1250 GS, F 900 GS, F 750 / 850 GS | ✓ |
| Kawasaki | Z400 / Ninja 400, Z900, Z650 / Ninja 650, Versys 650 | ✓ |
| Suzuki | V-Strom 650, V-Strom 800 / GSX-8S / GSX-8R, GSX-S1000 | ✓ |
| KTM | 390 Duke / Adventure (2013–2023 and 2024+), 790 / 890 Duke & Adventure, 1290 Super Adventure | ✓ |
| Triumph | Trident 660, Speed / Scrambler 400, Tiger 900, Street Triple 765 | ✓ |
| Ducati | Multistrada V4, Monster 937, Scrambler 800 | ✓ |
| Volkswagen | Golf 8, Polo 6, T-Roc, Tiguan (petrol and diesel) | petrol, diesel |
| Škoda | Octavia IV, Fabia IV | petrol, diesel |
| Ford | Fiesta Mk7 / Mk8, Puma, Focus Mk4 | petrol, diesel |
| BMW | 3 Series G20 / G21 | petrol, diesel |
| Renault | Clio V (petrol and E-Tech), Captur II | petrol, diesel |
| Dacia | Sandero III, Duster | petrol, diesel |
| Peugeot | 208 II (petrol and diesel), 2008 II | petrol, diesel |
| Citroën | C3 III | petrol, diesel |
| Opel / Vauxhall | Corsa F | petrol, diesel |
| Toyota | Yaris (XP21), Yaris Cross | hybrid / petrol |
| Fiat | Panda, 500 | petrol |

Model schedules rank above the brand-wide plan, which matches any model of the make. Every schedule lists its sources: owner's manual maintenance charts (as transcribed by [maintenanceschedule.com](https://maintenanceschedule.com/)) for motorcycles, [Haynes maintenance plans](https://uk.haynes.com/pages/maintenance-plans-car-volkswagen) and manufacturer service sheets for cars. Where only a secondary source was available, the item's note says so.

The files are generated by [`scripts/build_catalog.py`](scripts/build_catalog.py), with translations in [`scripts/catalog_i18n.py`](scripts/catalog_i18n.py). Each file carries its own Italian, French, Spanish and Portuguese text; the script stops and lists any text that has no translation. **Contributions are welcome**: add your vehicle to the script, run `python3 scripts/build_catalog.py`, and open a pull request with your sources.

## Project structure

```
ServiceBook/
  ServiceBookApp.swift        App entry, SwiftData container
  Models/Models.swift         Vehicle, MaintenanceTask, ServiceRecord, OdometerReading, SpecNote, Attachment
  Models/DueEngine.swift      Next-due computation (km / months, whichever first)
  Schedules/                  ScheduleLibrary (catalog download, cache, matching, applying)
  Services/                   Claude API client, manual importer, reminders, Keychain
  Views/                      SwiftUI screens
ServiceBookTests/              Unit tests (stream parser, AI decoding, schedules, due engine)
catalog/                      Schedule library: index.json + schedules/*.json (downloaded by the app)
scripts/build_catalog.py      Source of the schedule library (catalog_i18n.py: translations)
```

## Disclaimer

Maintenance schedules depend on market, engine, model year and usage. ServiceBook is a guide: always check your owner's manual and your mechanic's advice. The authors accept no responsibility for missed or incorrect maintenance. Vehicle and brand names belong to their owners. This project is not affiliated with any manufacturer.

## License

[MIT](LICENSE)
