"""Generates the built-in maintenance schedules bundled with the app.

Run:  python3 scripts/build_schedules.py
Output: ServiceBook/Schedules/schedule-*.json

Every schedule lists its sources. Values are transcribed from the
manufacturer documents named in `source` / `sourceURLs`; where only a
secondary source was available the task notes say so.
"""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "ServiceBook", "Schedules")


def t(title, action, category, km=None, months=None, first_km=None, first_months=None,
      one_time=False, notes=None, spec=None, ref=None):
    d = {"title": title, "action": action, "category": category}
    if km: d["intervalKm"] = km
    if months: d["intervalMonths"] = months
    if first_km: d["firstKm"] = first_km
    if first_months: d["firstMonths"] = first_months
    if one_time: d["oneTime"] = True
    if notes: d["notes"] = notes
    if spec: d["spec"] = spec
    if ref: d["sourceRef"] = ref
    return d


def s(group, title, value):
    return {"group": group, "title": title, "value": value}


# ---------------------------------------------------------------- Kawasaki Z400
KAWA_REF = "Owner's manual, Periodic Maintenance Chart"
z400_annual = [
    ("Throttle control system", "inspect", "controls", "Check throttle grip play and smooth return in all steering positions."),
    ("Brake system (leaks, damage, operation)", "inspect", "brakes", None),
    ("Brake pad wear", "inspect", "brakes", "Replace pads when the friction material is worn to the wear groove (about 1 mm)."),
    ("Brake light switches", "inspect", "brakes", "Front lever and rear pedal must both switch the brake light on."),
    ("Brake fluid level", "check", "brakes", "Between LOWER and UPPER marks on both reservoirs. DOT 4 only."),
    ("Fuel system (leaks, hose damage)", "inspect", "fuel", None),
    ("Cooling system & coolant level", "inspect", "cooling", "Check level in the reserve tank with the engine cold, between F and L marks."),
    ("Clutch operation & lever play", "inspect", "controls", "Clutch lever free play 2–3 mm."),
    ("Wheels & tyres (wear, damage)", "inspect", "tyres", "Minimum tread depth: front 1 mm, rear 2 mm (up to 130 km/h) — check local law."),
    ("Wheel bearings", "inspect", "wheels", None),
    ("Front fork & rear shock (leaks, operation)", "inspect", "suspension", None),
    ("Steering play", "inspect", "steering", None),
    ("Electrical system (lights, horn, switches)", "inspect", "electrical", None),
    ("Chassis parts", "lubricate", "chassis", "Lever pivots, pedal pivots, side stand pivot, cable ends."),
    ("Nuts, bolts & fasteners tightness", "inspect", "chassis", None),
]

