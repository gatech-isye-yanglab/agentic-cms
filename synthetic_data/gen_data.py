"""
gen_data.py — Populate the schema-exact synthetic DB.

Output modes:
    --sqlite PATH    create/overwrite a SQLite DB at PATH and load into it
    --csv DIR        write one CSV per table into DIR (for MySQL LOAD DATA)
    --dump PATH      write a single SQL INSERT dump (portable, MySQL-ready)

Any combination of the three is valid.

Scale is controlled by:
    --n-patients N   total synthetic beneficiaries (default: 10000)
    --n-patients all use every DE-SynPUF Sample 1 beneficiary (~116K)

Run from this directory:
    python3 gen_data.py --sqlite synthetic_db.sqlite
"""

from __future__ import annotations

import argparse
import csv
import os
import random
import sqlite3
import sys
from datetime import date, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_SQLITE = os.path.join(HERE, "schema_sqlite.sql")
SCHEMA_MYSQL  = os.path.join(HERE, "schema_mysql.sql")
SYNPUF_BENE   = os.path.join(
    HERE, "de_synpuf_2008_2010",
    "DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv",
)

SEED = 42

# ── State → state_key lookup ─────────────────────────────────────────────────
# SE states are keyed 1..7 to match the existing toy_db/seed_mysql.py convention.
SE_STATES = ["AL", "FL", "GA", "MS", "NC", "SC", "TN"]
OTHER_STATES = [
    "AK","AZ","AR","CA","CO","CT","DE","HI","ID","IL","IN","IA","KS","KY","LA",
    "ME","MD","MA","MI","MN","MO","MT","NE","NV","NH","NJ","NM","NY","ND","OH",
    "OK","OR","PA","RI","SD","TX","UT","VT","VA","WA","WV","WI","WY","DC",
]
TERRITORIES = ["PR","VI","GU","AS","MP","00","XX","ZZ","YY"]  # make up to 60

STATE_CODES = SE_STATES + OTHER_STATES + TERRITORIES
STATE_KEYS: dict[str, int] = {s: i + 1 for i, s in enumerate(STATE_CODES)}

# Mask for selecting SE vs non-SE.
IN_SE = set(SE_STATES)

# ── ICD code pools ───────────────────────────────────────────────────────────
# Diabetes diagnosis codes (ICD-9 25x, ICD-10 E10/E11 families).
ICD9_DIAB = [
    "25000","25001","25002","25010","25011","25012",
    "25020","25021","25022","25030","25040","25041",
    "25050","25060","25061","25070","25071","25080","25090",
]
ICD10_DIAB = [
    "E1010","E1011","E1110","E1111","E109","E119","E104","E114",
    "E102","E112","E088","E089","E098","E1000","E1100",
]
DIAB_ALL = ICD9_DIAB + ICD10_DIAB

# Non-diabetes codes for negative controls.
NON_DIAB = [
    "J189","I10","Z0000","M5450","K219","J069","N390","R0789",
    "A090","B342","C3490","D649","F329","G935","I2510","K5909",
]

# HCPCS pools for LINE_PRCDR_CD seeding.  Each pool is exposed to a fraction
# of beneficiaries via `pick_treatment_type` so the resulting distribution in
# taf_other_services_line has realistic diversity (~40–50 distinct codes) and
# non-zero oncology signal for the lung-cancer pipeline (KNOWN_GAPS.md §1).
#
# Sources:
#   - HCPCS_CHEMO / HCPCS_IMMUNO: pipelines/lung_cancer/reference/build_reference_tables.sql
#     (12 chemo + 12 immuno codes — permanent J-codes + pre-approval C-codes)
#   - HCPCS_DIAB / HCPCS_DIAB_TREATMENT: pipelines/diabetes/reference/hcpcs_code.sql
#   - HCPCS_GENERIC: common E/M, imaging, lab codes (office visits etc.)

# Lung-cancer chemotherapy cytotoxics + anti-VEGF targeted therapy.
HCPCS_CHEMO = [
    "J9060","J9045","J9267","J9264","J9171","J9201","J9305",
    "J9390","J9181","J9206","J9035","J9308",
]

# Lung-cancer immunotherapy: checkpoint inhibitors (J permanent + C pre-approval).
HCPCS_IMMUNO = [
    "J9228","J9299","J9271","J9022","J9173","J9023",
    "C9027","C9284","C9453","C9483","C9491","C9492",
]

