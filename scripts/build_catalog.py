"""Builds the schedule catalog that the app downloads from GitHub.

Run:  python3 scripts/build_catalog.py
Output: catalog/index.json (what the app lists and matches) and catalog/schedules/<id>.json
(downloaded only when a user picks that schedule). Push them to main to publish.

Every schedule file carries its own translations (it, fr, es, pt), so a new schedule needs no
app update. Translations come from scripts/catalog_i18n.py (TR: plain texts, TPL: texts with
numbers), then from ServiceBook/Schedules/Schedules.xcstrings (texts of the first built-in
schedules). Texts wrapped in N() hold only names, codes and numbers: they are copied with the
number format of each language. The build stops and lists every text without a translation.

Each schedule names its sources. Brand-wide plans ("All models") hold the manufacturer's
service regime and match any model of the make; model schedules rank above them.
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT = os.path.join(ROOT, "catalog")
LANGS = ["it", "fr", "es", "pt"]
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
from catalog_i18n import TR, TPL  # noqa: E402

AUTO = {}


def num(n, lang):
    s = f"{n:,}"
    return s if lang == "en" else s.replace(",", "." if lang in ("it", "es") else " ")


def loc(text, lang):
    """Number format of the language for a text made of names, codes and measurements."""
    if lang == "en":
        return text
    unit = r"(?=(?:\s?[–-]\s?\d+(?:\.\d+)?)?\s?(?:bar|mm|L\b|kg|N·m|kPa|psi))"
    s = re.sub(r"(\d)\.(\d+)" + unit, r"\1,\2", text)
    sep = "." if lang in ("it", "es") else " "
    while True:
        new = re.sub(r"(\d),(\d{3})(?!\d)", r"\1" + sep + r"\2", s)
        if new == s:
            return s
        s = new


def N(text):
    AUTO[text] = {l: loc(text, l) for l in LANGS}
    return text


def F(key, *args):
    """Text from a template in TPL, with numbers (ints) and names filled in for each language."""
    tpl = TPL[key]

    def arg(a, lang):
        if isinstance(a, int):
            return num(a, lang)
        if lang == "en":
            return a
        found = translation(a)
        return found[lang] if found else a

    en = tpl["en"].format(*[arg(a, "en") for a in args])
    AUTO[en] = {l: tpl[l].format(*[arg(a, l) for a in args]) for l in LANGS}
    return en


with open(os.path.join(ROOT, "ServiceBook", "Schedules", "Schedules.xcstrings"), encoding="utf-8") as f:
    XC = {k: {l: v["localizations"][l]["stringUnit"]["value"] for l in LANGS}
          for k, v in json.load(f)["strings"].items() if "localizations" in v}


def translation(text):
    if text in AUTO:
        return AUTO[text]
    if text in TR:
        return dict(zip(LANGS, TR[text]))
    return XC.get(text)


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


ROADWORTHY_MOTO = t("Roadworthiness test (contrôle technique / MOT / revisione)", "inspect", "legal", months=36, first_months=60,
                    notes="Depends on your country. France (2-wheelers): first at 5 years, then every 3 years. Italy: first at 4 years, then every 2. UK MOT: first at 3 years, then yearly. Edit this item to match your country.")
ROADWORTHY_CAR = t("Roadworthiness test (contrôle technique / MOT / revisione)", "inspect", "legal", months=24, first_months=48,
                   notes="Depends on your country. France & Italy: first at 4 years, then every 2 years. UK MOT: first at 3 years, then yearly. Edit this item to match your country.")
DAILY_MOTO = s("Before every ride", "Daily checks",
               "Fuel level · engine oil level · tyre pressure & condition · chain slack & lube · brake lever/pedal feel and fluid level · throttle snaps back · clutch · lights, indicators, horn · steering moves freely · engine stop & side stand switches")

# ====================================================================== Kawasaki Z400 (unchanged)
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
    "model": N("Z400"),
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
         for (name, action, cat, n) in z400_annual] + [ROADWORTHY_MOTO],
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
        DAILY_MOTO,
    ],
}

# ====================================================================== Motorcycles: shared builder
MOTO_REF = KAWA_REF
MOTO_REF_P = KAWA_REF + " (periodic inspection)"
MS = "https://maintenanceschedule.com/"


def moto(oil, *, oil_filter=None, initial=1000, initial_note=None, air=None, air_check=None, plugs=None, plugs_check=None,
         valves=None, valves_note=None, sync=None, coolant=None, coolant_first=None, brake_fluid=24, brake_fluid_first=None,
         brake_hoses=None, fork_oil=None, chain=True, chain_lube=1000, extra=(), ref=MOTO_REF, notes=None):
    """Tasks of a motorcycle schedule. Intervals are (km, months) tuples; months may be None."""
    notes = notes or {}
    km, months = oil
    out = []
    if initial:
        out.append(t("Initial (run-in) service", "service", "service", first_km=initial, one_time=True,
                     notes=initial_note or "Engine oil and filter change plus a full check of the bike. Follow the running-in rules in your manual.",
                     ref=ref))
    out.append(t("Engine oil", "replace", "oil", km=km, months=months, notes=notes.get("oil"), ref=ref))
    fk, fm = oil_filter or oil
    out.append(t("Oil filter", "replace", "oil", km=fk, months=fm, notes=notes.get("oil_filter"), ref=ref))
    if air_check:
        out.append(t("Air filter: check & clean", "clean", "filters", km=air_check[0], months=air_check[1], ref=ref))
    if air:
        out.append(t("Air cleaner element", "replace", "filters", km=air[0], months=air[1],
                     notes=notes.get("air", "Replace more often when riding in rain or on dusty roads."), ref=ref))
    if plugs_check:
        out.append(t("Spark plugs: check", "inspect", "ignition", km=plugs_check, ref=ref))
    if plugs:
        out.append(t("Spark plugs", "replace", "ignition", km=plugs, notes=notes.get("plugs"), ref=ref))
    if valves:
        out.append(t("Valve clearance", "inspect", "engine", km=valves, notes=valves_note or "Dealer job: requires removing the cylinder head cover.", ref=ref))
    if sync:
        out.append(t("Engine vacuum synchronization", "inspect", "engine", km=sync[0], months=sync[1], ref=ref))
    if coolant:
        out.append(t("Coolant: drain, flush & refill", "replace", "cooling", km=coolant[0], months=coolant[1],
                     first_km=coolant_first[0] if coolant_first else None, first_months=coolant_first[1] if coolant_first else None,
                     notes=notes.get("coolant"), ref=ref))
    out.append(t("Brake fluid (front & rear)", "replace", "brakes", months=brake_fluid, first_months=brake_fluid_first,
                 notes=notes.get("brake_fluid"), spec="DOT 4", ref=ref))
    if brake_hoses:
        out.append(t("Brake hoses", "replace", "brakes", months=brake_hoses, ref=ref))
    if fork_oil:
        out.append(t("Fork oil", "replace", "suspension", km=fork_oil, ref=ref))
    out += list(extra)
    if chain:
        out.append(t("Drive chain", "lubricate", "chain", km=chain_lube,
                     notes="Also after washing the bike or riding in the rain. Use chain lube for O/X-ring chains.", ref=ref))
        out.append(t("Drive chain slack", "check", "chain", km=1000,
                     notes="Measure where and how your manual says (the point and the stand differ between models).", ref=ref))
        out.append(t("Drive chain & sprocket wear", "inspect", "chain", km=km, ref=ref))
    for (name, action, cat, _) in z400_annual:
        if cat == "chain" and not chain:
            continue
        out.append(t(name, action, cat, km=km, months=months or 12, ref=MOTO_REF_P if ref == MOTO_REF else ref))
    out.append(ROADWORTHY_MOTO)
    return out


def moto_specs(oil, front, rear, *, slack=None, plug=None, capacity=None, axle=None, chain=True, extra=()):
    out = [s("Fluids", "Engine oil", N(oil))]
    if capacity:
        out.append(s("Fluids", "Engine oil capacity", N(capacity)))
    out.append(s("Fluids", "Brake fluid", "DOT 4"))
    out.append(s("Tyres", "Front tyre", N(front)))
    out.append(s("Tyres", "Rear tyre", N(rear)))
    if slack:
        out.append(s("Chain", "Chain slack", N(slack)))
    if axle:
        out.append(s("Chain", "Rear axle nut torque", N(axle)))
    if plug:
        out.append(s("Electrical", "Spark plug", N(plug)))
    out += list(extra)
    if chain:
        out.append(DAILY_MOTO)
    return out


def bike(tid, make, model, aliases, generation, years, tasks, specs, source, urls, disclaimer=None):
    return {
        "id": tid, "make": make, "model": N(model), "aliases": aliases, "generation": generation,
        "yearFrom": years[0], "yearTo": years[1], "kind": "motorcycle", "fuel": "petrol",
        "source": source, "sourceURLs": urls,
        "disclaimer": disclaimer or "Intervals are 'whichever comes first'. Ride in rain, dust or heavy traffic? Service more often. Always confirm with the manual for your exact bike.",
        "tasks": tasks, "specs": specs,
    }


def ms_source(name):
    return F("src_ms", name)


ALL = "All models"


def brand_bike(tid, make, tasks, note, source, urls, aliases=None):
    return {
        "id": tid, "make": make, "model": ALL, "aliases": aliases or [], "generation": "Brand-wide plan · motorcycles",
        "kind": "motorcycle", "fuel": "petrol", "generic": True,
        "source": source, "sourceURLs": urls, "disclaimer": note, "tasks": tasks,
        "specs": [s("Fluids", "Brake fluid", "DOT 4"), DAILY_MOTO],
    }


# ---------------------------------------------------------------- Honda
HONDA_NOTE = {"oil": "Honda Europe schedule: every 12,000 km or every year. Check the level in the window or on the dipstick before every ride."}
honda_bikes = [
    bike("honda-xl750-transalp", "Honda", "XL750 Transalp", ["transalp", "xl750", "xl 750"], N("XL750 (2023+)"), (2023, None),
         moto((12000, 12), oil_filter=(24000, None), air=(24000, None), plugs=48000, plugs_check=24000, valves=24000,
              coolant=(None, 36), notes=HONDA_NOTE),
         moto_specs("SAE 10W-30 · JASO T 903 MA", "90/90-21 54H · 2.25 bar", "150/70 R18 70H · 2.5–2.8 bar",
                    slack="50–55 mm", plug="NGK SILMAR8A9S · 0.8–0.9 mm"),
         ms_source("Honda XL750 Transalp"), [MS + "honda-xl750-transalp-2023-maintenance/"]),
    bike("honda-crf1100l-africa-twin", "Honda", "CRF1100L Africa Twin", ["africa twin", "africatwin", "crf1100", "crf 1100", "crf1100l"],
         N("CRF1100L (2020+)"), (2020, None),
         moto((12000, 12), oil_filter=(24000, None), air=(18000, None), plugs=48000, plugs_check=24000, valves=24000,
              coolant=(None, 36), notes=HONDA_NOTE,
              extra=[t("DCT clutch oil filter (DCT models)", "replace", "transmission", km=24000, first_km=1000, ref=MOTO_REF)]),
         moto_specs("SAE 10W-30 · JASO T 903 MA", "90/90-21 54H · 2.25 bar", "150/70 R18 70H · 2.5–2.8 bar",
                    slack="35–45 mm", plug="NGK SILMAR8A9S · 0.8–0.9 mm", axle="100 N·m",
                    extra=[s("Torques", "Oil drain bolt", N("30 N·m")), s("Torques", "Oil filter", N("26 N·m"))]),
         ms_source("Honda CRF1100L Africa Twin"), [MS + "honda-africa-twin-crf1100l-maintenance/"],
         F("disc_us_km", "Honda")),
    bike("honda-nc750x", "Honda", "NC750X", ["nc750", "nc 750", "nc750x", "nc750s", "nc 750 x", "nc750 dct"],
         N("RC90 / RH09 (2014+)"), (2014, None),
         moto((12000, 12), oil_filter=(24000, None), air=(18000, None), plugs=48000, plugs_check=24000, valves=24000,
              coolant=(None, 36), notes=HONDA_NOTE,
              extra=[t("DCT clutch oil filter (DCT models)", "replace", "transmission", km=24000, first_km=1000, ref=MOTO_REF)]),
         moto_specs("SAE 10W-30 · JASO T 903 MA", "120/70 ZR17 58W · 2.5 bar", "160/60 ZR17 69W · 2.9 bar",
                    plug="NGK IFR6G-11K · 1.0–1.1 mm",
                    extra=[s("Torques", "Oil drain bolt", N("30 N·m")), s("Torques", "Oil filter", N("26 N·m"))]),
         ms_source("Honda NC750X"), [MS + "honda-nc750x-maintenance-schedule/"], F("disc_us_km", "Honda")),
    bike("honda-cb750-hornet", "Honda", "CB750 Hornet", ["hornet 750", "cb750", "cb 750", "hornet750"], N("CB750 (2023+)"), (2023, None),
         moto((12000, 12), oil_filter=(24000, None), air=(24000, None), plugs=48000, plugs_check=24000, valves=24000,
              coolant=(None, 36), notes=HONDA_NOTE),
         moto_specs("SAE 10W-30 · JASO T 903 MA", "120/70 ZR17 58W · 2.5 bar", "160/60 ZR17 69W · 2.9 bar",
                    slack="25–35 mm", plug="NGK SILMAR8A9S"),
         ms_source("Honda CB750 Hornet"), [MS + "honda-cb750-hornet-2023-maintenance/"]),
    bike("honda-cb650r", "Honda", "CB650R / CBR650R", ["cb650r", "cbr650r", "cb 650 r", "cbr 650 r", "cb650", "cbr650"],
         N("CB650R / CBR650R (2019+)"), (2019, None),
         moto((12000, 12), oil_filter=(24000, None), air=(36000, None), plugs=48000, plugs_check=24000, valves=36000,
              coolant=(None, 36), notes=HONDA_NOTE),
         moto_specs("SAE 10W-30 · JASO T 903 MA", "120/70 ZR17 58W · 2.5 bar", "180/55 ZR17 73W · 2.9 bar",
                    slack="25–35 mm", plug="NGK IMR9E-9HES · 0.8–0.9 mm", axle="98 N·m",
                    extra=[s("Torques", "Oil drain bolt", N("30 N·m")), s("Torques", "Oil filter", N("26 N·m"))]),
         ms_source("Honda CB650R"), [MS + "honda-cb650r-maintenance-schedule/"], F("disc_us_km", "Honda")),
    bike("honda-cb500-family", "Honda", "CB500X / NX500 / CB500F / CBR500R", ["cb500x", "cb500f", "cbr500r", "nx500", "cb500 hornet", "cb500",
                                                                             "cb 500", "cbr 500", "nx 500"],
         N("471 cc (2019+)"), (2019, None),
         moto((12000, 12), oil_filter=(24000, None), air=(18000, None), plugs=24000, valves=24000,
              coolant=(None, 36), notes=HONDA_NOTE),
         moto_specs("SAE 10W-30 · JASO T 903 MA", "CB500X: 110/80 R19 · 2.0 bar", "CB500X: 160/60 ZR17 · 2.8 bar",
                    plug="NGK CPR8EA-9 · 0.8–0.9 mm",
                    extra=[s("Torques", "Oil drain bolt", N("30 N·m")), s("Torques", "Oil filter", N("26 N·m"))]),
         ms_source("Honda CB500X (2022)"), [MS + "honda-cb500x-2022-maintenance-schedule/"], F("disc_us_km", "Honda")),
]
honda_generic = brand_bike(
    "honda-generic-motorcycle", "Honda",
    moto((12000, 12), oil_filter=(24000, None), air=(18000, None), plugs=24000, valves=24000, coolant=(None, 36), notes=HONDA_NOTE),
    "Honda's usual plan for its road bikes: service every 12,000 km or every year. Air filter, spark plug and valve intervals vary by model (18,000–48,000 km): check your manual and edit the items.",
    F("src_ms_brand", "Honda"), [MS + "honda-xl750-transalp-2023-maintenance/", MS + "honda-cb650r-maintenance-schedule/"])

# ---------------------------------------------------------------- Yamaha
YAMA_NOTE = {"oil": "Yamaha Europe schedule: every 10,000 km or every year."}
yama_extra = [
    t("Steering bearings", "lubricate", "steering", km=20000, ref=MOTO_REF),
    t("Swingarm pivot bearings", "lubricate", "suspension", km=50000, ref=MOTO_REF),
]
yamaha_bikes = [
    bike("yamaha-mt07", "Yamaha", "MT-07", ["mt07", "mt 07", "fz07", "xsr700", "xsr 700", "tracer 7", "tracer7", "tracer 700", "yzf-r7", "r7"],
         N("CP2 689 cc (2014+)"), (2014, None),
         moto((10000, 12), oil_filter=(20000, None), air=(40000, None), plugs=20000, plugs_check=10000, valves=40000,
              coolant=(None, 36), brake_hoses=48, notes=YAMA_NOTE, extra=yama_extra),
         moto_specs("SAE 10W-40 · JASO MA", "120/70 ZR17 58W · 2.5 bar", "180/55 ZR17 73W · 2.9 bar",
                    slack="51–56 mm", plug="NGK LMAR9E-J · 0.6–0.7 mm", axle="105 N·m",
                    extra=[s("Torques", "Oil drain bolt", N("43 N·m")), s("Torques", "Oil filter", N("17 N·m"))]),
         ms_source("Yamaha MT-07"), [MS + "yamaha-mt-07-fz-07-maintenance/"],
         "Intervals are 'whichever comes first'. The XSR700, Tracer 7 and R7 share the engine: tyre sizes and chain slack differ, check your manual."),
    bike("yamaha-mt09", "Yamaha", "MT-09 / Tracer 9 / XSR900", ["mt09", "mt 09", "mt09 sp", "tracer 9", "tracer9", "tracer 9 gt", "xsr900", "xsr 900"],
         N("CP3 890 cc (2021+)"), (2021, None),
         moto((10000, 12), oil_filter=(20000, None), air=(40000, None), plugs=20000, plugs_check=10000, valves=40000,
              sync=(10000, 12), coolant=(None, 36), brake_hoses=48, notes=YAMA_NOTE, extra=yama_extra),
         moto_specs("SAE 10W-40 · JASO MA", "MT-09: 120/70 ZR17 58W · 2.5 bar", "MT-09: 180/55 ZR17 73W · 2.9 bar",
                    slack="36–41 mm", plug="NGK LMAR9A-9 · 0.8–0.9 mm", axle="105 N·m"),
         ms_source("Yamaha MT-09 (890 cc)"), [MS + "yamaha-mt-09-sp-mtn890-890cc-2021/"],
         "Intervals are 'whichever comes first'. The Tracer 9 and XSR900 share the engine: tyre sizes and chain slack differ, check your manual."),
    bike("yamaha-tenere700", "Yamaha", "Ténéré 700", ["tenere 700", "tenere700", "ténéré 700", "t7", "xtz690", "xtz 690", "tenere"],
         N("XTZ690 (2019+)"), (2019, None),
         moto((10000, 12), oil_filter=(20000, None), air=(20000, None), plugs=20000, plugs_check=10000, valves=40000,
              sync=(10000, 12), coolant=(None, 36), brake_hoses=48, notes=YAMA_NOTE, extra=yama_extra),
         moto_specs("SAE 10W-40 · JASO MA", "90/90-21 54V · 2.2 bar", "150/70 R18 70V · 2.5 bar",
                    slack="43–48 mm", plug="NGK LMAR8A-9 · 0.8–0.9 mm", axle="105 N·m",
                    extra=[s("Fluids", "Coolant capacity", N("1.6 L")), s("Torques", "Oil drain bolt", N("43 N·m")), s("Torques", "Oil filter", N("17 N·m"))]),
         ms_source("Yamaha Ténéré 700"), [MS + "yamaha-tenere-700-maintenance/"]),
]
yamaha_generic = brand_bike(
    "yamaha-generic-motorcycle", "Yamaha",
    moto((10000, 12), oil_filter=(20000, None), air=(20000, None), plugs=20000, valves=40000, coolant=(None, 36), brake_hoses=48,
         notes=YAMA_NOTE, extra=yama_extra[:1]),
    "Yamaha's usual plan for its current road bikes: service every 10,000 km or every year. Valve clearance is 40,000 km on the 700 and 900 twins and triples; other models can differ, so check your manual and edit the items.",
    F("src_ms_brand", "Yamaha"), [MS + "yamaha-mt-07-fz-07-maintenance/", MS + "yamaha-tenere-700-maintenance/"])

# ---------------------------------------------------------------- BMW Motorrad
BMW_INITIAL = "BMW running-in check between 500 and 1,200 km: engine oil and filter change and a full check by a BMW Motorrad dealer."
BMW_NOTES = {"oil": "BMW Motorrad annual service: every 10,000 km or every year.",
             "brake_fluid": "BMW: first change after 1 year, then every 2 years."}
bmw_shaft = [
    t("Final drive (rear bevel gear) oil", "replace", "transmission", km=20000, months=24, spec=N("SAE 70W-80 · API GL-5"), ref=MOTO_REF),
    t("Drive shaft: check & lubricate", "lubricate", "transmission", km=20000, ref=MOTO_REF),
    t("Drive shaft", "replace", "transmission", km=60000, ref=MOTO_REF),
]
bmw_bikes = [
    bike("bmw-r1300gs", "BMW", "R 1300 GS", ["r1300gs", "r 1300 gs", "r1300 gs", "r1300gsa", "r 1300 gs adventure", "r1300"],
         N("R 1300 GS / GS Adventure (2024+)"), (2024, None),
         moto((10000, 12), initial=1000, initial_note=BMW_INITIAL, air=(20000, None), plugs=20000, valves=20000,
              brake_fluid_first=12, chain=False, notes=BMW_NOTES, extra=bmw_shaft),
         moto_specs("SAE 5W-40 · API SL / JASO MA2 (BMW Advantec Ultimate)", "120/70 R19 · 2.5 bar", "170/60 R17 · 2.9 bar",
                    plug="NGK LMAR8AI-10", chain=False),
         ms_source("BMW R 1300 GS"), [MS + "bmw-r-1300-gs-maintenance/", MS + "bmw-r-1300-gs-adventure-2025-maintenance/"]),
    bike("bmw-r1250gs", "BMW", "R 1250 GS", ["r1250gs", "r 1250 gs", "r1250 gs", "r1250gsa", "r 1250 gs adventure", "r1250"],
         N("R 1250 GS / GS Adventure ShiftCam (2019–2023)"), (2019, 2024),
         moto((10000, 12), initial=1000, initial_note=BMW_INITIAL, air=(20000, 12), plugs=20000, valves=20000,
              brake_fluid_first=12, chain=False, notes=BMW_NOTES, extra=bmw_shaft),
         moto_specs("SAE 5W-40 · API SL / JASO MA2 (BMW Advantec Ultimate)", "120/70 R19 · 2.5 bar", "170/60 R17 · 2.9 bar",
                    plug="NGK LMAR8AI-10", chain=False,
                    extra=[s("Torques", "Oil drain bolt", N("42 N·m")), s("Torques", "Oil filter", N("11 N·m"))]),
         ms_source("BMW R 1250 GS"), [MS + "bmw-r-1250-gs-gsa-shiftcam-2019/"]),
    bike("bmw-f900gs", "BMW", "F 900 GS", ["f900gs", "f 900 gs", "f900 gs", "f900gsa", "f 900 gs adventure", "f800gs 2024", "f 800 gs"],
         N("F 900 GS / GS Adventure (2024+)"), (2024, None),
         moto((10000, 12), initial=1000, initial_note=BMW_INITIAL, air=(10000, None), plugs=20000, valves=20000,
              brake_fluid_first=12, fork_oil=30000, notes=BMW_NOTES),
         moto_specs("SAE 5W-40 · API SJ / JASO MA2 (BMW Advantec Ultimate)", "90/90-21 · 2.2–2.5 bar", "150/70 R17 · 2.5–2.9 bar",
                    slack="40–50 mm", plug="NGK LMAR9J-9E", capacity="3.5 L", axle="125 N·m"),
         ms_source("BMW F 900 GS"), [MS + "bmw-f-900-gs-maintenance/"],
         "Intervals are 'whichever comes first'. The source lists the air filter every 10,000 km (more often off-road); the new F 800 GS may differ, check your manual."),
    bike("bmw-f850gs", "BMW", "F 850 GS", ["f850gs", "f 850 gs", "f850 gs", "f850gsa", "f 850 gs adventure", "f750gs", "f 750 gs"],
         N("F 750 GS / F 850 GS (2018–2023)"), (2018, 2023),
         moto((10000, 12), initial=1000, initial_note=BMW_INITIAL, air=(20000, None), plugs=20000, valves=20000,
              brake_fluid_first=12, fork_oil=30000, notes=BMW_NOTES),
         moto_specs("SAE 5W-40 · API SL / JASO MA2", "90/90-21 · 2.2–2.5 bar", "150/70 R17 · 2.5–2.9 bar",
                    plug="NGK LMAR8J-9E"),
         ms_source("BMW F 850 GS"), [MS + "bmw-f-850-gs-maintenance-schedule/", MS + "bmw-f-750-gs-maintenance-schedule/"]),
]
bmw_generic = brand_bike(
    "bmw-generic-motorcycle", "BMW",
    moto((10000, 12), initial=1000, initial_note=BMW_INITIAL, air=(20000, None), plugs=20000, valves=20000, brake_fluid_first=12,
         notes=BMW_NOTES, extra=[bmw_shaft[0]]),
    "BMW Motorrad's usual plan: annual service every 10,000 km or every year, valves and spark plugs every 20,000 km. Final drive oil applies to shaft-drive models only; delete the chain items if your bike has a shaft.",
    F("src_ms_brand", "BMW Motorrad"), [MS + "bmw-r-1250-gs-gsa-shiftcam-2019/", MS + "bmw-f-900-gs-maintenance/"])

# ---------------------------------------------------------------- Kawasaki
def kawa(km=12000, plugs=12000, air=12000, valves=24000, fuel_filter=True, rear_susp=True):
    extra = [
        t("Air suction system", "inspect", "engine", km=km, ref=MOTO_REF),
        t("Fuel hoses", "replace", "fuel", months=60, ref=MOTO_REF),
        t("Brake master cylinder & caliper rubber parts", "replace", "brakes", km=48000, months=48, ref=MOTO_REF),
        t("Steering stem bearings", "lubricate", "steering", km=24000, months=24, ref=MOTO_REF),
        t("Drive chain guide wear", "inspect", "chain", km=km, ref=MOTO_REF),
    ]
    if fuel_filter:
        extra.insert(1, t("Fuel filter", "replace", "fuel", km=24000, ref=MOTO_REF))
    if rear_susp:
        extra.append(t("Rear suspension linkage", "lubricate", "suspension", km=24000, ref=MOTO_REF))
    tasks = moto((km, 12), air=(air, None), plugs=plugs, valves=valves, sync=(km, None), coolant=(36000, 36),
                 brake_hoses=48, chain_lube=600, extra=extra)
    for x in tasks:  # Kawasaki: brake fluid also by distance
        if x["title"] == "Brake fluid (front & rear)":
            x["intervalKm"] = 24000
    return tasks


kawasaki_bikes = [
    bike("kawasaki-z900", "Kawasaki", "Z900", ["z900", "z 900", "z900 se", "zr900"], N("ZR900 (2017–2024)"), (2017, 2024),
         kawa(),
         moto_specs("SAE 10W-40 · API SG+ · JASO MA", "120/70 ZR17 58W · 2.5 bar", "180/55 ZR17 73W · 2.9 bar",
                    slack="25–35 mm", plug="NGK CR9EIA-9", axle="110 N·m"),
         ms_source("Kawasaki Z900 (2020–2024)"), [MS + "kawasaki-z900-2020-maintenance/", MS + "kawasaki-z900-2017-maintenance-schedule/"]),
    bike("kawasaki-z650", "Kawasaki", "Z650 / Ninja 650", ["z650", "z 650", "ninja 650", "ninja650", "er650", "ex650", "z650rs"],
         N("ER650 / EX650 (2017+)"), (2017, None),
         kawa(),
         moto_specs("SAE 10W-40 · API SG+ · JASO MA", "120/70 ZR17 58W · 2.25 bar", "160/60 ZR17 69W · 2.5 bar",
                    slack="20–30 mm", plug="NGK CR9EIA-9 · 0.8–0.9 mm", capacity="1.8 L",
                    extra=[s("Torques", "Oil drain bolt", N("30 N·m")), s("Torques", "Oil filter", N("17.5 N·m"))]),
         ms_source("Kawasaki Z650"), [MS + "kawasaki-z650-2017-maintenance-schedule/"]),
    bike("kawasaki-versys650", "Kawasaki", "Versys 650", ["versys 650", "versys650", "kle650", "versys"], N("KLE650 (2015+)"), (2015, None),
         kawa(),
         moto_specs("SAE 10W-40 · API SG+ · JASO MA", "120/70 ZR17 58W · 2.25 bar", "160/60 ZR17 69W · 2.5 bar",
                    plug="NGK CR9EIA-9 · 0.8–0.9 mm", capacity="1.6–1.8 L",
                    extra=[s("Torques", "Oil drain bolt", N("30 N·m")), s("Torques", "Oil filter", N("17.5 N·m"))]),
         ms_source("Kawasaki Versys 650 (2015+)"), [MS + "kawasaki-versys-650-kle650-2015-gen3/"]),
]
kawasaki_generic = brand_bike(
    "kawasaki-generic-motorcycle", "Kawasaki", kawa(),
    "Kawasaki's usual plan for its road bikes: service every 12,000 km or every year, valves every 24,000 km. Check your manual for the items your model has (fuel filter, air suction, rear linkage) and edit them.",
    F("src_ms_brand", "Kawasaki"), [MS + "kawasaki-z650-2017-maintenance-schedule/", MS + "kawasaki-z900-2020-maintenance/"])

# ---------------------------------------------------------------- Suzuki
SUZ_NOTE = {"oil": "Suzuki schedule: every 6,000 km or every year.", "oil_filter": "Suzuki: at the first service (1,000 km), then every 18,000 km."}


def suzuki(coolant):
    return moto((6000, 12), oil_filter=(18000, None), air=(18000, None), air_check=(6000, None), plugs=12000, plugs_check=6000,
                valves=24000, sync=(12000, None), coolant=coolant, brake_hoses=48, notes=SUZ_NOTE)


suzuki_bikes = [
    bike("suzuki-vstrom650", "Suzuki", "V-Strom 650", ["v-strom 650", "vstrom 650", "vstrom650", "dl650", "v strom 650", "650xt"],
         N("DL650 (2017+)"), (2017, None), suzuki((None, 48)),
         moto_specs("SAE 10W-40 · JASO T 903 MA", "110/80 R19 59V · 2.25 bar", "150/70 R17 69V · 2.5–2.9 bar",
                    slack="20–30 mm", plug="NGK MR8E-9"),
         ms_source("Suzuki V-Strom 650 (2017+)"), [MS + "suzuki-v-strom-650-3rd-gen-maintenance-schedule/"]),
    bike("suzuki-776-twin", "Suzuki", "V-Strom 800 / GSX-8S / GSX-8R", ["v-strom 800", "vstrom 800", "vstrom800", "v-strom 800de", "800de", "800re",
                                                                      "gsx-8s", "gsx8s", "gsx-8r", "gsx8r", "gsx-8t", "gsx-8tt", "dl800"],
         N("776 cc (2023+)"), (2023, None), suzuki((24000, 48)),
         moto_specs("SAE 10W-40 · JASO MA", "V-Strom 800DE: 90/90-21 · 2.25 bar", "V-Strom 800DE: 150/70 R17 · 2.5–2.8 bar",
                    slack="V-Strom 800DE: 30–40 mm · GSX-8S: 20–30 mm", plug="NGK LMAR8BI-9", axle="100 N·m",
                    extra=[s("Torques", "Oil drain bolt", N("23 N·m")), s("Torques", "Oil filter", N("20 N·m"))]),
         ms_source("Suzuki V-Strom 800DE, GSX-8S"), [MS + "suzuki-v-strom-800de-2023-maintenance/", MS + "suzuki-gsx-8s-2023-maintenance/"]),
    bike("suzuki-gsx-s1000", "Suzuki", "GSX-S1000", ["gsx-s1000", "gsxs1000", "gsx s1000", "gsx-s1000gt", "gsx-s1000gx", "gsx-s 1000", "katana"],
         N("GSX-S1000 / GT / GX (2021+)"), (2021, None), suzuki((48000, 48)),
         moto_specs("SAE 10W-40 · JASO MA", "120/70 ZR17 58W · 2.5 bar", "190/50 ZR17 73W · 2.9 bar",
                    slack="20–30 mm", plug="NGK CR9EIA-9", axle="100 N·m"),
         ms_source("Suzuki GSX-S1000 (2022+)"), [MS + "suzuki-gsx-s1000-2022-maintenance/", MS + "suzuki-gsx-s1000gt-maintenance/"]),
]
suzuki_generic = brand_bike(
    "suzuki-generic-motorcycle", "Suzuki", suzuki((None, 48)),
    "Suzuki's usual plan: engine oil every 6,000 km or every year, oil filter every 18,000 km, valves every 24,000 km. Coolant: 4 years with Suzuki long-life coolant.",
    F("src_ms_brand", "Suzuki"), [MS + "suzuki-v-strom-650-3rd-gen-maintenance-schedule/", MS + "suzuki-gsx-8s-2023-maintenance/"])

# ---------------------------------------------------------------- KTM
KTM_NOTE = {"oil": "KTM: engine oil, oil filter and oil screens at every service or every year.",
            "brake_fluid": "Bikes with a hydraulic clutch: change the clutch fluid at the same time."}


def ktm(km, valves, coolant=48):
    return moto((km, 12), air=(km, None), plugs=valves, valves=valves, coolant=(None, coolant), notes=KTM_NOTE,
                valves_note="Dealer job.",
                extra=[t("Oil screens: clean", "clean", "oil", km=km, months=12, ref=MOTO_REF)])


ktm_bikes = [
    bike("ktm-390-2024", "KTM", "390 Duke / Adventure", ["390 duke", "390duke", "390 adventure", "390 adv", "390 enduro", "390 smc", "390"],
         N("399 cc (2024+)"), (2024, None), ktm(10000, 20000),
         moto_specs("SAE 15W-50 · JASO MA2", "390 Duke: 110/70 ZR17 · 2.0 bar", "390 Duke: 150/60 ZR17 · 2.0–2.2 bar",
                    plug="Bosch VR 6 NEU", axle="100 N·m",
                    extra=[s("Engine", "Valve clearance", "Intake 0.10–0.15 mm · Exhaust 0.15–0.20 mm")]),
         ms_source("KTM 390 Duke (2024+)"), [MS + "ktm-390-duke-2024-maintenance/", MS + "ktm-390-adventure-2025-399cc/"]),
    bike("ktm-390-2013", "KTM", "390 Duke / Adventure", ["390 duke", "390duke", "rc 390", "rc390", "390 adventure", "390 adv", "390"],
         N("373 cc (2013–2023)"), (2013, 2023), ktm(7500, 15000),
         moto_specs("SAE 15W-50 · JASO MA2", "390 Duke: 110/70 R17 · 2.0 bar", "390 Duke: 150/60 R17 · 2.0–2.2 bar",
                    plug="Bosch VR 5 NEU", axle="98 N·m",
                    extra=[s("Engine", "Valve clearance", "Intake 0.10–0.15 mm · Exhaust 0.15–0.20 mm")]),
         ms_source("KTM 390 Duke (2013–2023)"), [MS + "ktm-390-duke-maintenance-schedule/", MS + "ktm-390-adventure-maintenance/"]),
    bike("ktm-790-890", "KTM", "790 / 890 Duke & Adventure", ["890 duke", "890duke", "790 duke", "790duke", "890 adventure", "790 adventure",
                                                              "890 adv", "790 adv", "890 smt", "890", "790"],
         N("LC8c 799 / 889 cc (2018+)"), (2018, None), ktm(15000, 30000),
         moto_specs("SAE 10W-50 · JASO MA2", "890 Duke: 120/70 ZR17 · 2.3 bar", "890 Duke: 180/55 ZR17 · 2.5–2.6 bar",
                    plug="NGK LMAR9AI-10", axle="90 N·m",
                    extra=[s("Torques", "Oil drain bolt", N("20 N·m"))]),
         ms_source("KTM 890 Duke (2021+)"), [MS + "ktm-890-duke-2021-maintenance-schedule/", MS + "ktm-890-adventure-maintenance-service/"]),
    bike("ktm-1290-super-adventure", "KTM", "1290 Super Adventure", ["1290 super adventure", "1290 adventure", "super adventure", "1290 sa",
                                                                     "1290 super duke", "1290", "1390"],
         N("LC8 1301 cc (2021+)"), (2021, None), ktm(15000, 30000),
         moto_specs("SAE 10W-50 · JASO MA2", "120/70 ZR19 · 2.4 bar", "170/60 ZR17 · 2.9 bar", axle="90 N·m",
                    extra=[s("Electrical", "Spark plugs", "LKAR9DI-10 (inner) · LMAR7DI-10 (outer)")]),
         ms_source("KTM 1290 Super Adventure S (2021+)"), [MS + "ktm-1290-super-adventure-s-2021/"]),
]
ktm_generic = brand_bike(
    "ktm-generic-motorcycle", "KTM", ktm(15000, 30000),
    "KTM's usual plan for its twins: service every 15,000 km or every year, valves and spark plugs every 30,000 km. Single-cylinder 125–390 models are serviced more often (7,500–10,000 km): use their own schedule or edit the items.",
    F("src_ms_brand", "KTM"), [MS + "ktm-890-duke-2021-maintenance-schedule/", MS + "ktm-1290-super-adventure-s-2021/"])

# ---------------------------------------------------------------- Triumph
TRI_NOTE = {"oil": "Triumph: engine oil and filter at every service or every year."}


def triumph(km, major, coolant=36, fork=None, extra=()):
    return moto((km, 12), air=(major, None), plugs=major, valves=major, coolant=(None, coolant), fork_oil=fork,
                chain_lube=300, notes=TRI_NOTE, extra=list(extra))


triumph_bikes = [
    bike("triumph-trident-660", "Triumph", "Trident 660", ["trident 660", "trident660", "trident", "tiger sport 660", "daytona 660"],
         N("660 cc triple (2021–2025)"), (2021, 2025), triumph(16000, 32000, fork=64000),
         moto_specs("SAE 10W-40 · API SH / JASO MA", "120/70 ZR17 58W · 2.34 bar", "180/55 ZR17 73W · 2.9 bar",
                    slack="43–55 mm", plug="NGK CR9EK", axle="110 N·m"),
         ms_source("Triumph Trident 660"), [MS + "triumph-trident-660-maintenance/"],
         "Intervals are 'whichever comes first'. The Tiger Sport 660 and Daytona 660 share the engine: check your manual for differences."),
    bike("triumph-400", "Triumph", "Speed 400 / Scrambler 400 X", ["speed 400", "speed400", "scrambler 400", "scrambler 400 x", "400 x", "thruxton 400",
                                                                    "speed t4", "tr series"],
         N("398 cc (2024+)"), (2024, None),
         triumph(16000, 32000, coolant=48, fork=64000,
                 extra=[t("Fuel filter", "replace", "fuel", km=32000, ref=MOTO_REF),
                        t("Oil screens: clean", "clean", "oil", km=16000, months=12, ref=MOTO_REF)]),
         moto_specs("SAE 10W-50 · API SN / JASO MA2", "Speed 400: 110/70 R17 · 1.8 bar", "Speed 400: 150/60 R17 · 2.3 bar",
                    slack="20–30 mm", plug="Bosch VR6NEU · 17 N·m", axle="98 N·m",
                    extra=[s("Torques", "Oil drain bolt", N("13 N·m"))]),
         ms_source("Triumph Speed 400"), [MS + "triumph-speed-400-2024-maintenance/", MS + "triumph-scrambler-400-x-maintenance/"]),
    bike("triumph-tiger-900", "Triumph", "Tiger 900", ["tiger 900", "tiger900", "tiger 900 gt", "tiger 900 rally", "tiger 850", "tiger 850 sport"],
         N("Tiger 900 / 850 Sport (2020+)"), (2020, None),
         triumph(10000, 20000, fork=40000, extra=[t("Engine vacuum synchronization", "inspect", "engine", km=10000, ref=MOTO_REF)]),
         moto_specs("SAE 10W-40 · API SH / JASO MA", "GT: 100/90-19 · 2.5 bar · Rally: 90/90-21 · 2.3 bar", "150/70 R17 69V · 2.9 bar",
                    slack="GT: 25–35 mm · Rally: 30–40 mm", plug="NGK CR9EK", axle="110 N·m"),
         ms_source("Triumph Tiger 900"), [MS + "triumph-tiger-900-maintenance-schedule/"],
         "Intervals are 'whichever comes first'. Newer model years may have longer intervals: check the service book of your bike."),
    bike("triumph-street-triple-765", "Triumph", "Street Triple 765", ["street triple", "street triple 765", "streettriple", "765 rs", "765 r",
                                                                         "street triple rs", "street triple r"],
         N("765 cc (2017+)"), (2017, None), triumph(10000, 20000, fork=40000),
         moto_specs("SAE 10W-40 · API SH / JASO MA", "120/70 ZR17", "180/55 ZR17",
                    slack="20–30 mm", plug="NGK CR9EIA9 · 0.9 mm", axle="110 N·m"),
         ms_source("Triumph Street Triple R 765"), [MS + "triumph-street-triple-r-maintenance-schedule/"],
         "Intervals are 'whichever comes first'. Newer model years may have longer intervals: check the service book of your bike."),
]
triumph_generic = brand_bike(
    "triumph-generic-motorcycle", "Triumph", triumph(16000, 32000),
    "Triumph's current plan: service every 16,000 km or every year, valves and spark plugs every 32,000 km. Many models built before about 2022 use 10,000 / 20,000 km: check your service book and edit the items.",
    F("src_ms_brand", "Triumph"), [MS + "triumph-trident-660-maintenance/", MS + "triumph-speed-400-2024-maintenance/"])

# ---------------------------------------------------------------- Ducati
DUC_NOTE = {"brake_fluid": "Ducati: brake and clutch fluid every 2 years."}
duc_belts = lambda km: t("Timing belts", "replace", "engine", km=km, months=60, ref=MOTO_REF,
                          notes="Ducati's twins with belt-driven camshafts. Replace even if they look fine.")
ducati_bikes = [
    bike("ducati-multistrada-v4", "Ducati", "Multistrada V4", ["multistrada v4", "multistrada", "multistrada v4 s", "multistrada v4s",
                                                                "multistrada v4 rally", "multistrada v4 pikes peak"],
         N("V4 Granturismo (2021+)"), (2021, None),
         moto((15000, 24), air=(30000, None), air_check=(15000, None), plugs=60000, valves=60000, coolant=(None, 48), fork_oil=45000,
              notes=DUC_NOTE, valves_note="Valve clearance check every 60,000 km (V4 Granturismo engine, spring valves).",
              extra=[t("Annual service checklist", "inspect", "service", months=12, ref=MOTO_REF)]),
         moto_specs("SAE 15W-50 · API SN / JASO MA2", "120/70 R19 60W · 2.4 bar", "170/60 R17 72W · 2.5–2.9 bar",
                    slack="33–35 mm", plug="NGK T00132U · 12 N·m",
                    extra=[s("Torques", "Oil drain bolt", N("14 N·m"))]),
         ms_source("Ducati Multistrada V4 / V4 S"), [MS + "ducati-multistrada-v4-v4s-maintenance/"]),
    bike("ducati-monster-937", "Ducati", "Monster 937", ["monster", "monster 937", "monster+", "monster plus", "monster sp", "monster 950"],
         N("937 cc (2021–2025)"), (2021, 2025),
         moto((15000, 24), air=(30000, None), air_check=(15000, None), plugs=30000, valves=30000, coolant=(30000, 48), fork_oil=45000,
              notes=DUC_NOTE, valves_note="Desmo service: valve clearance check and adjustment.",
              extra=[duc_belts(30000), t("Annual service checklist", "inspect", "service", months=12, ref=MOTO_REF)]),
         moto_specs("SAE 15W-50 · API SN / JASO MA2", "120/70 ZR17 58W · 2.3–2.5 bar", "180/55 ZR17 73W · 2.5–2.9 bar",
                    slack="53–55 mm",
                    extra=[s("Torques", "Oil drain bolt", N("20 N·m")), s("Torques", "Oil filter", N("12 N·m"))]),
         ms_source("Ducati Monster 937"), [MS + "ducati-monster-plus-2021-937cc/", MS + "ducati-monster-sp-937-2023/"]),
    bike("ducati-scrambler-800", "Ducati", "Scrambler 800", ["scrambler", "scrambler 800", "scrambler icon", "scrambler full throttle",
                                                              "scrambler nightshift", "desert sled", "scrambler cafe racer"],
         N("803 cc (2015–2022)"), (2015, 2022),
         moto((12000, 12), air=(24000, None), air_check=(12000, 12), plugs=24000, valves=12000, fork_oil=36000, notes=DUC_NOTE,
              valves_note="Desmo service: valve clearance check and adjustment.",
              extra=[duc_belts(24000)]),
         moto_specs("SAE 15W-50 · API SN / JASO MA2", "Icon: 110/80 R18 58H · 2.5 bar", "Icon: 180/55 R17 73H · 2.5–2.9 bar",
                    slack="48–50 mm", plug="NGK DCPR8E", capacity="3.7 L", axle="145 N·m"),
         ms_source("Ducati Scrambler 800"), [MS + "ducati-scrambler-800-maintenance-schedule/"],
         "Intervals are 'whichever comes first'. Second-generation Scramblers (2023+) have a different schedule: check your manual."),
]
ducati_generic = brand_bike(
    "ducati-generic-motorcycle", "Ducati",
    moto((15000, 24), air=(30000, None), air_check=(15000, None), plugs=30000, valves=30000, coolant=(None, 48), notes=DUC_NOTE,
         valves_note="Desmo service: valve clearance check and adjustment.",
         extra=[duc_belts(30000), t("Annual service checklist", "inspect", "service", months=12, ref=MOTO_REF)]),
    "Ducati's usual plan for its current twins: oil every 15,000 km or 2 years with an annual check, Desmo service every 30,000 km. Older air-cooled models need the Desmo service every 12,000 km; V4 engines every 60,000 km and have no belts. Edit the items for your bike.",
    F("src_ms_brand", "Ducati"), [MS + "ducati-monster-plus-2021-937cc/", MS + "ducati-multistrada-v4-v4s-maintenance/"])

# ====================================================================== Cars: Ford (unchanged + new models)
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
        ROADWORTHY_CAR,
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


ford_checks = [
    s("Owner checks", "Daily", "Exterior lamps · interior lamps · warning lamps and indicators"),
    s("Owner checks", "When refuelling", "Washer fluid · tyre pressures · tyre condition"),
    s("Owner checks", "Monthly", "Engine oil, coolant & brake fluid levels · leaks · A/C · parking brake · horn · wheel nut tightness"),
    s("Tyres", "Tyre pressures", "See the label on the driver's door B-pillar (depends on tyre size and load)"),
]
FORD_URLS = [
    "https://www.newtonnet.co.uk/fiesta/serviceschedule-1yr12500mi.pdf",
    "https://www.newtonnet.co.uk/fiesta/serviceschedule-3yr37500mi.pdf",
    "https://haynes.com/en-gb/tips-tutorials/ford-fiesta-routine-maintenance-guide-2013-2017-models",
]
MANUAL_2021 = "https://www.fordservicecontent.com/Ford_Content/Catalog/owner_information/CG3654en-202012-20201214103157.pdf"


def ford_template(tid, model, generation, years, fuel, aliases, specs, extra_sources, note, generic=False):
    tasks = ford_common() + (ford_diesel() if fuel == "diesel" else ford_petrol())
    d = {
        "id": tid, "make": "Ford", "model": model if model == ALL else N(model), "aliases": aliases, "generation": generation,
        "yearFrom": years[0], "yearTo": years[1], "kind": "car", "fuel": fuel,
        "source": "Ford Europe service schedules (Fiesta), Ford Fiesta owner's manual, Haynes maintenance guide",
        "sourceURLs": FORD_URLS + extra_sources, "disclaimer": note, "tasks": tasks, "specs": specs,
    }
    if generic:
        d["generic"] = True
    return d


fiesta_mk8_diesel = ford_template(
    "ford-fiesta-mk8-diesel", "Fiesta", "Mk8 (2017–2023) — 1.5 TDCi / EcoBlue diesel", (2017, 2023), "diesel",
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
    "ford-fiesta-mk8-petrol", "Fiesta", "Mk8 (2017–2023) — 1.0 EcoBoost / 1.1 Duratec petrol", (2017, 2023), "petrol",
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
    "ford-fiesta-mk7-petrol", "Fiesta", "Mk7 (2008–2017) — petrol", (2008, 2017), "petrol",
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
    "ford-fiesta-mk7-diesel", "Fiesta", "Mk7 (2008–2017) — 1.4 / 1.5 / 1.6 TDCi diesel", (2008, 2017), "diesel",
    ["fiesta", "fiesta mk7", "fiesta 7", "fiesta vii", "fiesta mk6", "fiesta tdci", "fiesta 1.5 tdci", "fiesta 1.6 tdci"],
    [
        s("Fluids", "Brake fluid", "DOT 4 (Ford Super DOT 4 / LV)"),
        s("Fluids", "Coolant", "Ford Super Plus (purple) — do not mix with other coolants"),
        s("Fluids", "Engine oil", "See your owner's handbook — or use 'Import manual PDF' to fill this in automatically"),
    ] + ford_checks,
    [],
    "Intervals are 'whichever comes first'. Diesel-specific items come from the Haynes guide; check timing-belt interval with a Ford dealer.",
)
ford_petrol_specs = [
    s("Fluids", "Engine oil (1.0 EcoBoost)", "SAE 5W-20 to Ford WSS-M2C948-B"),
    s("Fluids", "Brake fluid", "DOT 4 LV High Performance WSS-M6C65-A2"),
] + ford_checks
FORD_SAME = "Ford uses the same service regime across its European range: these items come from the Fiesta service sheets. Check the timing-belt item for your engine (some recent engines have a chain) and edit it."
ford_more = [
    ford_template("ford-puma-petrol", N("Puma"), F("gen_petrol", N("2019+ · 1.0 EcoBoost (mHEV)")), (2019, None), "petrol",
                  ["puma", "puma st", "puma ecoboost", "puma hybrid", "puma mhev"], ford_petrol_specs, [], FORD_SAME),
    ford_template("ford-focus-mk4-petrol", N("Focus"), F("gen_petrol", N("Mk4 (2018+) · 1.0 / 1.5 EcoBoost")), (2018, None), "petrol",
                  ["focus", "focus mk4", "focus 4", "focus iv", "focus ecoboost", "focus st", "focus active"], ford_petrol_specs, [], FORD_SAME),
    ford_template("ford-focus-mk4-diesel", N("Focus"), F("gen_diesel", N("Mk4 (2018+) · 1.5 / 2.0 EcoBlue")), (2018, None), "diesel",
                  ["focus", "focus mk4", "focus 4", "focus iv", "focus ecoblue", "focus tdci"],
                  [s("Fluids", "Brake fluid", "DOT 4 LV High Performance WSS-M6C65-A2")] + ford_checks, [], FORD_SAME),
    ford_template("ford-generic-petrol", ALL, "Brand-wide plan · petrol", (None, None), "petrol", [], ford_petrol_specs, [], FORD_SAME, generic=True),
    ford_template("ford-generic-diesel", ALL, "Brand-wide plan · diesel", (None, None), "diesel", [],
                  [s("Fluids", "Brake fluid", "DOT 4 LV High Performance WSS-M6C65-A2")] + ford_checks, [], FORD_SAME, generic=True),
]

# ====================================================================== Cars: shared builder
HAYNES_PLAN = "Haynes maintenance plan (manufacturer intervals)"
OWNER = "Owner's handbook"
HAYNES_URL = "https://uk.haynes.com/pages/maintenance-plans-car-"


def car_checks(km, months, ref):
    """The checks done at every service, with the same titles as the Ford schedules."""
    return [t(title, action, cat, km=km, months=months, ref=ref) for (title, action, cat) in [
        ("Brakes: pads, discs & rear drums", "inspect", "brakes"),
        ("Brake fluid level & leaks", "check", "brakes"),
        ("Tyres: wear, condition & tread depth", "inspect", "tyres"),
        ("Steering, suspension, ball joints & driveshaft gaiters", "inspect", "suspension"),
        ("Engine, transmission & underbody leaks", "inspect", "engine"),
        ("Pipes, hoses, wiring & exhaust", "inspect", "chassis"),
        ("Coolant antifreeze concentration & fluid levels", "check", "cooling"),
        ("Battery (leaks, condition)", "inspect", "electrical"),
        ("Lights, instruments, warning lamps & horn", "check", "electrical"),
        ("Windscreen, wipers & washers", "check", "body"),
        ("Seat belts, buckles & stalks", "check", "safety"),
    ]]


def car_owner():
    return [
        t("Safety kit (warning triangle, vest, first aid kit)", "check", "safety", months=12,
          notes="Check the first aid kit expiry date. A vest and warning triangle are mandatory in France and Italy."),
        t("Monthly owner checks", "check", "owner", months=1,
          notes="Engine oil level · coolant level · brake fluid level · pipes, hoses & reservoirs for leaks · A/C operation · parking brake · horn · wheel nut tightness.",
          ref=OWNER),
        t("Tyre pressures & condition (when refuelling)", "check", "tyres", months=1,
          notes="Also check washer fluid. Pressures are on the label in the driver's door frame.", ref=OWNER),
        ROADWORTHY_CAR,
    ]


DPF = t("Diesel particulate filter & AdBlue (if fitted)", "inspect", "emissions", months=12,
        notes="Do a regular 20+ minute motorway drive so the DPF can regenerate, especially if you mostly do short trips.")


def car(tid, make, model, aliases, generation, years, fuel, tasks, specs, source, urls, disclaimer, generic=False, make_aliases=None):
    d = {"id": tid, "make": make}
    if make_aliases:
        d["makeAliases"] = make_aliases
    d.update({"model": model, "aliases": aliases, "generation": generation, "yearFrom": years[0], "yearTo": years[1],
              "kind": "car", "fuel": fuel, "source": source, "sourceURLs": urls, "disclaimer": disclaimer,
              "tasks": tasks, "specs": specs + ford_checks})
    if generic:
        d["generic"] = True
    return d


# ---------------------------------------------------------------- Volkswagen group (VW, Škoda)
def vag(fuel):
    ref = HAYNES_PLAN
    out = [t("Regular service: engine oil & filter", "replace", "oil", km=15000, months=12, ref=ref,
             notes="Fixed service: every 15,000 km or every year. With LongLife (flexible) service the car tells you when it is due, up to 30,000 km or 2 years. Use oil with the VW approval in your handbook.")]
    out += car_checks(15000, 12, ref)
    out += [
        t("Cabin (pollen / odour) filter", "replace", "filters", km=60000, months=24, ref=ref),
        t("Air filter (induction)", "replace", "filters", km=90000, months=72, ref=ref, notes="More often in dusty or polluted conditions."),
        t("Brake fluid", "replace", "brakes", months=24, ref=ref, spec="DOT 4"),
    ]
    if fuel == "petrol":
        out.append(t("Spark plugs", "replace", "ignition", km=60000, months=48, ref=ref))
    else:
        out.append(t("Timing belt, tensioner & water pump", "replace", "engine", km=210000, ref=ref,
                     notes="2.0 TDI (EA288): 210,000 km. VW gives no time limit; many garages also change it after about 10 years."))
        out.append(DPF)
    return out + car_owner()


VAG_PETROL_NOTE = "Intervals are 'whichever comes first'. 1.0 / 1.5 TSI engines have a timing belt with no fixed replacement interval: it is inspected at services. DSG gearbox oil, where needed, depends on the gearbox type: check your service booklet."
VAG_DIESEL_NOTE = "Intervals are 'whichever comes first'. DSG gearbox oil, where needed, depends on the gearbox type: check your service booklet."
VW_SRC = F("src_haynes", "Škoda Octavia IV (VW group regime)")
VW_URLS = [HAYNES_URL + "skoda-octavia-iv-2020-2025", HAYNES_URL + "volkswagen-t-roc-2018-2025"]
VW_PETROL_OIL = [s("Fluids", "Engine oil", "VW 508 00 (0W-20) · older engines: VW 504 00 (5W-30)")]
VW_DIESEL_OIL = [s("Fluids", "Engine oil", "VW 509 00 (0W-20) · older engines: VW 507 00 (5W-30)")]


def vag_car(tid, make, model, aliases, gen, years, fuel, make_aliases=None, generic=False):
    return car(tid, make, model, aliases, F("gen_" + fuel, gen) if not generic else "Brand-wide plan · " + fuel, years, fuel,
               vag(fuel), VW_PETROL_OIL if fuel == "petrol" else VW_DIESEL_OIL, VW_SRC, VW_URLS,
               VAG_PETROL_NOTE if fuel == "petrol" else VAG_DIESEL_NOTE, generic=generic, make_aliases=make_aliases)


VW = ["vw", "volkswagen"]
vag_cars = [
    vag_car("volkswagen-golf-8-petrol", "Volkswagen", N("Golf"), ["golf", "golf 8", "golf viii", "golf mk8", "golf variant", "golf gti", "golf etsi", "golf tsi"],
            N("Mk8 (2020+) · 1.0 / 1.5 TSI / eTSI"), (2020, None), "petrol", VW),
    vag_car("volkswagen-golf-8-diesel", "Volkswagen", N("Golf"), ["golf", "golf 8", "golf viii", "golf mk8", "golf variant", "golf tdi", "golf gtd"],
            N("Mk8 (2020+) · 2.0 TDI"), (2020, None), "diesel", VW),
    vag_car("volkswagen-polo-6-petrol", "Volkswagen", N("Polo"), ["polo", "polo 6", "polo vi", "polo aw", "polo tsi", "polo gti"],
            N("AW (2017+) · 1.0 MPI / TSI"), (2017, None), "petrol", VW),
    vag_car("volkswagen-t-roc-petrol", "Volkswagen", N("T-Roc"), ["t-roc", "troc", "t roc", "t-roc cabriolet"],
            N("2017+ · 1.0 / 1.5 TSI"), (2017, None), "petrol", VW),
    vag_car("volkswagen-t-roc-diesel", "Volkswagen", N("T-Roc"), ["t-roc", "troc", "t roc"],
            N("2017+ · 2.0 TDI"), (2017, None), "diesel", VW),
    vag_car("volkswagen-tiguan-petrol", "Volkswagen", N("Tiguan"), ["tiguan", "tiguan allspace", "tiguan 2", "tiguan 3", "tiguan ehybrid"],
            N("2016+ · 1.5 / 2.0 TSI"), (2016, None), "petrol", VW),
    vag_car("volkswagen-tiguan-diesel", "Volkswagen", N("Tiguan"), ["tiguan", "tiguan allspace", "tiguan 2", "tiguan 3", "tiguan tdi"],
            N("2016+ · 2.0 TDI"), (2016, None), "diesel", VW),
    vag_car("volkswagen-generic-petrol", "Volkswagen", ALL, [], None, (None, None), "petrol", VW, generic=True),
    vag_car("volkswagen-generic-diesel", "Volkswagen", ALL, [], None, (None, None), "diesel", VW, generic=True),
    vag_car("skoda-octavia-4-petrol", "Škoda", N("Octavia"), ["octavia", "octavia 4", "octavia iv", "octavia combi", "octavia rs"],
            N("IV (2020+) · 1.0 / 1.5 TSI / eTSI"), (2020, None), "petrol"),
    vag_car("skoda-octavia-4-diesel", "Škoda", N("Octavia"), ["octavia", "octavia 4", "octavia iv", "octavia combi", "octavia tdi"],
            N("IV (2020+) · 2.0 TDI"), (2020, None), "diesel"),
    vag_car("skoda-fabia-4-petrol", "Škoda", N("Fabia"), ["fabia", "fabia 4", "fabia iv"], N("IV (2021+) · 1.0 MPI / TSI"), (2021, None), "petrol"),
    vag_car("skoda-generic-petrol", "Škoda", ALL, [], None, (None, None), "petrol", generic=True),
    vag_car("skoda-generic-diesel", "Škoda", ALL, [], None, (None, None), "diesel", generic=True),
]

# ---------------------------------------------------------------- BMW (cars)
def bmw_car_tasks(fuel):
    ref = HAYNES_PLAN
    out = [t("Regular service: engine oil & filter", "replace", "oil", km=30000, months=24, ref=ref,
             notes="BMW Condition Based Service: the car shows when the oil service is due. These are the maximums: 30,000 km or 2 years.")]
    out += car_checks(30000, 24, ref)
    out += [
        t("Cabin (pollen / odour) filter", "replace", "filters", km=30000, months=24, ref=ref, notes="BMW: at every oil service."),
        t("Air filter (induction)", "replace", "filters", km=60000, months=48, ref=ref, notes="BMW: every second oil service."),
        t("Brake fluid", "replace", "brakes", months=24, first_months=36, ref=ref, spec="DOT 4", notes="BMW: first after 3 years, then every 2 years."),
        t("BMW vehicle check", "inspect", "service", km=60000, months=48, ref=ref),
    ]
    if fuel == "petrol":
        out.append(t("Spark plugs", "replace", "ignition", km=60000, months=48, ref=ref, notes="BMW: every second oil service."))
    else:
        out.append(DPF)
    return out + car_owner()


BMW_NOTE = "BMW engines use timing chains: there is no belt to replace. Follow the service display (Condition Based Service); intervals here are BMW's maximums."
BMW_SRC = F("src_haynes", "BMW 3 Series (2019–2025)")
BMW_URLS = [HAYNES_URL + "bmw-3-series-2019-2025"]
bmw_cars = [
    car("bmw-3-series-g20-petrol", "BMW", "3 Series", ["3 series", "serie 3", "série 3", "3er", "318i", "320i", "330i", "330e", "320e", "m340i", "g20", "g21"],
        F("gen_petrol", N("G20 / G21 (2019+)")), (2019, None), "petrol", bmw_car_tasks("petrol"),
        [s("Fluids", "Engine oil", N("BMW Longlife-01 / Longlife-17 FE+"))], BMW_SRC, BMW_URLS, BMW_NOTE),
    car("bmw-3-series-g20-diesel", "BMW", "3 Series", ["3 series", "serie 3", "série 3", "3er", "316d", "318d", "320d", "330d", "m340d", "g20", "g21"],
        F("gen_diesel", N("G20 / G21 (2019+)")), (2019, None), "diesel", bmw_car_tasks("diesel"),
        [s("Fluids", "Engine oil", N("BMW Longlife-04"))], BMW_SRC, BMW_URLS, BMW_NOTE),
    car("bmw-generic-petrol", "BMW", ALL, [], "Brand-wide plan · petrol", (None, None), "petrol", bmw_car_tasks("petrol"),
        [], BMW_SRC, BMW_URLS, BMW_NOTE, generic=True),
    car("bmw-generic-diesel", "BMW", ALL, [], "Brand-wide plan · diesel", (None, None), "diesel", bmw_car_tasks("diesel"),
        [s("Fluids", "Engine oil", N("BMW Longlife-04"))], BMW_SRC, BMW_URLS, BMW_NOTE, generic=True),
]

# ---------------------------------------------------------------- Renault group (Renault, Dacia)
def renault_tasks(fuel):
    ref = HAYNES_PLAN
    out = [t("Regular service: engine oil & filter", "replace", "oil", km=30000, months=24, first_months=12, ref=ref,
             notes="Renault: first service after 1 year, then every 30,000 km or 2 years. If you drive more than 15,000 km a year: every 30,000 km or every year.")]
    out += car_checks(30000, 24, ref)
    out += [
        t("Cabin (pollen / odour) filter", "replace", "filters", km=30000, months=24, first_months=12, ref=ref),
        t("Air filter (induction)", "replace", "filters", km=60000, months=48, ref=ref, notes="More often in dusty or polluted conditions."),
        t("Brake fluid", "replace", "brakes", months=36, ref=ref, spec="DOT 4", notes="Cars registered before 2022: every 120,000 km or 3 years."),
    ]
    if fuel == "petrol":
        out.append(t("Spark plugs", "replace", "ignition", km=60000, months=48, ref=ref))
    else:
        out.append(t("Timing belt, tensioner & water pump", "replace", "engine", km=120000, months=60, ref=N("ad.fr"),
                     notes="1.5 dCi / Blue dCi: Renault's interval depends on the engine version (secondary sources give 120,000–160,000 km and 4–6 years). Check your service booklet and edit this item."))
        out.append(DPF)
    return out + car_owner()


REN_NOTE = "Intervals are 'whichever comes first'. The TCe and SCe petrol engines have a timing chain. Renault engines also need oil meeting Renault RN17."
REN_DIESEL_NOTE = "Intervals are 'whichever comes first'. Diesel items other than the timing belt follow Renault's regime for its petrol engines (Haynes): confirm with your service booklet."
REN_SRC = F("src_haynes", "Renault Clio V, Captur II, Dacia Sandero III")
REN_URLS = [HAYNES_URL + "renault-clio-v-2019-2025", HAYNES_URL + "renault-captur-ii-2020-2025", HAYNES_URL + "dacia-sandero-iii-2021-2025"]
REN_OIL = [s("Fluids", "Engine oil", N("Renault RN17 (5W-30)"))]


def ren_car(tid, make, model, aliases, gen, years, fuel, generic=False, hybrid=False):
    note = REN_NOTE if fuel == "petrol" else REN_DIESEL_NOTE
    if hybrid:
        note = "E-Tech hybrid: the service regime is assumed to be the same as Renault's petrol engines (Haynes lists only the petrol versions). Confirm with your service booklet."
    gen_text = ("Brand-wide plan · " + fuel) if generic else F("gen_" + ("hybrid" if hybrid else fuel), gen)
    return car(tid, make, model, aliases, gen_text, years, "hybrid" if hybrid else fuel, renault_tasks(fuel),
               REN_OIL, REN_SRC, REN_URLS, note, generic=generic)


ren_cars = [
    ren_car("renault-clio-5-petrol", "Renault", N("Clio"), ["clio", "clio 5", "clio v", "clio tce", "clio sce", "clio eco-g", "clio gpl", "clio lpg"],
            N("V (2019+) · SCe / TCe / ECO-G"), (2019, None), "petrol"),
    ren_car("renault-clio-5-hybrid", "Renault", N("Clio"), ["clio", "clio 5", "clio v", "clio e-tech", "clio etech", "clio hybrid"],
            N("V (2020+) · E-Tech 140 / 145"), (2020, None), "petrol", hybrid=True),
    ren_car("renault-captur-2-petrol", "Renault", N("Captur"), ["captur", "captur 2", "captur ii", "captur tce", "captur eco-g"],
            N("II (2019+) · TCe / ECO-G"), (2019, None), "petrol"),
    ren_car("renault-generic-petrol", "Renault", ALL, [], None, (None, None), "petrol", generic=True),
    ren_car("renault-generic-diesel", "Renault", ALL, [], None, (None, None), "diesel", generic=True),
    ren_car("dacia-sandero-3-petrol", "Dacia", N("Sandero"), ["sandero", "sandero 3", "sandero iii", "sandero stepway", "stepway", "sandero eco-g"],
            N("III (2020+) · SCe / TCe / ECO-G"), (2020, None), "petrol"),
    ren_car("dacia-duster-petrol", "Dacia", N("Duster"), ["duster", "duster 2", "duster 3", "duster ii", "duster iii", "duster tce", "duster eco-g", "jogger", "bigster"],
            N("II / III (2018+) · TCe / ECO-G"), (2018, None), "petrol"),
    ren_car("dacia-generic-petrol", "Dacia", ALL, [], None, (None, None), "petrol", generic=True),
    ren_car("dacia-generic-diesel", "Dacia", ALL, [], None, (None, None), "diesel", generic=True),
]

# ---------------------------------------------------------------- Stellantis (Peugeot, Citroën, Opel)
def stellantis_tasks(fuel):
    ref = HAYNES_PLAN
    if fuel == "petrol":
        out = [t("Regular service: engine oil & filter", "replace", "oil", km=15000, months=12, ref=ref,
                 notes="The service plan says every 20,000 km or every year. For the 1.2 PureTech with a belt in oil, Peugeot now advises changing the oil every 15,000 km or every year with the approved 0W-30 / 0W-20 oil, so this item uses 15,000 km.")]
        out += car_checks(20000, 12, ref)
        out += [
            t("Cabin (pollen / odour) filter", "replace", "filters", km=20000, months=12, ref=ref),
            t("Air filter (induction)", "replace", "filters", km=40000, months=48, ref=ref, notes="More often in dusty or polluted conditions."),
            t("Spark plugs", "replace", "ignition", km=40000, months=48, ref=ref),
            t("Timing belt, tensioner & idlers", "replace", "engine", km=100000, months=72, ref=N("ad.fr"),
              notes="1.2 PureTech (belt in oil): 100,000 km or 6 years. Have the belt checked when the dealer asks. Since 2024 some versions (e.g. the 1.2 Hybrid) have a timing chain: delete this item if yours does."),
        ]
    else:
        out = [t("Regular service: engine oil & filter", "replace", "oil", km=30000, months=12, ref=ref,
                 notes="1.5 BlueHDi: every 30,000 km or every year.")]
        out += car_checks(30000, 12, ref)
        out += [
            t("Cabin (pollen / odour) filter", "replace", "filters", km=30000, months=12, ref=ref),
            t("Air filter (induction)", "replace", "filters", km=60000, months=48, ref=ref, notes="More often in dusty or polluted conditions."),
            t("Timing belt, tensioner & water pump", "replace", "engine", km=175000, months=120, ref=N("peugeotforums.com"),
              notes="1.5 BlueHDi: about 175,000 km or 10 years according to secondary sources. Ask the dealer with your VIN and edit this item."),
            DPF,
        ]
    out.append(t("Brake fluid", "replace", "brakes", months=24, ref=ref, spec="DOT 4"))
    return out + car_owner()


STL_SRC = F("src_haynes", "Peugeot 208 (2019–2025)")
STL_URLS = [HAYNES_URL + "peugeot-208-2019-2025",
            "https://www.ad.fr/guides/guide-conseil/distribution/courroie-de-distribution-208-quand-la-changer-et-a-quel-prix"]
STL_NOTE = "Intervals are 'whichever comes first'. Peugeot, Citroën and Opel share the same 1.2 PureTech and 1.5 BlueHDi engines and service plan."
STL_OIL_P = [s("Fluids", "Engine oil", N("PSA B71 2312 (0W-30) · B71 2010 (0W-20)"))]
STL_OIL_D = [s("Fluids", "Engine oil", N("PSA B71 2312 (0W-30) · B71 2290 (5W-30)"))]


def stl_car(tid, make, model, aliases, gen, years, fuel, generic=False, make_aliases=None):
    gen_text = ("Brand-wide plan · " + fuel) if generic else F("gen_" + fuel, gen)
    return car(tid, make, model, aliases, gen_text, years, fuel, stellantis_tasks(fuel),
               STL_OIL_P if fuel == "petrol" else STL_OIL_D, STL_SRC, STL_URLS, STL_NOTE, generic=generic, make_aliases=make_aliases)


OPEL = ["vauxhall"]
stl_cars = [
    stl_car("peugeot-208-2-petrol", "Peugeot", N("208"), ["208", "208 ii", "208 2", "208 puretech", "e-208"], N("II (2019+) · 1.2 PureTech"), (2019, None), "petrol"),
    stl_car("peugeot-208-2-diesel", "Peugeot", N("208"), ["208", "208 ii", "208 2", "208 bluehdi"], N("II (2019+) · 1.5 BlueHDi"), (2019, None), "diesel"),
    stl_car("peugeot-2008-2-petrol", "Peugeot", N("2008"), ["2008", "2008 ii", "2008 2", "2008 puretech"], N("II (2019+) · 1.2 PureTech"), (2019, None), "petrol"),
    stl_car("peugeot-generic-petrol", "Peugeot", ALL, [], None, (None, None), "petrol", generic=True),
    stl_car("peugeot-generic-diesel", "Peugeot", ALL, [], None, (None, None), "diesel", generic=True),
    stl_car("citroen-c3-petrol", "Citroën", N("C3"), ["c3", "c3 iii", "c3 3", "c3 puretech"], N("III (2016–2024) · 1.2 PureTech"), (2016, 2024), "petrol"),
    stl_car("citroen-generic-petrol", "Citroën", ALL, [], None, (None, None), "petrol", generic=True),
    stl_car("citroen-generic-diesel", "Citroën", ALL, [], None, (None, None), "diesel", generic=True),
    stl_car("opel-corsa-f-petrol", "Opel", N("Corsa"), ["corsa", "corsa f", "corsa 2019", "corsa puretech"], N("F (2019+) · 1.2"), (2019, None), "petrol", make_aliases=OPEL),
    stl_car("opel-generic-petrol", "Opel", ALL, [], None, (None, None), "petrol", generic=True, make_aliases=OPEL),
    stl_car("opel-generic-diesel", "Opel", ALL, [], None, (None, None), "diesel", generic=True, make_aliases=OPEL),
]

# ---------------------------------------------------------------- Toyota
def toyota_tasks():
    ref = "Toyota maintenance schedule — Europe (Yaris, 2017)"
    sec = N("carwiki.de")
    out = [t("Regular service: engine oil & filter", "replace", "oil", km=15000, months=12, ref=ref,
             notes="Toyota Europe: every 15,000 km or every year.")]
    out += car_checks(15000, 12, ref)
    out += [
        t("Hybrid system check", "inspect", "electrical", km=15000, months=12, ref=sec,
          notes="Hybrid models: Toyota checks the hybrid battery and system at each service (it also keeps the extended battery cover active)."),
        t("Cabin (pollen / odour) filter", "replace", "filters", km=45000, months=36, ref=sec),
        t("Air filter (induction)", "replace", "filters", km=45000, months=36, ref=sec, notes="More often in dusty or polluted conditions."),
        t("Spark plugs", "replace", "ignition", km=60000, months=48, ref=sec,
          notes="Some engines have a longer interval (up to 90,000 km): check your service booklet."),
        t("Brake fluid", "replace", "brakes", months=24, ref=ref, spec=N("DOT 3 / DOT 4")),
        t("Coolant: drain, flush & refill", "replace", "cooling", km=90000, first_km=150000, ref=ref,
          notes="Toyota Super Long Life Coolant (pink): first at 150,000 km, then every 90,000 km."),
    ]
    return out + car_owner()


TOY_SRC = F("src_toyota", "Yaris")
TOY_URLS = ["https://www.toyota-tech.eu/MS/PDFS/0987cdaa5d81412da314c963e3b45482.pdf", "https://carwiki.de/?p=69398",
            "https://mag.toyota.co.uk/toyota-yaris-servicing-all-you-need-to-know"]
TOY_NOTE = "Toyota petrol and hybrid engines have a timing chain. Filters and spark plugs come from a secondary source: confirm them with your service booklet."
TOY_OIL = [s("Fluids", "Engine oil", N("SAE 0W-16 / 0W-20"))]
toyota_cars = [
    car("toyota-yaris-4-hybrid", "Toyota", N("Yaris"), ["yaris", "yaris 4", "yaris iv", "yaris hybrid", "yaris xp21", "gr yaris"],
        F("gen_hybrid", N("XP21 (2020+)")), (2020, None), "hybrid", toyota_tasks(), TOY_OIL, TOY_SRC, TOY_URLS, TOY_NOTE),
    car("toyota-yaris-cross-hybrid", "Toyota", N("Yaris Cross"), ["yaris cross", "yariscross"],
        F("gen_hybrid", N("2021+")), (2021, None), "hybrid", toyota_tasks(), TOY_OIL, TOY_SRC, TOY_URLS, TOY_NOTE),
    car("toyota-generic-hybrid", "Toyota", ALL, [], "Brand-wide plan · hybrid & petrol", (None, None), "hybrid", toyota_tasks(),
        TOY_OIL, TOY_SRC, TOY_URLS, TOY_NOTE, generic=True),
]

# ---------------------------------------------------------------- Fiat
def fiat_tasks(belt):
    ref = "Fiat maintenance plan (motori.quotidiano.net)"
    out = [t("Regular service: engine oil & filter", "replace", "oil", km=15000, months=12, ref=ref,
             notes="Fiat: every 15,000 km or every year.")]
    out += car_checks(15000, 12, ref)
    out += [
        t("Cabin (pollen / odour) filter", "replace", "filters", km=30000, months=24, ref=ref, notes="Fiat: at every second service."),
        t("Air filter (induction)", "replace", "filters", km=30000, months=24, ref=ref, notes="Fiat: at every second service."),
        t("Spark plugs", "replace", "ignition", km=30000, months=24, ref=ref, notes="Fiat: at every second service."),
        t("Brake fluid", "replace", "brakes", months=24, ref=ref, spec="DOT 4"),
    ]
    if belt:
        out.append(t("Timing belt, tensioner & idlers", "replace", "engine", km=120000, months=72, ref=ref,
                     notes="1.2 8V FIRE (petrol and LPG): 120,000 km or 6 years; some sources say 100,000 km or 5 years. The 1.0 Hybrid (FireFly) has a chain: delete this item."))
    out.append(t("Auxiliary drive belt", "replace", "engine", km=240000, months=96, ref=ref,
                 notes="1.0 Hybrid: check after 8 years, replace at 240,000 km."))
    return out + car_owner()


FIAT_SRC = F("src_fiat", "Fiat 500")
FIAT_URLS = ["https://motori.quotidiano.net/comefare/manutenzione-ordinaria-fiat-500.htm", HAYNES_URL + "fiat-panda-2011-2025"]
FIAT_NOTE = "Plan for the 1.0 Hybrid (FireFly) and 1.2 FIRE / LPG engines. The 0.9 TwinAir uses 30,000 km or 2 years (Haynes): edit the items if yours is a TwinAir."
fiat_cars = [
    car("fiat-panda-3-petrol", "Fiat", N("Panda"), ["panda", "panda 3", "panda iii", "panda hybrid", "panda cross", "panda city cross", "new panda"],
        F("gen_petrol", N("319 (2012+) · 1.0 Hybrid / 1.2 / 0.9 TwinAir")), (2012, None), "petrol", fiat_tasks(True), [], FIAT_SRC, FIAT_URLS, FIAT_NOTE),
    car("fiat-500-petrol", "Fiat", N("500"), ["500", "500c", "500 hybrid", "500 dolcevita", "cinquecento"],
        F("gen_petrol", N("312 (2007+) · 1.0 Hybrid / 1.2 / 0.9 TwinAir")), (2007, None), "petrol", fiat_tasks(True), [], FIAT_SRC, FIAT_URLS, FIAT_NOTE),
    car("fiat-generic-petrol", "Fiat", ALL, [], "Brand-wide plan · petrol", (None, None), "petrol", fiat_tasks(True), [], FIAT_SRC, FIAT_URLS, FIAT_NOTE, generic=True),
]

# ====================================================================== Output
SCHEDULES = ([z400] + honda_bikes + [honda_generic] + yamaha_bikes + [yamaha_generic] + bmw_bikes + [bmw_generic]
             + kawasaki_bikes + [kawasaki_generic] + suzuki_bikes + [suzuki_generic] + ktm_bikes + [ktm_generic]
             + triumph_bikes + [triumph_generic] + ducati_bikes + [ducati_generic]
             + [fiesta_mk8_diesel, fiesta_mk8_petrol, fiesta_mk7_diesel, fiesta_mk7_petrol] + ford_more
             + vag_cars + bmw_cars + ren_cars + stl_cars + toyota_cars + fiat_cars)


def texts(tpl):
    out = [tpl["model"], tpl.get("source"), tpl.get("disclaimer"), tpl.get("generation")]
    for x in tpl["tasks"]:
        out += [x["title"], x.get("notes"), x.get("spec"), x.get("sourceRef")]
    for x in tpl.get("specs", []):
        out += [x["group"], x["title"], x["value"]]
    return [x for x in out if x]


def main():
    missing = set()
    ids = set()
    index = {"schedules": [], "translations": {l: {} for l in LANGS}}
    files = {}
    for tpl in SCHEDULES:
        assert tpl["id"] not in ids, tpl["id"]
        ids.add(tpl["id"])
        tpl = {k: v for k, v in tpl.items() if v is not None}
        trans = {l: {} for l in LANGS}
        for text in texts(tpl):
            found = translation(text)
            if not found:
                missing.add(text)
                continue
            for l in LANGS:
                trans[l][text] = found[l]
        tpl["translations"] = trans
        tpl["version"] = int(hashlib.sha1(json.dumps(tpl, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:8], 16)
        files[tpl["id"]] = tpl
        entry = {k: tpl[k] for k in ["id", "make", "makeAliases", "model", "aliases", "generation", "yearFrom", "yearTo",
                                      "kind", "fuel", "generic"] if k in tpl}
        entry.update(tasks=len(tpl["tasks"]), specs=len(tpl.get("specs", [])), version=tpl["version"])
        index["schedules"].append(entry)
        for text in [tpl["model"], tpl.get("generation")]:
            if text and text in trans["it"]:
                for l in LANGS:
                    index["translations"][l][text] = trans[l][text]
    if missing:
        print(json.dumps(sorted(missing), ensure_ascii=False, indent=1))
        sys.exit(f"{len(missing)} texts have no translation: add them to scripts/catalog_i18n.py")
    os.makedirs(os.path.join(OUT, "schedules"), exist_ok=True)
    for tid, tpl in files.items():
        with open(os.path.join(OUT, "schedules", f"{tid}.json"), "w", encoding="utf-8") as f:
            json.dump(tpl, f, ensure_ascii=False, indent=1)
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    stale = [n for n in os.listdir(os.path.join(OUT, "schedules")) if n[:-5] not in files]
    print(f"{len(files)} schedules ({sum(1 for x in files.values() if x.get('generic'))} brand-wide plans) written to catalog/")
    if stale:
        print("Not in the catalog any more (delete them):", ", ".join(stale))


main()