z400 = {
    "id": "kawasaki-z400-2019",
    "make": "Kawasaki",
    "model": "Z400",
    "aliases": ["z400", "z 400", "z400 abs", "er400", "er400d", "ninja 400", "ninja400", "ex400"],
    "generation": "ER400D (2019–2025) — also applies to Ninja 400",
    "yearFrom": 2018,
    "yearTo": 2025,
    "kind": "motorcycle",
    "fuel": "petrol",
    "source": "Kawasaki Z400 owner's manual — Periodic Maintenance Chart (intervals as transcribed by maintenanceschedule.com)",
    "sourceURLs": [
        "https://maintenanceschedule.com/kawasaki-z400-er400-maintenance-schedule/",
        "https://www.kawasaki.com/en-us/owner-center/service-manuals",
    ],
    "disclaimer": "Intervals are 'whichever comes first'. Ride in rain, dust or heavy traffic? Service more often. Always confirm with the manual for your exact bike.",
    "tasks": [
        t("Initial (run-in) service", "service", "service", first_km=1000, first_months=1, one_time=True,
          notes="Engine oil + filter change, idle speed, and all periodic inspection items. Ride gently and keep revs below 4,000 rpm for the first 800 km, below 6,000 rpm up to 1,600 km.",
          ref=KAWA_REF),
        t("Engine oil", "replace", "oil", km=12000, months=12,
          spec="SAE 10W-40, API SG–SN + JASO MA/MA1/MA2 · approx. 2.0 L with filter · drain bolt 30 N·m",
          notes="Kawasaki also lists the initial change at 1,000 km. Check the level in the sight glass before every ride (bike upright, engine off for a few minutes).",
          ref=KAWA_REF),
        t("Oil filter", "replace", "oil", km=12000, months=12,
          spec="Kawasaki 16097-0008 (e.g. HiFlo HF303RC) · 17.5 N·m", ref=KAWA_REF),
        t("Spark plugs", "replace", "ignition", km=12000,
          spec="NGK LMAR9G · gap 0.7–0.8 mm · 13 N·m", ref=KAWA_REF),
        t("Air cleaner element", "replace", "filters", km=12000,
          notes="Replace more often when riding in rain or on dusty roads.", ref=KAWA_REF),
        t("Idle speed", "inspect", "engine", km=12000, months=12, spec="1,200–1,400 rpm (typical; see manual)", ref=KAWA_REF),
        t("Engine vacuum synchronization", "inspect", "engine", km=12000, ref=KAWA_REF),
        t("Air suction system", "inspect", "engine", km=12000, ref=KAWA_REF),
        t("Valve clearance", "inspect", "engine", km=24000, ref=KAWA_REF,
          notes="Dealer job: requires removing the cylinder head cover."),
        t("Fuel filter", "replace", "fuel", km=24000, ref=KAWA_REF),
        t("Evaporative emission system", "inspect", "fuel", km=24000,
          notes="Only on models fitted with the EVAP canister (e.g. some US markets).", ref=KAWA_REF),
        t("Fuel hoses", "replace", "fuel", months=60, ref=KAWA_REF),
        t("Coolant, radiator hoses & O-rings", "replace", "cooling", km=36000, months=36,
          spec="Permanent ethylene-glycol antifreeze for aluminium engines (silicate-free), 50 % mix",
          ref=KAWA_REF),
        t("Brake fluid (front & rear)", "replace", "brakes", km=24000, months=24, spec="DOT 4", ref=KAWA_REF),
        t("Brake hoses", "replace", "brakes", months=48, ref=KAWA_REF),
        t("Brake master cylinder & caliper rubber parts", "replace", "brakes", km=48000, months=48, ref=KAWA_REF),
        t("Rear suspension (Uni-Trak)", "lubricate", "suspension", km=24000, ref=KAWA_REF),
        t("Steering stem bearings", "lubricate", "steering", km=24000, months=24, ref=KAWA_REF),
        t("Drive chain", "lubricate", "chain", km=600,
          notes="Also after washing the bike or riding in the rain. Use chain lube for O/X-ring chains.",
          ref=KAWA_REF),
        t("Drive chain slack", "check", "chain", km=1000, spec="20–30 mm at the middle of the lower run (bike on side stand)",
          notes="After adjusting, align both adjusters and tighten the rear axle nut to 98 N·m.", ref=KAWA_REF),
        t("Drive chain & sprocket wear", "inspect", "chain", km=12000, ref=KAWA_REF),
        t("Drive chain guide wear", "inspect", "chain", km=12000, ref=KAWA_REF),
    ] + [t(name, action, cat, km=12000, months=12, notes=n, ref=KAWA_REF + " (periodic inspection)")
         for (name, action, cat, n) in z400_annual] + [
        t("Roadworthiness test (contrôle technique / MOT / revisione)", "inspect", "legal", months=36, first_months=60,
          notes="Depends on your country. France (2-wheelers): first at 5 years, then every 3 years. Italy: first at 4 years, then every 2. UK MOT: first at 3 years, then yearly. Edit this item to match your country."),
    ],
    "specs": [
        s("Fluids", "Engine oil", "SAE 10W-40 · API SG–SN · JASO MA/MA1/MA2"),
        s("Fluids", "Engine oil capacity", "≈ 2.0 L with filter change"),
        s("Fluids", "Brake fluid", "DOT 4"),
        s("Fluids", "Coolant", "Ethylene-glycol permanent antifreeze for aluminium engines, 50 % with distilled water"),
        s("Tyres", "Front tyre", "110/70R17 M/C 54H · 200 kPa (2.00 bar / 28 psi) cold"),
        s("Tyres", "Rear tyre", "150/60R17 M/C 66H · 225 kPa (2.25 bar / 32 psi) cold"),
        s("Chain", "Chain slack", "20–30 mm"),
        s("Chain", "Rear axle nut torque", "98 N·m"),
        s("Electrical", "Spark plug", "NGK LMAR9G, gap 0.7–0.8 mm, 13 N·m"),
        s("Torques", "Oil drain bolt", "30 N·m"),
        s("Torques", "Oil filter", "17.5 N·m"),
        s("Before every ride", "Daily checks",
          "Fuel level · engine oil level · tyre pressure & condition · chain slack & lube · brake lever/pedal feel and fluid level · throttle snaps back · clutch · lights, indicators, horn · steering moves freely · engine stop & side stand switches"),
    ],
}

