<p align="center">
  <img src="docs/icon.png" width="128" alt="ServiceBook app icon">
</p>

# ServiceBook — vehicle maintenance tracker for iOS

[![Build](https://github.com/deborahdore/ServiceBook/actions/workflows/build.yml/badge.svg)](https://github.com/deborahdore/ServiceBook/actions/workflows/build.yml)

ServiceBook is a free, open-source iPhone/iPad app that turns your vehicle's **owner's manual** into a live maintenance checklist. Add a car or motorcycle and the app builds the full list of checks from the manufacturer's schedule: intervals in **km and months** ("whichever comes first"), specifications, and the important notes from the manual. It then tells you what is overdue, what is due soon, and what comes next.

## Features

- **Vehicles**: cars, motorcycles, scooters, vans. Make, model, year, engine, plate, VIN and first registration.
- **Maintenance schedule from the manual**
  - **Built-in schedules** researched from manufacturer documents (see [Built-in schedules](#built-in-schedules)).
  - **Find the manual online (AI)**: Claude searches the web for the official owner's manual or maintenance chart of *your* vehicle, reads it, and converts every item into the checklist.
  - **Import a manual PDF (AI)**: pick the manual PDF and the app extracts the maintenance pages for Claude to convert. Scanned PDFs work too, up to 100 pages.
  - You always **review** the extracted items before they are added. Every item can be edited, hidden or deleted, and you can add your own.
- **Due tracking**: each item is shown as *Overdue*, *Due soon* or *Upcoming*, with "due at 24,000 km · in 3,200 km" or "due on 12 Mar 2027 · in 4 months" and a progress bar. Run-in services and other one-time items are handled too.
- **"History unknown" mode** for used vehicles: items you have never logged are counted from today's mileage instead of showing as overdue.
- **Service log**: services, **tyre changes** (position, brand/model, size, DOT), part replacements, repairs, inspections (contrôle technique / MOT / revisione), with cost, workshop and notes. Ticking the schedule items you did restarts their intervals.
- **Receipts and documents**: attach PDFs and photos, or **scan paper receipts** with the camera. Keep the owner's manual, insurance and registration papers with the vehicle. Everything previews in-app with Quick Look and can be shared.
- **Mileage log** with history.
- **Reminders**: optional notifications for date-based items (one week before, and on the day).
- **Languages**: English, Italiano, Français, Español and Português. The app follows the iPhone's language, or pick one in **Settings → Language** (it applies right away). Built-in schedules are translated too (also on vehicles you already added), and AI imports are written in the chosen language.
- **Private by default**: all data stays on the device (SwiftData). The only network traffic is the AI import, sent to Anthropic with *your* API key.

## Requirements

- Xcode 16 or later. The project uses folder-synchronized groups, so new files dropped into `ServiceBook/` are picked up automatically.
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
| From a PDF | PDFKit extracts the text and keeps the pages about maintenance, intervals and specifications (up to about 150k characters). Image-only PDFs of 100 pages or fewer are sent as a document so Claude can read the page images. |

Under the hood:

- **Structured result.** Claude returns the schedule by calling a `submit_schedule` tool marked `strict`, so the result always matches the JSON schema: one item per component and action, kilometres, km and month intervals, specs and notes. If Claude finishes without calling the tool, the app asks once more and forces the call. If the API rejects strict mode, the app retries without it.
- **Live progress.** Responses are streamed (SSE). The import screen shows each search query, each page being read, and a counter of items as Claude writes them. You can stop at any time.
- **Long turns.** `pause_turn` responses are continued automatically, sending the server-tool blocks back unchanged.
- **Reliability.** Rate limits, overloads, 5xx errors and dropped connections are retried with backoff (3 s, 10 s, 30 s). Other errors get a plain explanation: invalid key, no credit, model not available, request too large.
- **Review first.** Nothing is saved until you have reviewed and selected the items. The review screen also shows the model used, the tokens and the searches.

Code: [`ClaudeClient.swift`](ServiceBook/Services/ClaudeClient.swift) (streaming client, Models API), [`ManualImporter.swift`](ServiceBook/Services/ManualImporter.swift) (prompts, tool schema), [`AIConnectionView.swift`](ServiceBook/Views/AIConnectionView.swift) (settings).

## Tests

`ServiceBookTests` covers the stream parser (web search, tool input, errors), the error mapping, the tool schema, decoding of AI output, the bundled schedules, and the due-date engine. CI runs them on an iPhone simulator for every push. To run them locally, press ⌘U in Xcode.

## Built-in schedules

| Vehicle | Items | Main sources |
|---|---|---|
| Kawasaki Z400 / Ninja 400 (ER400D, 2018–2025) | 38 | Kawasaki owner's manual periodic maintenance chart (via [maintenanceschedule.com](https://maintenanceschedule.com/kawasaki-z400-er400-maintenance-schedule/)) |
| Ford Fiesta Mk8 (2017–2023), diesel 1.5 TDCi | 33 | Ford service schedule sheets, [Fiesta owner's manual (2021)](https://www.fordservicecontent.com/Ford_Content/Catalog/owner_information/CG3654en-202012-20201214103157.pdf), Haynes |
| Ford Fiesta Mk8 (2017–2023), petrol | 32 | same as above |
| Ford Fiesta Mk7 (2008–2017), diesel | 33 | [Ford service schedule sheets](https://www.newtonnet.co.uk/fiesta/), [Haynes guide](https://haynes.com/en-gb/tips-tutorials/ford-fiesta-routine-maintenance-guide-2013-2017-models) |
| Ford Fiesta Mk7 (2008–2017), petrol | 32 | same as above |

Schedules are plain JSON in [`ServiceBook/Schedules`](ServiceBook/Schedules), generated by [`scripts/build_schedules.py`](scripts/build_schedules.py), which documents the source of every value. **Contributions are welcome.** Add your vehicle to the script, run `python3 scripts/build_schedules.py`, and open a pull request with your sources.

## Project structure

```
ServiceBook/
  ServiceBookApp.swift        App entry, SwiftData container
  Models/Models.swift         Vehicle, MaintenanceTask, ServiceRecord, OdometerReading, SpecNote, Attachment
  Models/DueEngine.swift      Next-due computation (km / months, whichever first)
  Schedules/                  Built-in schedule JSON + ScheduleLibrary (matching, applying)
  Services/                   Claude API client, manual importer, reminders, Keychain
  Views/                      SwiftUI screens
ServiceBookTests/              Unit tests (stream parser, AI decoding, schedules, due engine)
scripts/build_schedules.py    Source of the built-in schedules
```

## Disclaimer

Maintenance schedules depend on market, engine, model year and usage. ServiceBook is a guide: always check your owner's manual and your mechanic's advice. The authors accept no responsibility for missed or incorrect maintenance. Vehicle and brand names belong to their owners. This project is not affiliated with any manufacturer.

## License

[MIT](LICENSE)