# Diabetes self-management / insulin / glucose monitoring.
HCPCS_DIAB = [
    "G0108","G0109","J1815","J1817","J1818","J1819",
    "E0607","E0784","A4253","A4259",
    "A5500","A5501","A5510","A5512",
    "S9353","S9355",
]

# Generic outpatient: office visits (E/M), imaging, lab panels.
HCPCS_GENERIC = [
    "99213","99214","99203","99204","99215","99212","99211",
    "93000","93010","80053","85025","80061","85610","80047",
    "36415","99173","99406","99407","99408",
]

# Back-compat aliases for anything that used the pre-Phase-F names.
HCPCS_OTHER = HCPCS_GENERIC

# National drug codes for insulin / metformin / other common drugs.
NDC_DIAB = [
    "00002751501",  # Humulin R
    "00002831501",  # Humulin N
    "00088222033",  # Lantus
    "00378183101",  # Metformin
    "00093717001",  # Glipizide
    "00054327463",  # Glyburide
]
NDC_OTHER = [
    "00003093231","00054400099","00093014801","00378011101","00781178501",
]


# ── Helpers ─────────────────────────────────────────────────────────────────

def d_iso(d: date) -> str:
    return d.strftime("%Y-%m-%d")


def rand_date(y0: int, y1: int, rng: random.Random) -> date:
    s, e = date(y0, 1, 1), date(y1, 12, 31)
    return s + timedelta(days=rng.randint(0, (e - s).days))


def bucket_for(idx: int, total: int) -> str:
    r = (idx - 1) / total
    for thr, t in [(.40, 'positive'), (.60, 'single'), (.75, 'long_gap'),
                   (.85, 'wrong_state'), (.95, 'no_diabetes'), (1., 'ambiguous')]:
        if r < thr:
            return t
    return 'positive'


def era_for(rng: random.Random) -> int:
    """Return 1, 2, or 3 — era assignment distributed roughly 40/25/35.

    Drawn from `rng` rather than `idx` so bucket and era are independent —
    otherwise a patient's position-in-list forces a correlated bucket × era.
    """
    r = rng.random()
    if r < 0.40:
        return 1
    if r < 0.65:
        return 2
    return 3


def pick_state(bucket: str, rng: random.Random) -> tuple[str, int]:
    if bucket == 'wrong_state':
        s = rng.choice(OTHER_STATES)
    else:
        s = rng.choice(SE_STATES)
    return s, STATE_KEYS[s]


def pick_treatment_type(rng: random.Random) -> str:
    """Patient-level oncology treatment-arm assignment.

    Returns one of: 'generic', 'chemo', 'immuno', 'mixed'.
    Generic = no oncology HCPCS (most patients).  Chemo / immuno / mixed
    route the patient's outpatient-line HCPCS draws through the oncology
    pools so the lung-cancer pipeline's chemo/immuno extraction finds
    non-zero claims.  "mixed" exercises the v4_table clean-exposure rule.

    Distribution picked to give the pipeline meaningful arm sizes without
    making the synthetic population implausibly oncology-heavy — ~12 %
    chemo+immuno overall, close to real-world CMS outpatient-oncology
    frequencies.
    """
    r = rng.random()
    if r < 0.85:
        return 'generic'
    if r < 0.92:
        return 'chemo'
    if r < 0.97:
        return 'immuno'
    return 'mixed'


def pick_line_hcpcs(treatment_type: str, bucket: str, rng: random.Random) -> str:
    """Return one LINE_PRCDR_CD for a single outpatient-line row.

    Even oncology patients have non-oncology visits, so chemo/immuno
    patients draw from the oncology pool ~60 % of the time and from
    generic the rest.  Diabetes-positive patients (anything other than
    no_diabetes) have a small chance of drawing a diabetes-specific
    HCPCS so the diabetes treatment arm is exercised too.
    """
    if treatment_type == 'chemo':
        if rng.random() < 0.60:
            return rng.choice(HCPCS_CHEMO)
    elif treatment_type == 'immuno':
        if rng.random() < 0.60:
            return rng.choice(HCPCS_IMMUNO)
    elif treatment_type == 'mixed':
        r = rng.random()
        if r < 0.40:
            return rng.choice(HCPCS_CHEMO)
        if r < 0.80:
            return rng.choice(HCPCS_IMMUNO)
    # Generic or the "other visit" branch of an oncology patient.
    if bucket != 'no_diabetes' and rng.random() < 0.20:
        return rng.choice(HCPCS_DIAB)
    return rng.choice(HCPCS_GENERIC)