# ---------------------------------------------------------------- Ford Fiesta
FORD_REF = "Ford service schedule (Fiesta, 1 yr / 12,500 mi sheet)"
FORD_EXT = "Ford service schedule — Extended Period Maintenance"
HAYNES = "Haynes routine maintenance guide, Fiesta Mk7 (2013–2017)"
FORD_MANUAL = "Ford Fiesta owner's manual (CG3654, 2021) — Maintenance, General information"


def ford_common():
    return [
        t("Regular service: engine oil & filter", "replace", "oil", km=20000, months=12,
          notes="Ford Europe regular service: every year or 20,000 km, whichever first. If you mostly do short trips or towing, Haynes suggests every 10,000 km / 6 months. Reset the oil change indicator afterwards.",
          ref=FORD_REF),
        t("Cabin (pollen / odour) filter", "replace", "filters", km=20000, months=12, ref=FORD_REF),
        t("Brakes: pads, discs & rear drums", "inspect", "brakes", km=20000, months=12,
          notes="More often under severe duty (city traffic, mountains, towing).", ref=FORD_REF),
        t("Brake fluid level & leaks", "check", "brakes", km=20000, months=12, ref=FORD_REF),
        t("Tyres: wear, condition & tread depth", "inspect", "tyres", km=20000, months=12,
          notes="Legal minimum in the EU: 1.6 mm. Record tread depth for each tyre.", ref=FORD_REF),
        t("Steering, suspension, ball joints & driveshaft gaiters", "inspect", "suspension", km=20000, months=12, ref=FORD_REF),
        t("Engine, transmission & underbody leaks", "inspect", "engine", km=20000, months=12, ref=FORD_REF),
        t("Pipes, hoses, wiring & exhaust", "inspect", "chassis", km=20000, months=12, ref=FORD_REF),
        t("Underbody PVC coating", "inspect", "body", km=20000, months=12, ref=FORD_REF),
        t("Coolant antifreeze concentration & fluid levels", "check", "cooling", km=20000, months=12, ref=FORD_REF),
        t("Battery (leaks, condition)", "inspect", "electrical", km=20000, months=12, ref=FORD_REF),
        t("Lights, instruments, warning lamps & horn", "check", "electrical", km=20000, months=12, ref=FORD_REF),
        t("Windscreen, wipers & washers", "check", "body", km=20000, months=12, ref=FORD_REF),
        t("Headlamp alignment", "check", "electrical", km=20000, months=12, ref=FORD_REF),
        t("Handbrake & clutch operation", "check", "controls", km=20000, months=12, ref=FORD_REF),
        t("Seat belts, buckles & stalks", "check", "safety", km=20000, months=12, ref=FORD_REF),
        t("Safety kit (warning triangle, vest, first aid kit)", "check", "safety", months=12,
          notes="Check the first aid kit expiry date. A vest and warning triangle are mandatory in France and Italy.",
          ref=FORD_REF),
        t("Tyre sealant kit expiry (if fitted)", "check", "tyres", months=12, ref=FORD_REF),
        t("Brake fluid", "replace", "brakes", months=24, spec="DOT 4 LV High Performance (WSS-M6C65-A2)", ref=FORD_EXT),
        t("Air conditioning: performance & lines", "inspect", "climate", months=36, ref=FORD_EXT),
        t("Coolant: drain, flush & refill", "replace", "cooling", months=120,
          spec="Ford Super Plus Premium (WSS-M97B44-D)",
          notes="10 years if Ford Super Plus has been used from new. Haynes recommends every 2 years if the coolant type is unknown.",
          ref=FORD_EXT),
        t("Manual transmission oil level", "check", "transmission", months=24, ref=HAYNES),
        t("Remote key battery", "replace", "electrical", months=24, ref=HAYNES),
        t("Brake hoses", "inspect", "brakes", km=60000, months=36, ref=HAYNES),
        t("Air filter (induction)", "replace", "filters", km=60000, months=36,
          notes="More often in dusty or polluted conditions.", ref=FORD_REF + " (3 yr / 37,500 mi sheet)"),
        t("Monthly owner checks", "check", "owner", months=1,
          notes="Engine oil level · coolant level · brake fluid level · pipes, hoses & reservoirs for leaks · A/C operation · parking brake · horn · wheel nut tightness.",
          ref=FORD_MANUAL),
        t("Tyre pressures & condition (when refuelling)", "check", "tyres", months=1,
          notes="Also check washer fluid. Pressures are on the label in the driver's door frame.", ref=FORD_MANUAL),
        t("Roadworthiness test (contrôle technique / MOT / revisione)", "inspect", "legal", months=24, first_months=48,
          notes="Depends on your country. France & Italy: first at 4 years, then every 2 years. UK MOT: first at 3 years, then yearly. Edit this item to match your country."),
    ]


