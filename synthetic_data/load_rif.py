"""
load_rif.py — transform CMS Synthetic RIF 2023 (Synthea-generated) into
the schema-exact TAF tables used by `cms_source`.

This is the Tier 2a loader: realistic Synthea cohort + timelines +
demographics + prescription events, with a thin Python overlay that
injects oncology HCPCS codes (which Synthea's RIF 2023 does not model)
for the subset of beneficiaries Synthea assigned a lung-cancer ICD code.

Output: per-TAF-table CSVs written into ./csv/ (overwriting anything
`gen_data.py` put there for the same table).  MAX-era tables are left
alone — `gen_data.py` still supplies those because RIF coverage starts
in 2015.

Scope:
- TAF inpatient (RIF inpatient.csv) — claims 2016–2018
- TAF outpatient (RIF outpatient.csv) — claims 2016–2018
- TAF demog (RIF beneficiary_YYYY.csv for YYYY ∈ {2016, 2017, 2018})
- TAF RX header + line (RIF pde.csv) — events 2016–2018
- HCPCS overlay: for lung-cancer-cohort beneficiaries, inject synthetic
  oncology J/C-code line rows drawn from HCPCS_CHEMO / HCPCS_IMMUNO pools
  defined in gen_data.py (Phase F)

Usage:
    python3 load_rif.py --csv ./csv

Run AFTER `gen_data.py` (which seeds the MAX-era tables + meta tables)
but before `load_mysql.sql`.  Orchestrator `build_cms_source.sh` does
this in order.
"""

from __future__ import annotations

import argparse
import csv
import os
import random
import sys
from datetime import date, datetime
from collections import defaultdict

# Reuse column-order + state-key + HCPCS-pool definitions from gen_data.py
# so the two files stay in lock-step.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_data import (  # noqa: E402
    load_column_names,
    STATE_KEYS,
    HCPCS_CHEMO,
    HCPCS_IMMUNO,
    SEED,
)
from ssa_state_crosswalk import ssa_to_postal  # noqa: E402


HERE = os.path.dirname(os.path.abspath(__file__))
RIF_DIR = os.path.join(HERE, "synthetic_rif_2023")
COLUMNS_CSV = os.path.join(HERE, "columns_formats.csv")

TAF_YEARS = range(2016, 2024)  # inclusive 2016..2023 — covers the full
                               # window Synthea emits non-trivial claim
                               # volume, especially for diseases it models
                               # with a long progression (lung cancer,
                               # most oncology).  The lung-cancer pipeline
                               # filters year_num >= 2016 so any year in
                               # this range flows through.

# Lung-cancer ICD codes — mirror of reference/build_reference_tables.sql
# (decimal-stripped). Used to flag oncology-cohort beneficiaries for the
# HCPCS overlay step.
LUNG_ICD = {
    # ICD-9
    "162", "1622", "1623", "1624", "1625", "1628", "1629", "2312",
    # ICD-10 (with/without dot, RIF varies)
    "C34", "C340", "C3400", "C3401", "C3402",
    "C341", "C3410", "C3411", "C3412",
    "C342", "C343", "C3430", "C3431", "C3432",
    "C348", "C3480", "C3481", "C3482",
    "C349", "C3490", "C3491", "C3492",
    "D022", "D0220", "D0221", "D0222",
}


# ── Helpers ────────────────────────────────────────────────────────────

def rif_date_to_iso(s: str) -> str:
    """RIF dates are `DD-Mon-YYYY` (e.g. '16-Aug-1999'). Convert to ISO.

    Empty / malformed strings return '' — downstream LOAD DATA will
    write NULL.
    """
    if not s or not s.strip():
        return ""
    try:
        return datetime.strptime(s.strip(), "%d-%b-%Y").strftime("%Y-%m-%d")
    except ValueError:
        return ""


def year_of_rif_date(s: str) -> int | None:
    if not s or not s.strip():
        return None
    try:
        return datetime.strptime(s.strip(), "%d-%b-%Y").year
    except ValueError:
        return None


def strip_dot(code: str) -> str:
    """CMS stores ICDs dotless — '3401' not '34.01'.  RIF is already
    dotless but a few variants sneak through; normalise just in case."""
    return (code or "").replace(".", "").strip()