def pick_diag(era: int, bucket: str, rng: random.Random) -> str:
    """Era 1 (pre-2013) → ICD-9 only; Era 2 spans the ICD-9/10 cutover; Era 3 → ICD-10."""
    if bucket in ('no_diabetes',):
        return rng.choice(NON_DIAB)
    if era == 1:
        return rng.choice(ICD9_DIAB)
    if era == 2:
        return rng.choice(DIAB_ALL)
    return rng.choice(ICD10_DIAB)


def era_window(era: int) -> tuple[int, int]:
    return {1: (2005, 2012), 2: (2013, 2015), 3: (2016, 2018)}[era]


# ── Patient pool ─────────────────────────────────────────────────────────────

def load_desynpuf_ids(limit: int | None) -> list[str]:
    """Yield DESYNPUF_IDs for use as BENE_ID material."""
    ids = []
    with open(SYNPUF_BENE) as f:
        r = csv.DictReader(f)
        for row in r:
            ids.append(row["DESYNPUF_ID"])
            if limit is not None and len(ids) >= limit:
                break
    return ids


# ── Column ordering (from columns_formats.csv) ───────────────────────────────

def load_column_names(csv_path: str) -> dict[str, list[str]]:
    """Return {table_name: [col_name, ...]} in declared order."""
    tables: dict[str, list[tuple[int, str]]] = {}
    with open(csv_path) as f:
        r = csv.DictReader(f)
        for row in r:
            tables.setdefault(row['table_name'], []).append(
                (int(row['column_order']), row['column_name'])
            )
    return {t: [c for _, c in sorted(cols)] for t, cols in tables.items()}


# ── Core: build one patient's row dicts ─────────────────────────────────────

