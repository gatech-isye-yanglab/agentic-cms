"""
CMS Medicaid Diabetes Cohort — Clinical Code Reference
=======================================================
Used by the Clinical Code Agent to build correct WHERE / LIKE conditions
across all three CMS eras (ICD-9 for ERA1/2, ICD-10 for TAF ERA3).

Source: pipelines/diabetes/reference/ SQL files (gold standard, read-only).
"""

# ---------------------------------------------------------------------------
# ICD-9 diabetes diagnosis codes
# Loaded into the `icd_9_cm` reference table; used in:
#   DIAG_CD_n IN (SELECT codes FROM icd_9_cm)
# ---------------------------------------------------------------------------
ICD9_CODES: list[str] = [
    # Type 2 diabetes (250.x0 = type 2, 250.x2 = type 2 uncontrolled)
    "25000", "25010", "25020", "25030", "25040", "25050", "25060", "25070", "25080", "25090",
    "25002", "25012", "25022", "25032", "25042", "25052", "25062", "25072", "25082", "25092",
    # Diabetic neuropathy
    "3572",
    # Diabetic retinopathy subtypes
    "36641", "36201", "36202", "36203", "36204", "36205", "36206", "36207",
]

# ---------------------------------------------------------------------------
# ICD-10 diabetes LIKE patterns
# Used in TAF era (2016-2018) as:
#   DGNS_CD_n LIKE 'E08%' OR DGNS_CD_n LIKE 'E11%' ...
# ---------------------------------------------------------------------------
ICD10_LIKE_PATTERNS: list[str] = [
    "E08%",   # Diabetes due to underlying condition
    "E09%",   # Drug or chemical induced diabetes
    "E11%",   # Type 2 diabetes mellitus
    "E13%",   # Other specified diabetes mellitus
    "O241%",  # Pre-existing type 2 diabetes in pregnancy
    "O243%",  # Unspecified pre-existing diabetes in pregnancy
    "O248%",  # Other pre-existing diabetes in pregnancy
]

# Convenience: SQL fragment for one diagnosis column (substitute {col})
ICD10_LIKE_SQL_TEMPLATE = (
    "{col} like 'E08%' OR {col} like 'E09%' OR {col} like 'E11%' OR {col} like 'E13%' "
    "OR {col} like 'O241%' OR {col} like 'O243%' OR {col} like 'O248%'"
)

# ---------------------------------------------------------------------------
# ICD-10 → ICD-9 mapping table
# Loaded into the `ICD code` reference table (note: table name has a space).
# Format: {icd10_code: icd9_code}
# ---------------------------------------------------------------------------
ICD10_TO_ICD9: dict[str, str] = {
    # Type 1 diabetes
    "E1010": "25010", "E1011": "25011",
    "E1000": "25020", "E1001": "25021",
    "E102":  "25041", "E103":  "25051",
    "E104":  "25061", "E105":  "25071",
    "E10":   "25001", "E109":  "25001",
    # Type 2 diabetes
    "E1110": "25010", "E1111": "25011",
    "E1100": "25020", "E1101": "25021",
    "E112":  "25040", "E113":  "25050",
    "E114":  "25060", "E115":  "25070",
    "E119":  "25000",
    # Other diabetes types
    "E088":  "24980", "E089":  "24900",
    "E098":  "24980",
    # Cardiovascular
    "EI20":  "4111",
    "I210":  "4101", "I219":  "4109",
    "I63":   "43491", "I61":   "431", "I64":   "436",
    "I420":  "4254",  "I429":  "4259",
    "I129":  "40390", "I120":  "40391",
    "I131":  "40493", "I132":  "40493",
    "I159":  "25070",
    "I739":  "4439",  "I7389": "44389",
    "I96":   "7854",
    # Neuropathy / peripheral
    "G632":  "3572", "G590":  "3558",
    # Retinopathy / eye
    "H369":  "3629",  "H368":  "36283", "H360":  "36291",
    "H350":  "36210", "H353":  "36250", "H358":  "36283",
    "H3610": "36201", "H3611": "36207", "H3612": "36202",
    "H281":  "36641", "H282":  "36645",
    # Renal
    "N181":  "5851", "N182":  "5852", "N183":  "5853",
    "N184":  "5854", "N189":  "5859",
    # Skin / wound
    "L974":  "70707", "L975":  "70706", "L976":  "7079",
    "L97511":"70706", "L97512":"70706", "L97519":"70706",
    "L9781": "70707", "L9782": "70707", "L9789": "70707",
    "L9701": "70701", "L9702": "70701",
    "L0291": "6829",
    "L03211":"6820",  "L03212":"6821",
    "L03221":"6824",  "L03222":"6826",
    # Musculoskeletal
    "M897":  "73399", "M898":  "73399",
    # Lab / symptoms
    "R739":  "7906",
    "R7301": "79021", "R7302": "79022", "R7303": "79029",
    # Cardiac
    "E1152": "7854",  "E1151": "25070",
    "E160":  "2512",  "E161":  "2512",
    # GI
    "K3184": "53783", "K3185": "53783",
    # Procedure-related
    "T8131": "99831", "T814":  "99859",
}

# ---------------------------------------------------------------------------
# HCPCS diabetes-related procedure codes
# Loaded into the `HCPCS_Codes` reference table.
# Categories: glucose monitoring supplies, insulin pumps, self-management edu
# ---------------------------------------------------------------------------
HCPCS_CODES: list[str] = [
    # Glucose monitoring & supplies
    "A4224", "A4233", "A4234", "A4250", "A4252", "A4253", "A4256", "A4257", "A4259",
    "A9274", "A9276", "A9277", "A9280", "A9286", "A9287", "A9288",
    # Insulin & insulin supplies
    "J1815", "J1817", "J1818", "J1819",
    "A4206", "A4207", "A4208",
    # Insulin pump & accessories
    "E0780", "E0781", "E0782", "E0784",
    "E2100", "E2101", "E2150",
    "K0552", "K0553", "K0554",
    # Wound care / footwear
    "A5500", "A5501", "A5510", "A5512", "A5253",
    "A6550", "L3000",
    # Nutrition / enteral
    "B4150", "B4152", "B4153", "B4154",
    "A7000",
    # Diabetes self-management education
    "G0101", "G0108", "G0109", "G0245", "G0257",
    # CPAP / respiratory (co-morbidity)
    "E0603", "E0604",
    # Other / misc
    "E1399", "E2402",
    "J3490",
]

# ---------------------------------------------------------------------------
# Target states for the SE cohort (Step 4 filter)
# ---------------------------------------------------------------------------
TARGET_STATES: list[str] = ["AL", "FL", "GA", "MS", "NC", "SC", "TN"]

TARGET_STATES_SQL = (
    "state_cd = 'AL' OR state_cd = 'FL' OR state_cd = 'GA' OR "
    "state_cd = 'MS' OR state_cd = 'NC' OR state_cd = 'SC' OR state_cd = 'TN'"
)

# ---------------------------------------------------------------------------
# Year ranges per era (for documentation / prompt context)
# ---------------------------------------------------------------------------
ERA_YEARS: dict[str, list[int]] = {
    "MAX_ERA1": list(range(2005, 2013)),   # 2005-2012
    "MAX_ERA2": list(range(2013, 2016)),   # 2013-2015
    "TAF_ERA3": list(range(2016, 2019)),   # 2016-2018
}