def patient_id_from_bene(bene_id: str) -> str:
    """Mirror gen_data.py's PID + BENE_ID[:37] convention."""
    clean = (bene_id or "").replace("-", "")  # RIF BENE_IDs like '-10000930037831'
    return f"PID{clean[:37]}"


def msis_id_from_bene(bene_id: str) -> str:
    clean = (bene_id or "").replace("-", "")
    return f"MS{clean[:30]}"


# ── Beneficiary pool ───────────────────────────────────────────────────

def load_beneficiaries(years: range) -> dict[str, dict]:
    """Return {bene_id: {state_cd, state_key, birth_dt, sex_cd, race_cd,
    ref_yr, death_dt}}, taking the latest available year-file for each
    beneficiary (so current demographics win over historical ones)."""
    bene: dict[str, dict] = {}
    for y in years:
        path = os.path.join(RIF_DIR, f"beneficiary_{y}.csv")
        if not os.path.isfile(path):
            continue
        with open(path) as f:
            r = csv.DictReader(f, delimiter="|")
            for row in r:
                bid = row["BENE_ID"]
                postal = ssa_to_postal(row.get("STATE_CODE"))
                bene[bid] = {
                    "state_cd":  postal,
                    "state_key": STATE_KEYS.get(postal, 0),
                    "birth_dt":  rif_date_to_iso(row.get("BENE_BIRTH_DT", "")),
                    "sex_cd":    row.get("SEX_IDENT_CD", "") or "",
                    "race_cd":   row.get("BENE_RACE_CD", "") or "",
                    "ref_yr":    y,
                    "death_dt":  rif_date_to_iso(row.get("BENE_DEATH_DT", "")),
                }
    return bene


# ── Table-specific row emitters ────────────────────────────────────────

def emit_demog_elig_base(bene_pool: dict[str, dict]) -> list[dict]:
    """One row per (beneficiary, enrollment year) — the taf_demog_elig_base
    shape. For simplicity we emit one row per beneficiary keyed on their
    latest ref_yr (matches gen_data.py's one-row-per-patient TAF output)."""
    rows = []
    for bid, b in bene_pool.items():
        rows.append({
            "PATIENT_ID":      patient_id_from_bene(bid),
            "BENE_ID":         bid,
            "MSIS_ID":         msis_id_from_bene(bid),
            "STATE_CD":        b["state_cd"],
            "STATE_KEY":       b["state_key"],
            "SUBMTG_STATE_CD": b["state_cd"],
            "BENE_STATE_CD":   b["state_cd"],
            "BIRTH_DT":        b["birth_dt"],
            "DEATH_DT":        b["death_dt"],
            "SEX_CD":          b["sex_cd"],
            "RACE_ETHNCTY_CD": b["race_cd"],
            "RFRNC_YR":        b["ref_yr"],
        })
    return rows


