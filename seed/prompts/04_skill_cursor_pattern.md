# Prompt 04 — Structural skill files

## Goal

Generate `knowledge/skills/` — two markdown files that the agent
reads at runtime to learn the cursor pattern and the combine-step
shape. These are themselves prompt-shaped, by design — they are the
"institutional skill knowledge" that the agent internalizes before
writing SQL.

The Claw4Science / OpenClaw 2026 paper makes the same architectural
choice: skill files act as both documentation and execution. They
are the single source of truth for *how this institution writes
SQL*.

## Files to generate (under `knowledge/skills/`)

| File | Purpose |
|---|---|
| `extraction_cursor.md` | The CROSS JOIN cursor pattern that satisfies the partition rule, with placeholders for disease-specific substitution. |
| `combine_step.md` | The `all_combine` schema and per-era INSERT pattern that unions the 6 Step-1 outputs into a single normalized table. |

## extraction_cursor.md — content

Sections:

1. **Purpose.** State the partition rule: every extraction query
   against a `cms_source` source table MUST use a partitioned cursor
   loop, because the institutional production server kills any
   unpartitioned full-table scan.
2. **Required pattern (CROSS JOIN cursor — preferred).** A SINGLE
   cursor over a cross join of `state_codes` and `data_years`. Show
   the canonical SQL with `{proc_name}`, `{output_table}`,
   `{source_table}`, `{year_col}`, `{year_start}`, `{year_end}`,
   `{disease_filter}` placeholders. Critical: this avoids MySQL's
   nested-cursor DONE-flag bug.

   ```sql
   DELIMITER $$
   CREATE PROCEDURE {proc_name}()
   BEGIN
       DECLARE done INT DEFAULT 0;
       DECLARE v_state_key INT;
       DECLARE v_year_num INT;

       DECLARE cur1 CURSOR FOR
           SELECT sc.state_key, dy.year_num
           FROM cms_source.state_codes sc, cms_source.data_years dy
           WHERE dy.year_num BETWEEN {year_start} AND {year_end}
           ORDER BY sc.state_key, dy.year_num;

       DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

       OPEN cur1;
       read_loop: LOOP
           FETCH cur1 INTO v_state_key, v_year_num;
           IF done THEN LEAVE read_loop; END IF;

           INSERT INTO {output_table}
           SELECT *
           FROM cms_source.{source_table} inp
           WHERE inp.state_key = v_state_key
             AND inp.{year_col} = v_year_num
             AND ({disease_filter});
       END LOOP;
       CLOSE cur1;
   END$$
   DELIMITER ;

   CALL {proc_name}();
   ```

3. **Placeholder reference.** Brief table mapping each placeholder
   to its source (disease profile vs era metadata).
4. **ERA-specific column names** table — copy this table verbatim:

   | ERA | Source tables | Diag cols | Year col | State col | Patient ID |
   |-----|---------------|-----------|----------|-----------|------------|
   | ERA1 2005-2012 | `inpatient`, `other_therapy` | `DIAG_CD_1..9` / `..2` | `YR_NUM` | `state_key` | `patient_id` |
   | ERA2 2013-2015 | `inpatient1315`, `other_therapy1315` | `DIAG_CD_1..9` / `..2` | `YR_NUM` | `state_key` | `patient_id` |
   | ERA3 2016-2018 | `taf_inpatient_header`, `taf_other_services_header` | `DGNS_CD_1..12` / `..2` | `RFRNC_YR` | `STATE_KEY` | `PATIENT_ID` |

5. **Nested cursor warning.** If you nest cursors instead of cross-
   joining, you MUST declare a SEPARATE `done` flag for each cursor
   (`done_state`, `done_year`) — MySQL's `CONTINUE HANDLER FOR NOT
   FOUND` sets a shared flag, so the inner cursor exhausting can
   accidentally exit the outer loop. This is a real bug that has
   bitten real pipelines.

## combine_step.md — content

Sections:

1. **Purpose.** Union all 6 Step-1 extraction outputs into a single
   normalized `all_combine` table. **Identical across diseases —
   only the source table names produced by Step 1 change.**
2. **all_combine schema (fixed, disease-agnostic).** Verbatim CREATE
   TABLE with these columns:
   - `patient_id VARCHAR(40), BENE_ID VARCHAR(15), STATE_CD VARCHAR(2), state_key INT, YR_NUM INT, BIRTH_DT DATE, SRVC_BGN_DT DATE, SRVC_END_DT DATE, DIAG_CD_1..9 VARCHAR(8), DIAG_CD_10..12 VARCHAR(7)` (SRVC_BGN_DT / SRVC_END_DT are uppercase per `columns_formats.csv`)
3. **Insert pattern per era** with two examples:
   - ERA1 (`Re_all_inpatient`, `DIAG_CD_1..9`): straightforward INSERT
     SELECT into `all_combine`.
   - ERA3 TAF (`Re_All_taf_inpatient_header`, `DGNS_CD_1..12`): same
     INSERT but with `PATIENT_ID → patient_id`, `STATE_KEY → state_key`,
     `RFRNC_YR → YR_NUM`, `DGNS_CD_n → DIAG_CD_n` column-rename
     normalization in the SELECT list.
4. **Notes:**
   - `EL_DOB → BIRTH_DT` normalization: ERA1/2 use `EL_DOB`; TAF
     uses `BIRTH_DT`. `all_combine` uses `BIRTH_DT` for all eras.
   - `EL_SEX_CD`, `EL_RACE_ETHNCY_CD` are dropped in `all_combine`
     (not in schema). Demographics travel separately via
     `all_combine_demo`.
   - `YR_NUM` for ERA1/2 maps to `RFRNC_YR` for TAF — both stored in
     the unified `YR_NUM` column.
   - The table names in FROM clauses are the OUTPUT_TABLE_MAP values
     from the disease profile.

## Critical: do not generalize the column names

The institutional schema's intentional inconsistency
(`patient_id` lowercase MAX vs `PATIENT_ID` uppercase TAF; same for
`state_key`/`STATE_KEY`) is the *point*. The skill file teaches the
agent how to navigate this inconsistency, not how to hide it. If the
agent emits SQL that uses unified casing, it works against synthetic
and breaks against real institutional data. Track the inconsistency.

## See also

- Full-repo equivalents at `knowledge/skills/{extraction_cursor.md, combine_step.md}`.
- Prompt 03 for the partition-filter Critic that enforces what this skill teaches.
- Prompt 06 for the per-disease pipelines that consume these skills.
