-- 1. Create the final output table if it doesn't exist.
--    patient_id must match the collation of All_Selected_state.patient_id
--    (explicit utf8mb4_0900_as_cs in step3) so that step5's JOINs don't
--    hit "Illegal mix of collations".
CREATE TABLE IF NOT EXISTS temp_all_in_two_years_GA (
    patient_id VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs,
    srvc_bgn_DT DATE,
    appears_within_2_years TINYINT
);

-- 2. Clear previous results
TRUNCATE TABLE temp_all_in_two_years_GA;

-- 2b. Supporting index for the correlated EXISTS subquery below.
--     Without it the 24-month lookup is O(N^2) over ~20k GA rows and
--     never finishes in a reasonable wall-clock.  Re-creating is safe
--     because step3 rebuilds All_Selected_state from scratch.
SET @exists_idx := (SELECT COUNT(*) FROM information_schema.STATISTICS
                    WHERE TABLE_SCHEMA = DATABASE()
                      AND TABLE_NAME = 'All_Selected_state'
                      AND INDEX_NAME = 'idx_all_selected_state_ga');
SET @stmt := IF(@exists_idx = 0,
                'CREATE INDEX idx_all_selected_state_ga ON All_Selected_state (state_CD, patient_id, srvc_bgn_DT)',
                'DO 0');
PREPARE s FROM @stmt; EXECUTE s; DEALLOCATE PREPARE s;

-- 3. Insert the logic-driven results directly
INSERT INTO temp_all_in_two_years_GA (patient_id, srvc_bgn_DT, appears_within_2_years)
SELECT
    t1.patient_id,
    t1.srvc_bgn_DT,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM All_Selected_state t2
            WHERE t2.patient_id = t1.patient_id
              AND t2.state_CD = 'GA' -- Ensures the 'future' record is also in GA
              AND t2.srvc_bgn_DT > t1.srvc_bgn_DT
              AND t2.srvc_bgn_DT <= DATE_ADD(t1.srvc_bgn_DT, INTERVAL 2 YEAR)
        ) THEN 1
        ELSE 0
    END AS appears_within_2_years
FROM All_Selected_state t1
WHERE t1.state_CD = 'GA'; -- Filters the base records to Georgia