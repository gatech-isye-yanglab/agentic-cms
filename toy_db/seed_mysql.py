"""
Seed script: generates 1000 patients into local MySQL cms_source database.
Run: python3 toy_db/seed_mysql.py

Requires: pip install mysql-connector-python
Patient ID ranges:
  P0001-P0250  ERA 1 inpatient       cms_source.inpatient           (2005-2012)
  P0251-P0450  ERA 2 inpatient       cms_source.inpatient1315       (2013-2015)
  P0451-P0600  ERA 1 outpatient      cms_source.other_therapy       (2005-2012)
  P0601-P0700  ERA 2 outpatient      cms_source.other_therapy1315    (2013-2015)
  P0701-P0900  ERA 3 TAF inpatient   cms_source.taf_inpatient_header(2016-2018)
  P0901-P1000  ERA 3 TAF outpatient  cms_source.taf_other_services_header(2016-2018)

Patient type distribution (per group):
  40% positive   — 2+ claims ≤730 days, SE state, diabetes ICD code
  20% single     — 1 claim only  (excluded by 24-month rule)
  15% long_gap   — gap >730 days (excluded)
  10% wrong_state— non-SE state  (excluded by Step 4 filter)
  10% no_diabetes— non-diabetes ICD code (excluded by Step 2 filter)
   5% ambiguous  — inconsistent EL_SEX_CD across claims (positive but flagged later)
"""

import os
import random
from datetime import date, timedelta
import mysql.connector

SEED = 42
random.seed(SEED)

DB_CFG = dict(host='127.0.0.1', user='root', database='cms_source')

SE_STATES   = ['AL', 'FL', 'GA', 'MS', 'NC', 'SC', 'TN']
OUT_STATES  = ['NY', 'CA', 'TX', 'OH', 'PA', 'IL']
STATE_KEYS  = {s: i+1 for i, s in enumerate(SE_STATES)}
STATE_KEYS.update({s: 100+i+1 for i, s in enumerate(OUT_STATES)})

ICD9  = ['25000','25001','25002','25010','25011','25012',
         '25020','25021','25022','25030','25040','25041',
         '25050','25060','25061','25070','25071','25080','25090']
ICD10 = ['E1010','E1011','E1110','E1111','E109','E119',
         'E104','E114','E102','E112','E088','E089','E098','E1000','E1100']
NON_D = ['J189','I10','Z0000','M5450','K219','J069','N390','R0789']


def rd(y0, y1):
    s, e = date(y0,1,1), date(y1,12,31)
    return s + timedelta(days=random.randint(0,(e-s).days))

def add(d, n): return d + timedelta(days=n)
def icd9():  return random.choice(ICD9)
def icd10(): return random.choice(ICD10)
def non():   return random.choice(NON_D)
def diab():  return random.choice(ICD9+ICD10)

def state(target=True):
    s = random.choice(SE_STATES if target else OUT_STATES)
    return s, STATE_KEYS[s]

def ptype(idx, total):
    r = (idx-1)/total
    for thr, t in [(.40,'positive'),(.60,'single'),(.75,'long_gap'),
                   (.85,'wrong_state'),(.95,'no_diabetes'),(1.,'ambiguous')]:
        if r < thr: return t

# ── Row builders ──────────────────────────────────────────────────────────────

def row12_ip(pid, sc, sk, yr, sex, race, dob, bgn, end_, diags):
    d = (diags + [None]*9)[:9]
    return (pid, f"B{pid[1:]}", sc, sk, yr, dob, sex, race, bgn, end_, *d)

def row12_ot(pid, sc, sk, yr, sex, race, dob, bgn, end_, diags):
    d = (diags + [None]*2)[:2]
    return (pid, f"B{pid[1:]}", sc, sk, yr, dob, sex, race, bgn, end_, *d)

def row_taf_ip(pid, sc, sk, yr, dob, bgn, end_, diags):
    d = (diags + [None]*12)[:12]
    return (pid, f"B{pid[1:]}", sc, sk, yr, dob, bgn, end_, *d)

def row_taf_ot(pid, sc, sk, yr, dob, bgn, end_, diags):
    d = (diags + [None]*2)[:2]
    return (pid, f"B{pid[1:]}", sc, sk, yr, dob, bgn, end_, *d)

# ── Generate all rows ─────────────────────────────────────────────────────────