def make_patient_rows(
    idx: int,
    total: int,
    bene_id: str,
    rng: random.Random,
) -> tuple[str, str, dict[str, list[dict]]]:
    """Return (patient_id, bucket, rows_per_table)."""
    era = era_for(rng)
    bucket = bucket_for(idx, total)
    treatment_type = pick_treatment_type(rng)
    state_cd, state_key = pick_state(bucket, rng)
    sex = rng.choice(['1', '2'])  # CMS codes 1=M, 2=F; MAX era uses 'M'/'F' — see below
    max_sex = 'M' if sex == '1' else 'F'
    race = str(rng.randint(1, 5))
    dob = rand_date(1930, 1990, rng)
    patient_id = f"PID{bene_id[:37]}"  # fits varchar(40)
    msis_id = f"MS{bene_id[:30]}"
    y0, y1 = era_window(era)

    rows: dict[str, list[dict]] = {}

    # How many claim dates — drives both claim and bucket semantics.
    if bucket == 'positive':
        d1 = rand_date(y0, y1 - 1, rng)
        gap = rng.randint(30, 700)
        d2 = min(d1 + timedelta(days=gap), date(y1, 12, 31))
        dates = [d1, d2]
    elif bucket == 'single':
        dates = [rand_date(y0, y1, rng)]
    elif bucket == 'long_gap':
        d1 = rand_date(y0, y0, rng)
        d2 = min(d1 + timedelta(days=rng.randint(731, 900)), date(y1, 12, 31))
        dates = [d1, d2]
    elif bucket == 'wrong_state':
        d1 = rand_date(y0, y1 - 1, rng)
        d2 = min(d1 + timedelta(days=rng.randint(60, 500)), date(y1, 12, 31))
        dates = [d1, d2]
    elif bucket == 'no_diabetes':
        dates = [rand_date(y0, y1, rng)]
    else:  # ambiguous: two positive claims with sex that toggles
        d1 = rand_date(y0, y1 - 1, rng)
        d2 = min(d1 + timedelta(days=rng.randint(60, 500)), date(y1, 12, 31))
        dates = [d1, d2]

    # Decide whether patient shows up as inpatient or outpatient this era.
    # 50/50 split, with a small fraction getting both (makes integration tests richer).
    show_inp = rng.random() < 0.55
    show_out = rng.random() < 0.55 if show_inp else True  # always give outpatient if no inp
    show_rx  = rng.random() < 0.30

    diagnoses = [pick_diag(era, bucket, rng) for _ in dates]

    # ── ERA 1/2 demographics (personal_summary / personal_summary1315) ──
    if era == 1:
        rows.setdefault('personal_summary', []).append({
            'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
            'STATE_CD': state_cd, 'state_key': state_key,
            'MAX_YR_DT': y0, 'EL_DOB': d_iso(dob),
            'EL_SEX_CD': max_sex, 'EL_RACE_ETHNCY_CD': race,
            'AGE': y0 - dob.year,
            'RACE_CODE_1': race,
        })
    elif era == 2:
        rows.setdefault('personal_summary1315', []).append({
            'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
            'STATE_CD': state_cd, 'state_key': state_key,
            'MAX_YR_DT': y0, 'EL_DOB': d_iso(dob),
            'EL_SEX_CD': max_sex, 'EL_RACE_ETHNCY_CD': race,
            'AGE': y0 - dob.year,
            'RACE_CODE_1': race,
        })
    else:
        rows.setdefault('taf_demog_elig_base', []).append({
            'PATIENT_ID': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
            'STATE_CD': state_cd, 'STATE_KEY': state_key,
            'SUBMTG_STATE_CD': state_cd,
            'BENE_STATE_CD': state_cd,
            'BIRTH_DT': d_iso(dob),
            'AGE': y0 - dob.year,
            'SEX_CD': max_sex,
            'RACE_ETHNCTY_CD': race,
            'RFRNC_YR': y0,
        })

    # ── Claims ──
    if era == 1:
        if show_inp:
            for i, dt in enumerate(dates):
                sex_i = max_sex
                if bucket == 'ambiguous' and i == 1:
                    sex_i = 'F' if max_sex == 'M' else 'M'
                rows.setdefault('inpatient', []).append({
                    'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'state_key': state_key,
                    'YR_NUM': dt.year, 'EL_DOB': d_iso(dob),
                    'EL_SEX_CD': sex_i, 'EL_RACE_ETHNCY_CD': race,
                    'ADMSN_DT': d_iso(dt),
                    'SRVC_BGN_DT': d_iso(dt),
                    'SRVC_END_DT': d_iso(dt + timedelta(days=rng.randint(1, 5))),
                    'DIAG_CD_1': diagnoses[i],
                    'DIAG_CD_2': rng.choice(NON_DIAB),
                })
        if show_out:
            for i, dt in enumerate(dates):
                rows.setdefault('other_therapy', []).append({
                    'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'state_key': state_key,
                    'YR_NUM': dt.year, 'EL_DOB': d_iso(dob),
                    'EL_SEX_CD': max_sex, 'EL_RACE_ETHNCY_CD': race,
                    'SRVC_BGN_DT': d_iso(dt), 'SRVC_END_DT': d_iso(dt),
                    'DIAG_CD_1': diagnoses[i],
                    'DIAG_CD_2': None,
                })
        if show_rx:
            for dt in dates:
                rows.setdefault('rx', []).append({
                    'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'state_key': state_key,
                    'YR_NUM': dt.year, 'EL_DOB': d_iso(dob),
                    'EL_SEX_CD': max_sex, 'EL_RACE_ETHNCY_CD': race,
                    'PRSCRPTN_FILL_DT': d_iso(dt),
                    'PRSC_WRTE_DT': d_iso(dt - timedelta(days=rng.randint(0, 3))),
                    'NDC': rng.choice(NDC_DIAB if bucket != 'no_diabetes' else NDC_OTHER),
                })
    elif era == 2:
        if show_inp:
            for i, dt in enumerate(dates):
                sex_i = max_sex
                if bucket == 'ambiguous' and i == 1:
                    sex_i = 'F' if max_sex == 'M' else 'M'
                rows.setdefault('inpatient1315', []).append({
                    'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'state_key': state_key,
                    'YR_NUM': dt.year, 'EL_DOB': d_iso(dob),
                    'EL_SEX_CD': sex_i, 'EL_RACE_ETHNCY_CD': race,
                    'ADMSN_DT': d_iso(dt),
                    'SRVC_BGN_DT': d_iso(dt),
                    'SRVC_END_DT': d_iso(dt + timedelta(days=rng.randint(1, 5))),
                    'DIAG_CD_1': diagnoses[i],
                    'DIAG_CD_2': rng.choice(NON_DIAB),
                })
        if show_out:
            for i, dt in enumerate(dates):
                rows.setdefault('other_therapy1315', []).append({
                    'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'state_key': state_key,
                    'YR_NUM': dt.year, 'EL_DOB': d_iso(dob),
                    'EL_SEX_CD': max_sex, 'EL_RACE_ETHNCY_CD': race,
                    'SRVC_BGN_DT': d_iso(dt), 'SRVC_END_DT': d_iso(dt),
                    'DIAG_CD_1': diagnoses[i],
                })
        if show_rx:
            for dt in dates:
                rows.setdefault('rx1315', []).append({
                    'patient_id': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'state_key': state_key,
                    'YR_NUM': dt.year, 'EL_DOB': d_iso(dob),
                    'EL_SEX_CD': max_sex, 'EL_RACE_ETHNCY_CD': race,
                    'PRSCRPTN_FILL_DT': d_iso(dt),
                    'PRSC_WRTE_DT': d_iso(dt - timedelta(days=rng.randint(0, 3))),
                    'NDC': rng.choice(NDC_DIAB if bucket != 'no_diabetes' else NDC_OTHER),
                })
    else:
        if show_inp:
            for i, dt in enumerate(dates):
                clm_id = f"C{bene_id[:10]}I{i}"
                rows.setdefault('taf_inpatient_header', []).append({
                    'PATIENT_ID': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'STATE_KEY': state_key,
                    'SUBMTG_STATE_CD': state_cd, 'CLM_ID': clm_id,
                    'ADJDCTN_DT': d_iso(dt),
                    'ADMSN_DT': d_iso(dt),
                    'SRVC_BGN_DT': d_iso(dt),
                    'SRVC_END_DT': d_iso(dt + timedelta(days=rng.randint(1, 5))),
                    'DSCHRG_DT': d_iso(dt + timedelta(days=rng.randint(1, 5))),
                    'BIRTH_DT': d_iso(dob),
                    'DGNS_CD_1': diagnoses[i],
                    'DGNS_CD_2': rng.choice(NON_DIAB),
                    'RFRNC_YR': dt.year,
                })
                # 1–3 lines per header.  taf_inpatient_line has no LINE_PRCDR_CD
                # column (inpatient procedures travel as DGNS_POA / DRG codes on
                # the header, not as HCPCS on the line), but the LINE_SRVC_*_DT
                # fields still need real dates so they don't land as the
                # '0000-00-00' sentinel that trips NO_ZERO_DATE in strict mode.
                for lnum in range(1, rng.randint(1, 4) + 1):
                    rows.setdefault('taf_inpatient_line', []).append({
                        'PATIENT_ID': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                        'STATE_CD': state_cd, 'STATE_KEY': state_key,
                        'SUBMTG_STATE_CD': state_cd, 'CLM_ID': clm_id,
                        'LINE_NUM': lnum,
                        'ADJDCTN_DT': d_iso(dt),
                        'LINE_SRVC_BGN_DT': d_iso(dt),
                        'LINE_SRVC_END_DT': d_iso(dt),
                        'RFRNC_YR': dt.year,
                    })
        if show_out:
            for i, dt in enumerate(dates):
                clm_id = f"C{bene_id[:10]}O{i}"
                rows.setdefault('taf_other_services_header', []).append({
                    'PATIENT_ID': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'STATE_KEY': state_key,
                    'SUBMTG_STATE_CD': state_cd, 'CLM_ID': clm_id,
                    'ADJDCTN_DT': d_iso(dt),
                    'SRVC_BGN_DT': d_iso(dt),
                    'SRVC_END_DT': d_iso(dt),
                    'BIRTH_DT': d_iso(dob),
                    'DGNS_CD_1': diagnoses[i],
                    'RFRNC_YR': dt.year,
                })
                for lnum in range(1, rng.randint(1, 3) + 1):
                    rows.setdefault('taf_other_services_line', []).append({
                        'PATIENT_ID': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                        'STATE_CD': state_cd, 'STATE_KEY': state_key,
                        'SUBMTG_STATE_CD': state_cd, 'CLM_ID': clm_id,
                        'LINE_NUM': lnum,
                        'ADJDCTN_DT': d_iso(dt),
                        'LINE_SRVC_BGN_DT': d_iso(dt),
                        'LINE_SRVC_END_DT': d_iso(dt),
                        'LINE_PRCDR_CD_DT': d_iso(dt),
                        'LINE_PRCDR_CD': pick_line_hcpcs(treatment_type, bucket, rng),
                        'LINE_PRCDR_CD_SYS': 'H5',  # HCPCS (CMS code system 5)
                        'RFRNC_YR': dt.year,
                    })
        if show_rx:
            for dt in dates:
                clm_id = f"C{bene_id[:10]}R{dt.year}"
                rows.setdefault('taf_rx_header', []).append({
                    'PATIENT_ID': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'STATE_KEY': state_key,
                    'SUBMTG_STATE_CD': state_cd, 'CLM_ID': clm_id,
                    'ADJDCTN_DT': d_iso(dt),
                    'MDCD_PD_DT': d_iso(dt),
                    'RFRNC_YR': dt.year,
                })
                rows.setdefault('taf_rx_line', []).append({
                    'PATIENT_ID': patient_id, 'BENE_ID': bene_id, 'MSIS_ID': msis_id,
                    'STATE_CD': state_cd, 'STATE_KEY': state_key,
                    'SUBMTG_STATE_CD': state_cd, 'CLM_ID': clm_id,
                    'LINE_NUM': 1,
                    'ADJDCTN_DT': d_iso(dt),
                    'RFRNC_YR': dt.year,
                })

    return patient_id, bucket, rows