def ford_petrol():
    return [
        t("Spark plugs", "replace", "ignition", km=60000, months=36, ref=FORD_REF + " (3 yr / 37,500 mi sheet)"),
        t("Timing belt, tensioner & idlers", "replace", "engine", km=240000, months=120,
          notes="1.0 EcoBoost (wet belt): Ford 150,000 mi / 10 years. Other engines differ — 1.25 Duratec: 160,000 km / 8 years; 1.4 / 1.6 Duratec: about 200,000 km / 10 years. Edit this item for your engine.",
          ref=FORD_EXT),
        t("Auxiliary drive belt", "replace", "engine", km=240000, months=120, ref=FORD_EXT),
        t("Valve clearances", "check", "engine", km=240000, months=120, ref=FORD_EXT),
    ]


def ford_diesel():
    return [
        t("Fuel filter: drain water", "service", "fuel", km=20000, months=12, ref=HAYNES),
        t("Fuel filter", "replace", "fuel", km=60000, months=36, ref=HAYNES),
        t("Timing belt, tensioner & water pump", "replace", "engine", km=200000, months=120,
          notes="1.5 / 1.6 TDCi: about 200,000 km / 10 years (Ford Europe figure, as reported by AD). Haynes is more cautious (≈ 90,000 km). Older 1.4 TDCi: 150,000 km / 7 years. Ask a Ford dealer to confirm with your VIN.",
          ref="ad.fr Fiesta timing-belt guide; " + HAYNES),
        t("Auxiliary drive belt", "replace", "engine", km=180000, months=120, ref=HAYNES),
        t("Diesel particulate filter & AdBlue (if fitted)", "inspect", "emissions", km=20000, months=12,
          notes="Do a regular 20+ minute motorway drive so the DPF can regenerate, especially if you mostly do short trips."),
    ]


def ford_template(tid, generation, years, fuel, aliases, specs, extra_sources, note):
    tasks = ford_common() + (ford_diesel() if fuel == "diesel" else ford_petrol())
    return {
        "id": tid,
        "make": "Ford",
        "model": "Fiesta",
        "aliases": aliases,
        "generation": generation,
        "yearFrom": years[0],
        "yearTo": years[1],
        "kind": "car",
        "fuel": fuel,
        "source": "Ford Europe service schedules (Fiesta), Ford Fiesta owner's manual, Haynes maintenance guide",
        "sourceURLs": [
            "https://www.newtonnet.co.uk/fiesta/serviceschedule-1yr12500mi.pdf",
            "https://www.newtonnet.co.uk/fiesta/serviceschedule-3yr37500mi.pdf",
            "https://haynes.com/en-gb/tips-tutorials/ford-fiesta-routine-maintenance-guide-2013-2017-models",
        ] + extra_sources,
        "disclaimer": note,
        "tasks": tasks,
        "specs": specs,
    }


ford_checks = [
    s("Owner checks", "Daily", "Exterior lamps · interior lamps · warning lamps and indicators"),
    s("Owner checks", "When refuelling", "Washer fluid · tyre pressures · tyre condition"),
    s("Owner checks", "Monthly", "Engine oil, coolant & brake fluid levels · leaks · A/C · parking brake · horn · wheel nut tightness"),
    s("Tyres", "Tyre pressures", "See the label on the driver's door B-pillar (depends on tyre size and load)"),
]

MANUAL_2021 = "https://www.fordservicecontent.com/Ford_Content/Catalog/owner_information/CG3654en-202012-20201214103157.pdf"