def parse_inpatient(bene_pool: dict[str, dict]) -> tuple[list[dict], list[dict]]:
    """Walk inpatient.csv → (taf_inpatient_header rows, taf_inpatient_line rows).

    RIF inpatient.csv is line-level (one row per procedure line). We group
    by CLM_ID to produce one header row per claim and one line row per
    input row.
    """
    header_rows: list[dict] = []
    line_rows:   list[dict] = []
    seen_claims: set[str] = set()

    path = os.path.join(RIF_DIR, "inpatient.csv")
    with open(path) as f:
        r = csv.DictReader(f, delimiter="|")
        for row in r:
            yr = year_of_rif_date(row["CLM_FROM_DT"])
            if yr not in TAF_YEARS:
                continue
            bid = row["BENE_ID"]
            bene = bene_pool.get(bid)
            if not bene:
                continue
            clm = row["CLM_ID"]
            bgn = rif_date_to_iso(row["CLM_FROM_DT"])
            end = rif_date_to_iso(row["CLM_THRU_DT"])
            admsn = rif_date_to_iso(row.get("CLM_ADMSN_DT", ""))
            dschrg = rif_date_to_iso(row.get("NCH_BENE_DSCHRG_DT", "")) or end

            if clm not in seen_claims:
                seen_claims.add(clm)
                hdr = {
                    "PATIENT_ID":      patient_id_from_bene(bid),
                    "BENE_ID":         bid,
                    "MSIS_ID":         msis_id_from_bene(bid),
                    "STATE_CD":        bene["state_cd"],
                    "STATE_KEY":       bene["state_key"],
                    "SUBMTG_STATE_CD": bene["state_cd"],
                    "CLM_ID":          clm,
                    "ADMSN_DT":        admsn or bgn,
                    "SRVC_BGN_DT":     bgn,
                    "SRVC_END_DT":     end,
                    "DSCHRG_DT":       dschrg,
                    "BIRTH_DT":        bene["birth_dt"],
                    "RFRNC_YR":        yr,
                    "ADMTG_DGNS_CD":   strip_dot(row.get("PRNCPAL_DGNS_CD", "")),
                }
                # Dx code slots: RIF has ICD_DGNS_CD1..25; TAF uses DGNS_CD_1..12.
                # Take first 12.
                for i in range(1, 13):
                    hdr[f"DGNS_CD_{i}"] = strip_dot(row.get(f"ICD_DGNS_CD{i}", ""))
                header_rows.append(hdr)

            # Line: one row per RIF inpatient row (each is already a procedure line).
            ln = {
                "PATIENT_ID":      patient_id_from_bene(bid),
                "BENE_ID":         bid,
                "MSIS_ID":         msis_id_from_bene(bid),
                "STATE_CD":        bene["state_cd"],
                "STATE_KEY":       bene["state_key"],
                "SUBMTG_STATE_CD": bene["state_cd"],
                "CLM_ID":          clm,
                "LINE_NUM":        row.get("CLM_LINE_NUM", "") or "1",
                "LINE_SRVC_BGN_DT": bgn,
                "LINE_SRVC_END_DT": end,
                "ADJDCTN_DT":      bgn,
                "RFRNC_YR":        yr,
            }
            line_rows.append(ln)

    return header_rows, line_rows


def parse_outpatient(bene_pool: dict[str, dict]) -> tuple[list[dict], list[dict], set[str]]:
    """Walk outpatient.csv → (taf_other_services_header, taf_other_services_line,
    oncology_cohort_bene_ids).

    Returns the set of BENE_IDs with a lung-cancer dx anywhere in their
    outpatient claim history (used by the HCPCS overlay step).
    """
    header_rows: list[dict] = []
    line_rows:   list[dict] = []
    seen_claims: set[str] = set()
    oncology_bene: set[str] = set()

    path = os.path.join(RIF_DIR, "outpatient.csv")
    with open(path) as f:
        r = csv.DictReader(f, delimiter="|")
        for row in r:
            yr = year_of_rif_date(row["CLM_FROM_DT"])
            if yr not in TAF_YEARS:
                continue
            bid = row["BENE_ID"]
            bene = bene_pool.get(bid)
            if not bene:
                continue

            # Flag oncology-cohort membership by scanning dx codes.
            # Outpatient has ICD_DGNS_CD1..25 at cols 33-57.
            for i in range(1, 26):
                code = strip_dot(row.get(f"ICD_DGNS_CD{i}", ""))
                if code and code in LUNG_ICD:
                    oncology_bene.add(bid)
                    break

            clm = row["CLM_ID"]
            bgn = rif_date_to_iso(row["CLM_FROM_DT"])
            end = rif_date_to_iso(row["CLM_THRU_DT"])

            if clm not in seen_claims:
                seen_claims.add(clm)
                hdr = {
                    "PATIENT_ID":      patient_id_from_bene(bid),
                    "BENE_ID":         bid,
                    "MSIS_ID":         msis_id_from_bene(bid),
                    "STATE_CD":        bene["state_cd"],
                    "STATE_KEY":       bene["state_key"],
                    "SUBMTG_STATE_CD": bene["state_cd"],
                    "CLM_ID":          clm,
                    "SRVC_BGN_DT":     bgn,
                    "SRVC_END_DT":     end,
                    "BIRTH_DT":        bene["birth_dt"],
                    "RFRNC_YR":        yr,
                    # TAF other_services_header has only DGNS_CD_1 + DGNS_CD_2
                    "DGNS_CD_1": strip_dot(row.get("PRNCPAL_DGNS_CD", "")
                                           or row.get("ICD_DGNS_CD1", "")),
                    "DGNS_CD_2": strip_dot(row.get("ICD_DGNS_CD2", "")),
                }
                header_rows.append(hdr)

            # Line: each RIF row becomes one line (carries the row's HCPCS_CD).
            hcpcs = (row.get("HCPCS_CD", "") or "").strip()
            ln = {
                "PATIENT_ID":       patient_id_from_bene(bid),
                "BENE_ID":          bid,
                "MSIS_ID":          msis_id_from_bene(bid),
                "STATE_CD":         bene["state_cd"],
                "STATE_KEY":        bene["state_key"],
                "SUBMTG_STATE_CD":  bene["state_cd"],
                "CLM_ID":           clm,
                "LINE_NUM":         row.get("CLM_LINE_NUM", "") or "1",
                "LINE_SRVC_BGN_DT": bgn,
                "LINE_SRVC_END_DT": end,
                "LINE_PRCDR_CD":    hcpcs,
                "LINE_PRCDR_CD_DT": bgn,
                "LINE_PRCDR_CD_SYS": "H5" if hcpcs else "",
                "ADJDCTN_DT":       bgn,
                "RFRNC_YR":         yr,
            }
            line_rows.append(ln)

    return header_rows, line_rows, oncology_bene