# ── Writers ──────────────────────────────────────────────────────────────────

def _row_to_tuple(row: dict, col_names: list[str]) -> tuple:
    return tuple(row.get(c) for c in col_names)


class SqliteWriter:
    def __init__(self, path: str, columns: dict[str, list[str]]):
        # Truncate rather than unlink — some sandboxed filesystems refuse
        # `os.remove` on their own files.  `open(..., "w")` always succeeds
        # as long as the caller owns the directory entry.
        if os.path.exists(path):
            try:
                os.remove(path)
            except PermissionError:
                open(path, "wb").close()
        # Also remove any stale WAL/journal sidecar files.
        for suffix in ("-journal", "-wal", "-shm"):
            side = path + suffix
            if os.path.exists(side):
                try:
                    os.remove(side)
                except PermissionError:
                    open(side, "wb").close()
        self.conn = sqlite3.connect(path)
        # Keep default rollback journal — sandbox filesystems sometimes refuse
        # the WAL's shm mapping.  OFF sync is fine: we can re-run the generator
        # if it crashes.
        self.conn.execute("PRAGMA synchronous = OFF")
        self.conn.execute("PRAGMA temp_store = MEMORY")
        self.conn.execute("PRAGMA cache_size = -64000")  # 64 MB page cache
        # Apply schema
        with open(SCHEMA_SQLITE) as f:
            self.conn.executescript(f.read())
        self.columns = columns
        # Pre-compute INSERT templates
        self.inserts = {
            t: 'INSERT INTO "' + t + '" (' + ','.join(f'"{c}"' for c in cols)
               + ') VALUES (' + ','.join('?' * len(cols)) + ')'
            for t, cols in columns.items()
        }
        self.buf: dict[str, list[tuple]] = {t: [] for t in columns}
        self.BATCH = 5000

    def add(self, table: str, row: dict):
        self.buf[table].append(_row_to_tuple(row, self.columns[table]))
        if len(self.buf[table]) >= self.BATCH:
            self.flush(table)

    def flush(self, table: str):
        if not self.buf[table]:
            return
        self.conn.executemany(self.inserts[table], self.buf[table])
        self.buf[table].clear()

    def flush_all(self):
        for t in list(self.buf):
            self.flush(t)
        self.conn.commit()

    def close(self):
        self.flush_all()
        self.conn.close()