def generate():
    buckets = {t: [] for t in
               ['inpatient','inpatient1315','other_therapy',
                'other_therapy1315','taf_inpatient_header','taf_other_services_header']}
    labels = {}

    # ERA 1 inpatient 2005-2012 (P0001-P0250)
    for i in range(1, 251):
        pid = f"P{i:04d}"; pt = ptype(i, 250); labels[pid] = pt
        sex = random.choice(['M','F']); race = str(random.randint(1,5))
        dob = rd(1930,1975)
        sc, sk = state(pt != 'wrong_state')
        if pt == 'no_diabetes':
            bgn = rd(2005,2012)
            buckets['inpatient'].append(row12_ip(pid,sc,sk,bgn.year,sex,race,dob,bgn,add(bgn,3),[non(),non()]))
        elif pt == 'wrong_state':
            bgn = rd(2005,2012)
            buckets['inpatient'].append(row12_ip(pid,sc,sk,bgn.year,sex,race,dob,bgn,add(bgn,2),[icd9()]))
            bgn2 = add(bgn, random.randint(30,200)); yr2 = min(bgn2.year,2012)
            buckets['inpatient'].append(row12_ip(pid,sc,sk,yr2,sex,race,dob,bgn2,add(bgn2,2),[icd9()]))
        elif pt == 'single':
            bgn = rd(2005,2012)
            buckets['inpatient'].append(row12_ip(pid,sc,sk,bgn.year,sex,race,dob,bgn,add(bgn,2),[icd9()]))
        elif pt == 'long_gap':
            bgn1 = rd(2005,2009); bgn2 = add(bgn1, random.randint(731,1200))
            yr2 = min(bgn2.year,2012)
            buckets['inpatient'].append(row12_ip(pid,sc,sk,bgn1.year,sex,race,dob,bgn1,add(bgn1,2),[icd9()]))
            buckets['inpatient'].append(row12_ip(pid,sc,sk,yr2,sex,race,dob,bgn2,add(bgn2,2),[icd9()]))
        else:  # positive / ambiguous
            bgn1 = rd(2005,2011); bgn2 = add(bgn1, random.randint(30,700))
            yr2 = min(bgn2.year,2012)
            sex2 = ('F' if sex=='M' else 'M') if pt=='ambiguous' else sex
            d1 = icd9() if i%2==0 else icd10(); d2 = icd10() if i%3==0 else icd9()
            buckets['inpatient'].append(row12_ip(pid,sc,sk,bgn1.year,sex,race,dob,bgn1,add(bgn1,3),[d1,non()]))
            buckets['inpatient'].append(row12_ip(pid,sc,sk,yr2,sex2,race,dob,bgn2,add(bgn2,2),[d2]))

    # ERA 2 inpatient 2013-2015 (P0251-P0450)
    for i in range(251, 451):
        pid = f"P{i:04d}"; pt = ptype(i-250, 200); labels[pid] = pt
        sex = random.choice(['M','F']); race = str(random.randint(1,5))
        dob = rd(1935,1980)
        sc, sk = state(pt != 'wrong_state')
        if pt == 'no_diabetes':
            bgn = rd(2013,2015)
            buckets['inpatient1315'].append(row12_ip(pid,sc,sk,bgn.year,sex,race,dob,bgn,add(bgn,1),[non()]))
        elif pt in ('wrong_state','single'):
            bgn = rd(2013,2015)
            buckets['inpatient1315'].append(row12_ip(pid,sc,sk,bgn.year,sex,race,dob,bgn,add(bgn,2),[diab()]))
        elif pt == 'long_gap':
            bgn1 = rd(2013,2013); bgn2 = add(bgn1, random.randint(731,900))
            yr2 = min(bgn2.year,2015)
            buckets['inpatient1315'].append(row12_ip(pid,sc,sk,2013,sex,race,dob,bgn1,add(bgn1,1),[icd9()]))
            buckets['inpatient1315'].append(row12_ip(pid,sc,sk,yr2,sex,race,dob,bgn2,add(bgn2,1),[icd9()]))
        else:
            bgn1 = rd(2013,2014); bgn2 = add(bgn1, random.randint(14,700))
            yr2 = min(bgn2.year,2015)
            sex2 = ('F' if sex=='M' else 'M') if pt=='ambiguous' else sex
            buckets['inpatient1315'].append(row12_ip(pid,sc,sk,bgn1.year,sex,race,dob,bgn1,add(bgn1,2),[icd10()]))
            buckets['inpatient1315'].append(row12_ip(pid,sc,sk,yr2,sex2,race,dob,bgn2,add(bgn2,1),[icd9()]))

    # ERA 1 outpatient 2005-2012 (P0451-P0600)
    for i in range(451, 601):
        pid = f"P{i:04d}"; pt = ptype(i-450, 150); labels[pid] = pt
        sex = random.choice(['M','F']); race = str(random.randint(1,5))
        dob = rd(1940,1985)
        sc, sk = state(pt != 'wrong_state')
        if pt == 'no_diabetes':
            bgn = rd(2005,2012)
            buckets['other_therapy'].append(row12_ot(pid,sc,sk,bgn.year,sex,race,dob,bgn,bgn,[non()]))
        elif pt in ('wrong_state','single'):
            bgn = rd(2005,2012)
            buckets['other_therapy'].append(row12_ot(pid,sc,sk,bgn.year,sex,race,dob,bgn,bgn,[icd9()]))
        elif pt == 'long_gap':
            bgn1 = rd(2005,2009); bgn2 = add(bgn1, random.randint(731,1000))
            yr2 = min(bgn2.year,2012)
            buckets['other_therapy'].append(row12_ot(pid,sc,sk,bgn1.year,sex,race,dob,bgn1,bgn1,[icd9()]))
            buckets['other_therapy'].append(row12_ot(pid,sc,sk,yr2,sex,race,dob,bgn2,bgn2,[icd9()]))
        else:
            bgn1 = rd(2005,2011); bgn2 = add(bgn1, random.randint(10,700))
            yr2 = min(bgn2.year,2012)
            sex2 = ('F' if sex=='M' else 'M') if pt=='ambiguous' else sex
            buckets['other_therapy'].append(row12_ot(pid,sc,sk,bgn1.year,sex,race,dob,bgn1,bgn1,[icd9()]))
            buckets['other_therapy'].append(row12_ot(pid,sc,sk,yr2,sex2,race,dob,bgn2,bgn2,[icd10()]))

    # ERA 2 outpatient 2013-2015 (P0601-P0700)
    for i in range(601, 701):
        pid = f"P{i:04d}"; pt = ptype(i-600, 100); labels[pid] = pt
        sex = random.choice(['M','F']); race = str(random.randint(1,5))
        dob = rd(1945,1990)
        sc, sk = state(pt != 'wrong_state')
        if pt == 'no_diabetes':
            bgn = rd(2013,2015)
            buckets['other_therapy1315'].append(row12_ot(pid,sc,sk,bgn.year,sex,race,dob,bgn,bgn,[non()]))
        elif pt in ('wrong_state','single'):
            bgn = rd(2013,2015)
            buckets['other_therapy1315'].append(row12_ot(pid,sc,sk,bgn.year,sex,race,dob,bgn,bgn,[diab()]))
        elif pt == 'long_gap':
            bgn1 = rd(2013,2013); bgn2 = add(bgn1, random.randint(731,800))
            yr2 = min(bgn2.year,2015)
            buckets['other_therapy1315'].append(row12_ot(pid,sc,sk,2013,sex,race,dob,bgn1,bgn1,[icd9()]))
            buckets['other_therapy1315'].append(row12_ot(pid,sc,sk,yr2,sex,race,dob,bgn2,bgn2,[icd10()]))
        else:
            bgn1 = rd(2013,2014); bgn2 = add(bgn1, random.randint(10,700))
            yr2 = min(bgn2.year,2015)
            sex2 = ('F' if sex=='M' else 'M') if pt=='ambiguous' else sex
            buckets['other_therapy1315'].append(row12_ot(pid,sc,sk,bgn1.year,sex,race,dob,bgn1,bgn1,[icd10()]))
            buckets['other_therapy1315'].append(row12_ot(pid,sc,sk,yr2,sex2,race,dob,bgn2,bgn2,[icd9()]))

    # ERA 3 TAF inpatient 2016-2018 (P0701-P0900)
    for i in range(701, 901):
        pid = f"P{i:04d}"; pt = ptype(i-700, 200); labels[pid] = pt
        dob = rd(1940,1985)
        sc, sk = state(pt != 'wrong_state')
        if pt == 'no_diabetes':
            bgn = rd(2016,2018)
            buckets['taf_inpatient_header'].append(row_taf_ip(pid,sc,sk,bgn.year,dob,bgn,add(bgn,3),[non()]))
        elif pt in ('wrong_state','single'):
            bgn = rd(2016,2018)
            buckets['taf_inpatient_header'].append(row_taf_ip(pid,sc,sk,bgn.year,dob,bgn,add(bgn,2),[icd10()]))
        elif pt == 'long_gap':
            bgn1 = rd(2016,2016); bgn2 = add(bgn1, random.randint(731,900))
            yr2 = min(bgn2.year,2018)
            buckets['taf_inpatient_header'].append(row_taf_ip(pid,sc,sk,2016,dob,bgn1,add(bgn1,2),[icd10()]))
            buckets['taf_inpatient_header'].append(row_taf_ip(pid,sc,sk,yr2,dob,bgn2,add(bgn2,1),[icd10()]))
        else:
            bgn1 = rd(2016,2017); bgn2 = add(bgn1, random.randint(14,700))
            yr2 = min(bgn2.year,2018)
            buckets['taf_inpatient_header'].append(row_taf_ip(pid,sc,sk,bgn1.year,dob,bgn1,add(bgn1,3),[icd10(),non()]))
            buckets['taf_inpatient_header'].append(row_taf_ip(pid,sc,sk,yr2,dob,bgn2,add(bgn2,2),[icd10()]))

    # ERA 3 TAF outpatient 2016-2018 (P0901-P1000)
    for i in range(901, 1001):
        pid = f"P{i:04d}"; pt = ptype(i-900, 100); labels[pid] = pt
        dob = rd(1950,1995)
        sc, sk = state(pt != 'wrong_state')
        if pt == 'no_diabetes':
            bgn = rd(2016,2018)
            buckets['taf_other_services_header'].append(row_taf_ot(pid,sc,sk,bgn.year,dob,bgn,bgn,[non()]))
        elif pt in ('wrong_state','single'):
            bgn = rd(2016,2018)
            buckets['taf_other_services_header'].append(row_taf_ot(pid,sc,sk,bgn.year,dob,bgn,bgn,[icd10()]))
        elif pt == 'long_gap':
            bgn1 = rd(2016,2016); bgn2 = add(bgn1, random.randint(731,850))
            yr2 = min(bgn2.year,2018)
            buckets['taf_other_services_header'].append(row_taf_ot(pid,sc,sk,2016,dob,bgn1,bgn1,[icd10()]))
            buckets['taf_other_services_header'].append(row_taf_ot(pid,sc,sk,yr2,dob,bgn2,bgn2,[icd10()]))
        else:
            bgn1 = rd(2016,2017); bgn2 = add(bgn1, random.randint(10,700))
            yr2 = min(bgn2.year,2018)
            buckets['taf_other_services_header'].append(row_taf_ot(pid,sc,sk,bgn1.year,dob,bgn1,bgn1,[icd10()]))
            buckets['taf_other_services_header'].append(row_taf_ot(pid,sc,sk,yr2,dob,bgn2,bgn2,[icd10()]))

    return buckets, labels