def parse_pde(bene_pool: dict[str, dict]) -> tuple[list[dict], list[dict]]:
    """Walk pde.csv → (taf_rx_header, taf_rx_line). Each PDE row becomes
    one header row and one line row (matches gen_data.py's RX emission)."""
    header_rows: list[dict] = []
    line_rows:   list[dict] = []

    path = os.path.join(RIF_DIR, "pde.csv")
    with open(path) as f:
        r = csv.DictReader(f, delimiter="|")
        for row in r:
            yr = year_of_rif_date(row["SRVC_DT"])
            if yr not in TAF_YEARS:
                continue
            bid = row["BENE_ID"]
            bene = bene_pool.get(bid)
            if not bene:
                continue
            srvc = rif_date_to_iso(row["SRVC_DT"])
            pd = rif_date_to_iso(row.get("PD_DT", "")) or srvc
            clm = f"RX{row['PDE_ID']}"
            header_rows.append({
                "PATIENT_ID":      patient_id_from_bene(bid),
                "BENE_ID":         bid,
                "MSIS_ID":         msis_id_from_bene(bid),
                "STATE_CD":        bene["state_cd"],
                "STATE_KEY":       bene["state_key"],
                "SUBMTG_STATE_CD": bene["state_cd"],
                "CLM_ID":          clm,
                "ADJDCTN_DT":      srvc,
                "MDCD_PD_DT":      pd,
                "RFRNC_YR":        yr,
            })
            line_rows.append({
                "PATIENT_ID":      patient_id_from_bene(bid),
                "BENE_ID":         bid,
                "MSIS_ID":         msis_id_from_bene(bid),
                "STATE_CD":        bene["state_cd"],
                "STATE_KEY":       bene["state_key"],
                "SUBMTG_STATE_CD": bene["state_cd"],
                "CLM_ID":          clm,
                "LINE_NUM":        1,
                "ADJDCTN_DT":      srvc,
                "RFRNC_YR":        yr,
            })
    return header_rows, line_rows