class CsvWriter:
    def __init__(self, dir_: str, columns: dict[str, list[str]]):
        os.makedirs(dir_, exist_ok=True)
        self.dir = dir_
        self.columns = columns
        self.files = {}
        self.writers = {}
        for t, cols in columns.items():
            f = open(os.path.join(dir_, f"{t}.csv"), "w", newline="")
            w = csv.writer(f)
            w.writerow(cols)
            self.files[t] = f
            self.writers[t] = w

    def add(self, table: str, row: dict):
        self.writers[table].writerow(
            ["" if v is None else v for v in _row_to_tuple(row, self.columns[table])]
        )

    def close(self):
        for f in self.files.values():
            f.close()


# ── Meta-table fillers ───────────────────────────────────────────────────────

def fill_meta(
    writers: list,
    columns: dict[str, list[str]],
    patient_counts: dict[tuple[str, str, int], int],
    patient_line_counts: dict[tuple[str, str, int], int],
    all_states: list[str],
):
    """Populate data_years, state_codes, table_counts, and the two per-state
    count tables.  patient_counts is keyed by (tablename, state_code, year).
    """
    # data_years — covers MAX era (2005-2015) + TAF era as loaded.  Range
    # extended to 2023 so the RIF Tier-2a loader's claims (Synthea
    # generates most oncology claims in 2019+) are visible to the cursor
    # in step1 extraction procedures.
    for y in range(2005, 2024):
        for w in writers:
            w.add('data_years', {'year_num': y})
    # state_codes
    for s in STATE_CODES:
        for w in writers:
            w.add('state_codes', {'state_code': s, 'state_key': STATE_KEYS[s]})
    # messagelog — a single audit row so the table is non-empty
    for w in writers:
        w.add('messagelog', {
            'logtime': '2026-04-21 12:00:00',
            'sender': 'gen_data.py',
            'message': 'Synthetic DB generated — do not use on real patients.',
        })
    # table_counts — will be re-filled post-load with actual counts.
    # Placeholder keeps row-count=1 for now.
    for tbl in columns:
        for w in writers:
            w.add('table_counts', {'tablename': tbl, 'numrows': 0})
    # table_counts_by_state — one row per (table, state, year) partition observed
    for (tbl, state, year), n in sorted(patient_counts.items()):
        for w in writers:
            w.add('table_counts_by_state', {
                'tablename': tbl, 'numrows': n,
                'state_key': STATE_KEYS[state],
                'state_year': year,
            })
    # table_osline_counts_by_state — for TAF line tables only.
    for (tbl, state, year), n in sorted(patient_line_counts.items()):
        for w in writers:
            w.add('table_osline_counts_by_state', {
                'tablename': tbl, 'numrows': n,
                'state_key': STATE_KEYS[state],
                'state_year': year,
            })


