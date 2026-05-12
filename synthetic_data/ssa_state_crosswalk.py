"""SSA state-code → USPS postal crosswalk.

RIF uses the SSA (Social Security Administration) numeric state code in
`STATE_CODE` columns — e.g. '01' for Alabama, '10' for Florida. Our TAF
schema expects the two-letter USPS postal code.  This module maps between
the two.

Source: SSA POMS RM 10215.065 (the canonical SSA state-code table).
"""

from __future__ import annotations

SSA_TO_POSTAL: dict[str, str] = {
    "01": "AL", "02": "AK", "03": "AZ", "04": "AR", "05": "CA",
    "06": "CO", "07": "CT", "08": "DE", "09": "DC", "10": "FL",
    "11": "GA", "12": "HI", "13": "ID", "14": "IL", "15": "IN",
    "16": "IA", "17": "KS", "18": "KY", "19": "LA", "20": "ME",
    "21": "MD", "22": "MA", "23": "MI", "24": "MN", "25": "MS",
    "26": "MO", "27": "MT", "28": "NE", "29": "NV", "30": "NH",
    "31": "NJ", "32": "NM", "33": "NY", "34": "NC", "35": "ND",
    "36": "OH", "37": "OK", "38": "OR", "39": "PA", "40": "PR",
    "41": "RI", "42": "SC", "43": "SD", "44": "TN", "45": "TX",
    "46": "UT", "47": "VT", "48": "VA", "49": "VI", "50": "WA",
    "51": "WV", "52": "WI", "53": "WY", "54": "AS", "55": "GU",
    "56": "MP",
}


def ssa_to_postal(ssa: str | None) -> str:
    """Return USPS postal code for SSA code, or 'XX' for unknown/missing.

    RIF sometimes emits empty strings or single-digit codes ('1' instead of
    '01'); normalise before looking up.
    """
    if not ssa:
        return "XX"
    key = ssa.strip().zfill(2)
    return SSA_TO_POSTAL.get(key, "XX")