def overlay_oncology_hcpcs(
    oncology_bene: set[str],
    bene_pool: dict[str, dict],
    existing_line_rows: list[dict],
    rng: random.Random,
) -> list[dict]:
    """For each oncology-cohort beneficiary, assign a treatment type and
    append N extra taf_other_services_line rows with oncology HCPCS codes.

    The overlay does NOT modify existing RIF-loaded rows — it appends
    additional line rows linked to new synthetic CLM_IDs so the RIF data
    stays untouched and the oncology signal is clearly attributable to
    the overlay.

    Distribution among oncology beneficiaries:
      45 % chemo-only, 35 % immuno-only, 10 % mixed, 10 % untreated.
    Untreated are kept in the cohort but get no oncology lines (for example,
    patients diagnosed too late in the window to have started therapy).
    Per treated beneficiary: 6–24 line rows drawn across 2–6 service dates
    in 2017–2018.
    """
    extra: list[dict] = []
    year_by_bene: dict[str, list[int]] = defaultdict(list)
    for row in existing_line_rows:
        year_by_bene[row["BENE_ID"]].append(int(row["RFRNC_YR"]))

    for bid in sorted(oncology_bene):
        bene = bene_pool.get(bid)
        if not bene:
            continue
        r = rng.random()
        if r < 0.45:
            treatment = "chemo"
        elif r < 0.80:
            treatment = "immuno"
        elif r < 0.90:
            treatment = "mixed"
        else:
            continue  # untreated

        # Pick 2–6 distinct service dates in 2017–2018 (late-window therapy).
        n_visits = rng.randint(2, 6)
        visit_dates: list[date] = []
        for _ in range(n_visits):
            y = rng.choice([2017, 2018])
            m = rng.randint(1, 12)
            d = rng.randint(1, 28)
            visit_dates.append(date(y, m, d))
        visit_dates.sort()

        for vi, dt in enumerate(visit_dates):
            clm = f"ONCO{bid.replace('-', '')[:10]}V{vi}"
            bgn = dt.isoformat()
            lines_this_visit = rng.randint(1, 3)
            for lnum in range(1, lines_this_visit + 1):
                if treatment == "chemo":
                    hcpcs = rng.choice(HCPCS_CHEMO)
                elif treatment == "immuno":
                    hcpcs = rng.choice(HCPCS_IMMUNO)
                else:  # mixed
                    hcpcs = rng.choice(HCPCS_CHEMO if rng.random() < 0.5
                                        else HCPCS_IMMUNO)
                extra.append({
                    "PATIENT_ID":       patient_id_from_bene(bid),
                    "BENE_ID":          bid,
                    "MSIS_ID":          msis_id_from_bene(bid),
                    "STATE_CD":         bene["state_cd"],
                    "STATE_KEY":        bene["state_key"],
                    "SUBMTG_STATE_CD":  bene["state_cd"],
                    "CLM_ID":           clm,
                    "LINE_NUM":         lnum,
                    "LINE_SRVC_BGN_DT": bgn,
                    "LINE_SRVC_END_DT": bgn,
                    "LINE_PRCDR_CD":    hcpcs,
                    "LINE_PRCDR_CD_DT": bgn,
                    "LINE_PRCDR_CD_SYS": "H5",
                    "ADJDCTN_DT":       bgn,
                    "RFRNC_YR":         dt.year,
                })
    return extra


def overlay_oncology_headers(
    oncology_bene: set[str],
    bene_pool: dict[str, dict],
    line_rows: list[dict],
) -> list[dict]:
    """Mirror `overlay_oncology_hcpcs` for the header table: one header
    row per synthetic ONCO* CLM_ID.  Also stamps a lung-cancer dx code on
    the header (DGNS_CD_1) so the header-level extraction in
    step1/lung_cohort_TAF.sql also sees these rows as lung-cancer claims.
    """
    by_clm: dict[str, dict] = {}
    for r in line_rows:
        if not r["CLM_ID"].startswith("ONCO"):
            continue
        clm = r["CLM_ID"]
        if clm in by_clm:
            continue
        bid = r["BENE_ID"]
        bene = bene_pool[bid]
        by_clm[clm] = {
            "PATIENT_ID":      r["PATIENT_ID"],
            "BENE_ID":         bid,
            "MSIS_ID":         r["MSIS_ID"],
            "STATE_CD":        r["STATE_CD"],
            "STATE_KEY":       r["STATE_KEY"],
            "SUBMTG_STATE_CD": r["STATE_CD"],
            "CLM_ID":          clm,
            "SRVC_BGN_DT":     r["LINE_SRVC_BGN_DT"],
            "SRVC_END_DT":     r["LINE_SRVC_END_DT"],
            "BIRTH_DT":        bene["birth_dt"],
            "RFRNC_YR":        r["RFRNC_YR"],
            # Stamp a lung-cancer dx on the header so the header-level
            # cohort-extraction SQL in step1/lung_cohort_TAF.sql can
            # pick it up.
            "DGNS_CD_1": "C3490",
            "DGNS_CD_2": "",
        }
    return list(by_clm.values())