# ── Driver ───────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sqlite', help='path to SQLite DB to (re)build')
    ap.add_argument('--csv',    help='directory for per-table CSV files')
    ap.add_argument('--dump',   help='path for a single MySQL INSERT dump')
    ap.add_argument('--n-patients', default='10000',
                    help='integer or "all" for every DE-SynPUF beneficiary')
    ap.add_argument('--seed', type=int, default=SEED)
    args = ap.parse_args()

    if not any([args.sqlite, args.csv, args.dump]):
        ap.error("need at least one output mode (--sqlite / --csv / --dump)")

    rng = random.Random(args.seed)
    random.seed(args.seed)

    print(f"Loading DE-SynPUF beneficiary pool from {SYNPUF_BENE}")
    if args.n_patients == 'all':
        ids = load_desynpuf_ids(None)
    else:
        n = int(args.n_patients)
        ids = load_desynpuf_ids(n)
    # De-dupe & shuffle for era distribution.
    ids = list(dict.fromkeys(ids))
    rng.shuffle(ids)
    total = len(ids)
    print(f"  {total:,} unique beneficiaries selected")

    columns = load_column_names(os.path.join(HERE, "columns_formats.csv"))

    writers = []
    if args.sqlite:
        writers.append(SqliteWriter(args.sqlite, columns))
    if args.csv:
        writers.append(CsvWriter(args.csv, columns))
    # --dump is emitted from CSV after the run (see bottom).

    # patient counts for table_counts_by_state
    pc:  dict[tuple[str, str, int], int] = {}
    plc: dict[tuple[str, str, int], int] = {}
    bucket_dist: dict[str, int] = {}

    print("Generating rows ...")
    for i, bene_id in enumerate(ids, 1):
        _, bucket, rows = make_patient_rows(i, total, bene_id, rng)
        bucket_dist[bucket] = bucket_dist.get(bucket, 0) + 1
        for tbl, rs in rows.items():
            for r in rs:
                for w in writers:
                    w.add(tbl, r)
                year = (r.get('YR_NUM') or r.get('RFRNC_YR') or
                        r.get('MAX_YR_DT') or 2010)
                state = r.get('STATE_CD') or r.get('state_cd') or 'XX'
                if tbl.endswith('_line'):
                    plc[(tbl, state, int(year))] = plc.get((tbl, state, int(year)), 0) + 1
                else:
                    pc[(tbl, state, int(year))] = pc.get((tbl, state, int(year)), 0) + 1
        if i % 5000 == 0:
            print(f"  {i:>6,} / {total:,}")
            # Opportunistic flush + commit on SqliteWriter to keep memory down.
            for w in writers:
                if isinstance(w, SqliteWriter):
                    w.flush_all()
                    w.conn.commit()

    # Fill meta tables.
    print("Filling meta tables ...")
    fill_meta(writers, columns, pc, plc, STATE_CODES)

    # Finalise.
    for w in writers:
        w.close()

    # Re-compute table_counts with actual row counts if SQLite target exists.
    if args.sqlite:
        conn = sqlite3.connect(args.sqlite)
        cur = conn.cursor()
        # Clear placeholder
        cur.execute("DELETE FROM table_counts")
        for t in sorted(columns):
            n = cur.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
            cur.execute("INSERT INTO table_counts (tablename, numrows) VALUES (?, ?)", (t, n))
        conn.commit()
        # Print summary.
        print("\n── Row counts ────────────────────────────────────────────")
        grand = 0
        for t in sorted(columns):
            n = cur.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
            grand += n
            print(f"  {t:<36} {n:>12,}")
        print(f"  {'GRAND TOTAL':<36} {grand:>12,}")
        conn.close()

    print(f"\nBucket distribution: {bucket_dist}")

    # MySQL INSERT dump (if requested) — derived from CSV files, which must
    # already have been produced; if not, use an in-memory SQLite to export.
    if args.dump:
        src_conn = None
        if args.sqlite:
            src_conn = sqlite3.connect(args.sqlite)
        elif args.csv:
            # Build a temp in-memory SQLite from CSVs so we can reuse dump code.
            src_conn = sqlite3.connect(':memory:')
            with open(SCHEMA_SQLITE) as f:
                src_conn.executescript(f.read())
            for t, cols in columns.items():
                with open(os.path.join(args.csv, f"{t}.csv")) as f:
                    r = csv.reader(f)
                    next(r)  # header
                    placeholders = ",".join("?" * len(cols))
                    ins = f'INSERT INTO "{t}" VALUES ({placeholders})'
                    src_conn.executemany(ins, (
                        tuple(None if v == "" else v for v in row) for row in r
                    ))
            src_conn.commit()
        else:
            print("WARNING: --dump without --sqlite or --csv requires generation first; re-run with --sqlite or --csv", file=sys.stderr)
            return
        emit_mysql_dump(src_conn, columns, args.dump)
        src_conn.close()
        print(f"Wrote MySQL INSERT dump to {args.dump}")