fiesta_mk8_diesel = ford_template(
    "ford-fiesta-mk8-diesel", "Mk8 (2017–2023) — 1.5 TDCi / EcoBlue diesel", (2017, 2023), "diesel",
    ["fiesta", "fiesta mk8", "fiesta 8", "fiesta viii", "fiesta 1.5 tdci", "fiesta 1.5 ecoblue"],
    [
        s("Fluids", "Engine oil", "SAE 0W-30 to Ford WSS-M2C950-A (top-up: max 1 L of ACEA C2 0W-30 between services)"),
        s("Fluids", "Engine oil capacity", "6.2 L incl. filter · dipstick MIN→MAX = 1.75 L (2021 manual, 1.5 Duratorq-TDCi — check your handbook for earlier builds)"),
        s("Fluids", "Coolant", "Ford Super Plus Premium WSS-M97B44-D · 6.1 L"),
        s("Fluids", "Brake fluid", "DOT 4 LV High Performance WSS-M6C65-A2"),
        s("Fluids", "Fuel tank", "40 L"),
        s("Fluids", "Washer reservoir", "3 L"),
    ] + ford_checks,
    [MANUAL_2021],
    "Fiesta Mk8 launched in mid-2017: a 1.5 TDCi registered from late 2017 is almost always a Mk8. Intervals are 'whichever comes first'.",
)

fiesta_mk8_petrol = ford_template(
    "ford-fiesta-mk8-petrol", "Mk8 (2017–2023) — 1.0 EcoBoost / 1.1 Duratec petrol", (2017, 2023), "petrol",
    ["fiesta", "fiesta mk8", "fiesta 8", "fiesta viii", "fiesta ecoboost", "fiesta st"],
    [
        s("Fluids", "Engine oil (1.0 EcoBoost)", "SAE 5W-20 to Ford WSS-M2C948-B (top-up: max 0.5 L of ACEA A5/B5 5W-20)"),
        s("Fluids", "Engine oil capacity (1.0 EcoBoost)", "4.6 L incl. filter · dipstick MIN→MAX = 1 L"),
        s("Fluids", "Coolant (1.0 EcoBoost)", "Ford Super Plus Premium WSS-M97B44-D · 5.8 L"),
        s("Fluids", "Brake fluid", "DOT 4 LV High Performance WSS-M6C65-A2"),
        s("Fluids", "Fuel tank", "42 L"),
    ] + ford_checks,
    [MANUAL_2021],
    "Intervals are 'whichever comes first'. Timing-belt interval depends on the engine — edit it if yours is not a 1.0 EcoBoost.",
)

fiesta_mk7_petrol = ford_template(
    "ford-fiesta-mk7-petrol", "Mk7 (2008–2017) — petrol", (2008, 2017), "petrol",
    ["fiesta", "fiesta mk7", "fiesta 7", "fiesta vii", "fiesta mk6", "fiesta ecoboost", "fiesta duratec"],
    [
        s("Fluids", "Engine oil (1.0 EcoBoost)", "SAE 5W-20 to Ford WSS-M2C948-B"),
        s("Fluids", "Brake fluid", "DOT 4 (Ford Super DOT 4 / LV)"),
        s("Fluids", "Coolant", "Ford Super Plus (purple) — do not mix with other coolants"),
    ] + ford_checks,
    [],
    "Based on Ford's official 2013 Fiesta 1.0 EcoBoost service sheets. Intervals are 'whichever comes first'.",
)

fiesta_mk7_diesel = ford_template(
    "ford-fiesta-mk7-diesel", "Mk7 (2008–2017) — 1.4 / 1.5 / 1.6 TDCi diesel", (2008, 2017), "diesel",
    ["fiesta", "fiesta mk7", "fiesta 7", "fiesta vii", "fiesta mk6", "fiesta tdci", "fiesta 1.5 tdci", "fiesta 1.6 tdci"],
    [
        s("Fluids", "Brake fluid", "DOT 4 (Ford Super DOT 4 / LV)"),
        s("Fluids", "Coolant", "Ford Super Plus (purple) — do not mix with other coolants"),
        s("Fluids", "Engine oil", "See your owner's handbook — or use 'Import manual PDF' to fill this in automatically"),
    ] + ford_checks,
    [],
    "Intervals are 'whichever comes first'. Diesel-specific items come from the Haynes guide; check timing-belt interval with a Ford dealer.",
)

os.makedirs(OUT, exist_ok=True)
for tpl in [z400, fiesta_mk8_diesel, fiesta_mk8_petrol, fiesta_mk7_diesel, fiesta_mk7_petrol]:
    path = os.path.join(OUT, f"schedule-{tpl['id']}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(tpl, f, ensure_ascii=False, indent=2)
    print(path, len(tpl["tasks"]), "tasks")