def main():
    # Apply the schema first so seed runs from a clean fresh state.
    schema_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")
    if os.path.exists(schema_path):
        # Connect without a default DB so the CREATE DATABASE in schema.sql works.
        boot = mysql.connector.connect(host=DB_CFG['host'], user=DB_CFG['user'])
        bcur = boot.cursor()
        with open(schema_path) as f:
            for stmt in f.read().split(';'):
                if stmt.strip():
                    bcur.execute(stmt)
        boot.commit(); bcur.close(); boot.close()

    con = mysql.connector.connect(**DB_CFG)
    cur = con.cursor()

    # Meta
    all_states = list(STATE_KEYS.items())
    cur.executemany("INSERT IGNORE INTO state_codes (state_code, state_key) VALUES (%s,%s)",
                    [(k,v) for k,v in all_states])
    cur.executemany("INSERT IGNORE INTO data_years VALUES (%s)",
                    [(y,) for y in range(2005,2019)])

    print("Generating 1000 patients ...")
    buckets, labels = generate()

    sql_ip19  = "INSERT INTO {tbl} VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)"
    sql_ot2   = "INSERT INTO {tbl} VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)"
    sql_tafip = "INSERT INTO taf_inpatient_header VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)"
    sql_tafot = "INSERT INTO taf_other_services_header VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)"

    cur.executemany(sql_ip19.format(tbl='inpatient'),       buckets['inpatient'])
    cur.executemany(sql_ip19.format(tbl='inpatient1315'),   buckets['inpatient1315'])
    cur.executemany(sql_ot2.format(tbl='other_therapy'),    buckets['other_therapy'])
    cur.executemany(sql_ot2.format(tbl='other_therapy1315'), buckets['other_therapy1315'])
    cur.executemany(sql_tafip, buckets['taf_inpatient_header'])
    cur.executemany(sql_tafot, buckets['taf_other_services_header'])
    con.commit()

    # Summary
    from collections import Counter
    dist = Counter(labels.values())
    print("\n── Source table row counts ──────────────────────────────────")
    total = 0
    for tbl, label in [
        ('inpatient',                'ERA1 inpatient  2005-2012'),
        ('inpatient1315',            'ERA2 inpatient  2013-2015'),
        ('other_therapy',            'ERA1 outpatient 2005-2012'),
        ('other_therapy1315',         'ERA2 outpatient 2013-2015'),
        ('taf_inpatient_header',     'ERA3 TAF inpat  2016-2018'),
        ('taf_other_services_header','ERA3 TAF outpat 2016-2018'),
    ]:
        cur.execute(f"SELECT COUNT(*), COUNT(DISTINCT patient_id) FROM {tbl}")
        r, p = cur.fetchone()
        total += r
        print(f"  {label}: {r:4d} rows, {p:4d} patients")
    print(f"  Total: {total} rows, 1000 patients")
    print(f"\n  Patient types: {dict(dist)}")
    cur.close(); con.close()
    print("\nDone. Ready to run pipelines/diabetes/ steps 1-4 via toy_db/run_sql.py.")

if __name__ == "__main__":
    main()