def emit_mysql_dump(conn: sqlite3.Connection, columns: dict[str, list[str]], out_path: str):
    """Write INSERT statements compatible with MySQL.  Dates stay quoted as ISO
    strings (MySQL auto-casts varchar→date on load).
    """
    cur = conn.cursor()
    with open(out_path, "w") as f:
        f.write("-- MySQL data dump — synthetic DB\n")
        f.write("-- Run after schema_mysql.sql.  USE cms_source; first.\n")
        f.write("USE cms_source;\n")
        f.write("SET FOREIGN_KEY_CHECKS=0;\n")
        for t in sorted(columns):
            cols = columns[t]
            col_list = ",".join(f"`{c}`" for c in cols)
            cur.execute(f'SELECT {",".join([chr(34)+c+chr(34) for c in cols])} FROM "{t}"')
            batch = []
            BATCH = 1000
            for row in cur:
                vals = []
                for v in row:
                    if v is None:
                        vals.append("NULL")
                    elif isinstance(v, (int, float)):
                        vals.append(str(v))
                    else:
                        s = str(v).replace("\\", "\\\\").replace("'", "\\'")
                        vals.append(f"'{s}'")
                batch.append("(" + ",".join(vals) + ")")
                if len(batch) >= BATCH:
                    f.write(f"INSERT INTO `{t}` ({col_list}) VALUES\n")
                    f.write(",\n".join(batch))
                    f.write(";\n")
                    batch.clear()
            if batch:
                f.write(f"INSERT INTO `{t}` ({col_list}) VALUES\n")
                f.write(",\n".join(batch))
                f.write(";\n")
        f.write("SET FOREIGN_KEY_CHECKS=1;\n")


if __name__ == "__main__":
    main()