# ── CSV writer ─────────────────────────────────────────────────────────

def write_csv(path: str, columns: list[str], rows: list[dict]) -> None:
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(columns)
        for r in rows:
            w.writerow(["" if r.get(c) is None else r.get(c) for c in columns])


# ── Driver ─────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="./csv",
                    help="output directory (usually the same as gen_data.py's --csv)")
    ap.add_argument("--seed", type=int, default=SEED)
    args = ap.parse_args()

    if not os.path.isdir(args.csv):
        os.makedirs(args.csv, exist_ok=True)

    columns = load_column_names(COLUMNS_CSV)
    rng = random.Random(args.seed)

    print(f"Loading RIF beneficiaries for {list(TAF_YEARS)} ...")
    bene_pool = load_beneficiaries(TAF_YEARS)
    print(f"  {len(bene_pool):,} distinct beneficiaries")

    print("Parsing inpatient.csv ...")
    ip_hdr, ip_ln = parse_inpatient(bene_pool)
    print(f"  {len(ip_hdr):,} header rows, {len(ip_ln):,} line rows")

    print("Parsing outpatient.csv ...")
    op_hdr, op_ln, oncology_bene = parse_outpatient(bene_pool)
    print(f"  {len(op_hdr):,} header rows, {len(op_ln):,} line rows")
    print(f"  {len(oncology_bene):,} beneficiaries with lung-cancer dx (oncology cohort)")

    print("Parsing pde.csv ...")
    rx_hdr, rx_ln = parse_pde(bene_pool)
    print(f"  {len(rx_hdr):,} RX header rows, {len(rx_ln):,} RX line rows")

    print("Emitting taf_demog_elig_base ...")
    demog = emit_demog_elig_base(bene_pool)
    print(f"  {len(demog):,} demog rows")

    print("Overlaying synthetic oncology HCPCS for cohort beneficiaries ...")
    overlay_lines = overlay_oncology_hcpcs(oncology_bene, bene_pool, op_ln, rng)
    overlay_hdrs = overlay_oncology_headers(oncology_bene, bene_pool, overlay_lines)
    print(f"  {len(overlay_hdrs):,} overlay header rows, {len(overlay_lines):,} overlay line rows")

    # Combine real + overlay.
    op_hdr_all = op_hdr + overlay_hdrs
    op_ln_all  = op_ln  + overlay_lines

    print("\nWriting CSVs ...")
    out = args.csv
    write_csv(os.path.join(out, "taf_demog_elig_base.csv"),
              columns["taf_demog_elig_base"], demog)
    write_csv(os.path.join(out, "taf_inpatient_header.csv"),
              columns["taf_inpatient_header"], ip_hdr)
    write_csv(os.path.join(out, "taf_inpatient_line.csv"),
              columns["taf_inpatient_line"], ip_ln)
    write_csv(os.path.join(out, "taf_other_services_header.csv"),
              columns["taf_other_services_header"], op_hdr_all)
    write_csv(os.path.join(out, "taf_other_services_line.csv"),
              columns["taf_other_services_line"], op_ln_all)
    write_csv(os.path.join(out, "taf_rx_header.csv"),
              columns["taf_rx_header"], rx_hdr)
    write_csv(os.path.join(out, "taf_rx_line.csv"),
              columns["taf_rx_line"], rx_ln)

    print("\n── Row counts (overwritten) ──")
    for name, n in [
        ("taf_demog_elig_base",      len(demog)),
        ("taf_inpatient_header",     len(ip_hdr)),
        ("taf_inpatient_line",       len(ip_ln)),
        ("taf_other_services_header", len(op_hdr_all)),
        ("taf_other_services_line",  len(op_ln_all)),
        ("taf_rx_header",            len(rx_hdr)),
        ("taf_rx_line",              len(rx_ln)),
    ]:
        print(f"  {name:<32} {n:>10,}")


if __name__ == "__main__":
    main()
