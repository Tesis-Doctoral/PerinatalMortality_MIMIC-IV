-- ============================================================================
-- COUNT AUDIT, groups A-D -- fetal-death models (plan v2, task T08)
-- ============================================================================
-- Purpose: measure, on the revised obstetric cohort of the maternal project, the
-- numbers needed to settle decisions D3 (population), D4 (unit of analysis and
-- same pregnancy) and D5 (outcome definition) BEFORE any model is built.
-- READ-ONLY: it only creates temporary tables and runs SELECTs. Results are
-- aggregated counts; do NOT publish rows with subject_id or hadm_id.
--
-- Prerequisites (built by MaternalMortality_MIMIC-IV, sql/04_labels and sql/05_predictors):
--   mimiciv.cohort_obstetric_v2, mimiciv.hadm_delivery_v2, mimiciv.obstetric_dx_v2,
--   mimiciv.predictors_24h_v2
-- Q-A2 (last query) also needs mimiciv.cohort_fetal_death_dataset (legacy table of
-- sql/fetal_death_dataset.sql); if it does not exist, only that query fails.
--
-- The fetal-death label used here is PROVISIONAL: the same 13 code patterns as the
-- legacy scripts (strict / partial). The verified code table is task T15.
-- Q-C5 (patients on both sides of an admission-level split) is computed in the
-- notebook 01_patient_overlap (task T13). Groups E and F are separate scripts.
--
-- Run the whole script in ONE connection (DBeaver: Alt+X): the temporary tables
-- must survive between statements. Each result set starts with a label column q
-- that matches the identifier of the sheet 'Conteos' of the tracking workbook.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0. Working tables
-- ----------------------------------------------------------------------------
-- Provisional fetal-death code patterns (same list as the legacy scripts)
DROP TABLE IF EXISTS tmp_fa_patterns;
CREATE TEMP TABLE tmp_fa_patterns (
    icd_version INT,
    code_prefix VARCHAR(10),
    tier        VARCHAR(10)
);
INSERT INTO tmp_fa_patterns VALUES
 (10, 'O364', 'strict'), (10, 'Z371', 'strict'), (10, 'Z374', 'strict'), (10, 'Z377', 'strict'),
 (10, 'Z373', 'partial'), (10, 'Z376', 'partial'), (10, 'O312', 'partial'),
 (9,  '6564', 'strict'), (9,  'V271', 'strict'), (9,  'V274', 'strict'), (9,  'V277', 'strict'),
 (9,  'V273', 'partial'), (9,  'V276', 'partial');

-- Fetal-death codes in ANY admission of the patients of the cohort (needed to look at earlier events)
DROP TABLE IF EXISTS tmp_fa_hits_all;
CREATE TEMP TABLE tmp_fa_hits_all AS
SELECT d.subject_id, d.hadm_id, d.icd_version, d.icd_code, d.seq_num, p.tier
FROM   mimiciv.diagnoses_icd d
JOIN   tmp_fa_patterns p
       ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_prefix || '%'
WHERE  d.subject_id IN (SELECT subject_id FROM mimiciv.cohort_obstetric_v2);

-- One row per admission with a fetal-death code
DROP TABLE IF EXISTS tmp_fa_event;
CREATE TEMP TABLE tmp_fa_event AS
SELECT hadm_id,
       TRUE                      AS fd_any,
       BOOL_OR(tier = 'strict')  AS fd_strict,
       MIN(seq_num)              AS min_fd_seq,
       COUNT(*)                  AS n_fd_codes
FROM   tmp_fa_hits_all
GROUP  BY hadm_id;

-- Gestational weeks from Z3A.xx codes (ICD-10 only; Z3A.00 / Z3A.01 = unspecified / < 8 weeks)
DROP TABLE IF EXISTS tmp_fa_gest;
CREATE TEMP TABLE tmp_fa_gest AS
SELECT hadm_id, MAX(w) AS gest_weeks
FROM (
    SELECT d.hadm_id,
           CASE WHEN d.icd_code ~ '^Z3A[0-9]{2}' THEN substring(d.icd_code FROM 4 FOR 2)::INT END AS w
    FROM   mimiciv.diagnoses_icd d
    WHERE  d.icd_version = 10 AND d.icd_code LIKE 'Z3A%'
      AND  d.hadm_id IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
) t
WHERE  w >= 8
GROUP  BY hadm_id;

-- Obstetric diagnoses of the admission that are NOT fetal-death codes
DROP TABLE IF EXISTS tmp_fa_obst;
CREATE TEMP TABLE tmp_fa_obst AS
SELECT o.hadm_id, COUNT(*) FILTER (WHERE p.tier IS NULL) AS n_obst_other
FROM   mimiciv.obstetric_dx_v2 o
LEFT JOIN tmp_fa_patterns p
       ON p.icd_version = o.icd_version AND o.icd_code LIKE p.code_prefix || '%'
GROUP  BY o.hadm_id;

-- Working table: one row per admission of the obstetric universe
DROP TABLE IF EXISTS tmp_fa_base;
CREATE TEMP TABLE tmp_fa_base AS
SELECT c.subject_id, c.hadm_id, c.admittime, a.dischtime,
       COALESCE(c.is_delivery_v2, FALSE)       AS is_delivery_v2,
       COALESCE(c.has_stillbirth_code, FALSE)  AS has_stillbirth_code,
       COALESCE(c.has_structured_obst, FALSE)  AS has_structured_obst,
       COALESCE(c.smm_any, FALSE)              AS smm_any,
       COALESCE(c.died_same_admission, FALSE)  AS died_same_admission,
       CASE WHEN c.has_icd10_dx AND NOT c.has_icd9_dx THEN 'ICD-10 only'
            WHEN c.has_icd9_dx AND NOT c.has_icd10_dx THEN 'ICD-9 only'
            WHEN c.has_icd9_dx AND c.has_icd10_dx     THEN 'both'
            ELSE 'no diagnoses' END            AS icd_era,
       COALESCE(dv.has_abortive_code, FALSE)   AS has_abortive_code,
       pt.anchor_year_group,
       CAST(LEFT(pt.anchor_year_group, 4) AS int)
         + (EXTRACT(YEAR FROM c.admittime)::int - pt.anchor_year) AS approx_year_low,
       COALESCE(e.fd_any, FALSE)               AS fd_any,
       COALESCE(e.fd_strict, FALSE)            AS fd_strict,
       e.min_fd_seq,
       g.gest_weeks,
       COALESCE(ob.n_obst_other, 0)            AS n_obst_other,
       ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.admittime, c.hadm_id) AS adm_rank,
       (c.admittime::date - LAG(c.admittime::date)
            OVER (PARTITION BY c.subject_id ORDER BY c.admittime, c.hadm_id))        AS gap_days
FROM   mimiciv.cohort_obstetric_v2 c
JOIN   mimiciv.admissions a  ON a.hadm_id = c.hadm_id
JOIN   mimiciv.patients  pt  ON pt.subject_id = c.subject_id
LEFT JOIN mimiciv.hadm_delivery_v2 dv ON dv.hadm_id = c.hadm_id
LEFT JOIN tmp_fa_event e  ON e.hadm_id  = c.hadm_id
LEFT JOIN tmp_fa_gest  g  ON g.hadm_id  = c.hadm_id
LEFT JOIN tmp_fa_obst  ob ON ob.hadm_id = c.hadm_id;

-- Days since the closest EARLIER admission of the same patient that carries a fetal-death code
DROP TABLE IF EXISTS tmp_fa_prior;
CREATE TEMP TABLE tmp_fa_prior AS
SELECT b.hadm_id, MIN(b.admittime::date - a2.admittime::date) AS days_since_prior_fd
FROM   tmp_fa_base b
JOIN   mimiciv.admissions a2 ON a2.subject_id = b.subject_id AND a2.admittime < b.admittime
JOIN   (SELECT DISTINCT hadm_id FROM tmp_fa_hits_all) h ON h.hadm_id = a2.hadm_id
GROUP  BY b.hadm_id;

DROP TABLE IF EXISTS tmp_fa;
CREATE TEMP TABLE tmp_fa AS
SELECT b.*, p.days_since_prior_fd
FROM   tmp_fa_base b
LEFT JOIN tmp_fa_prior p ON p.hadm_id = b.hadm_id;

-- ============================================================================
-- GROUP A -- base
-- ============================================================================

-- Q-A1. Base counts (maternal audit: 25,736 / 15,084 / 19,425 / 19,383)
SELECT 'Q-A1 base' AS q,
       COUNT(*)                                                    AS n_admissions,
       COUNT(DISTINCT f.subject_id)                                AS n_patients,
       COUNT(*) FILTER (WHERE f.is_delivery_v2)                    AS n_delivery_hospitalizations,
       COUNT(DISTINCT f.subject_id) FILTER (WHERE f.is_delivery_v2) AS n_patients_with_delivery,
       COUNT(*) FILTER (WHERE f.is_delivery_v2 AND p.eligible_24h) AS n_deliveries_eligible_24h,
       (SELECT COUNT(*) FROM mimiciv.predictors_24h_v2)            AS n_rows_predictors_24h
FROM   tmp_fa f
LEFT JOIN mimiciv.predictors_24h_v2 p ON p.hadm_id = f.hadm_id;

-- Q-A3. Admissions per patient
WITH pa AS (SELECT subject_id, COUNT(*) AS n FROM tmp_fa GROUP BY subject_id)
SELECT 'Q-A3 admissions per patient' AS q,
       CASE WHEN n >= 5 THEN '5 or more' ELSE n::text END AS admissions_per_patient,
       COUNT(*)  AS n_patients,
       SUM(n)    AS n_admissions
FROM   pa GROUP BY 2 ORDER BY 2;

-- Q-A3b. Summary (maternal audit: 6,793 of 15,084 patients with more than one admission; maximum 27)
WITH pa AS (SELECT subject_id, COUNT(*) AS n FROM tmp_fa GROUP BY subject_id)
SELECT 'Q-A3b summary' AS q,
       COUNT(*)                                                    AS n_patients,
       COUNT(*) FILTER (WHERE n > 1)                               AS n_patients_with_more_than_one,
       ROUND(100.0 * COUNT(*) FILTER (WHERE n > 1) / COUNT(*), 1)  AS pct_more_than_one,
       MAX(n)                                                      AS max_admissions
FROM   pa;

-- ============================================================================
-- GROUP B -- events and definition
-- ============================================================================

-- Q-B1. Events by tier and ICD version (legacy: 154 events, 136 strict)
SELECT 'Q-B1 events by tier and ICD version' AS q, icd_era,
       COUNT(*)                                           AS n_admissions,
       COUNT(*) FILTER (WHERE fd_any)                     AS n_events_strict_or_partial,
       COUNT(*) FILTER (WHERE fd_strict)                  AS n_events_strict,
       COUNT(*) FILTER (WHERE fd_any AND NOT fd_strict)   AS n_events_partial_only,
       COUNT(DISTINCT subject_id) FILTER (WHERE fd_any)   AS n_patients_with_event
FROM   tmp_fa
GROUP  BY ROLLUP (icd_era)
ORDER  BY icd_era NULLS LAST;

-- Q-B2. Events by scope
SELECT 'Q-B2 events by scope' AS q, scope,
       n_admissions, n_events_strict_or_partial, n_events_strict,
       ROUND(1000.0 * n_events_strict_or_partial / NULLIF(n_admissions, 0), 2) AS events_per_1000_admissions
FROM (
    SELECT 1 AS o, 'Any obstetric admission' AS scope, COUNT(*) AS n_admissions,
           COUNT(*) FILTER (WHERE fd_any) AS n_events_strict_or_partial, COUNT(*) FILTER (WHERE fd_strict) AS n_events_strict
    FROM tmp_fa
    UNION ALL
    SELECT 2, 'Delivery hospitalization (v2 flag)', COUNT(*), COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_strict)
    FROM tmp_fa WHERE is_delivery_v2
    UNION ALL
    SELECT 3, 'Not a delivery hospitalization', COUNT(*), COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_strict)
    FROM tmp_fa WHERE NOT is_delivery_v2
    UNION ALL
    SELECT 4, 'With a structured obstetric code (any position)', COUNT(*), COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_strict)
    FROM tmp_fa WHERE has_structured_obst
    UNION ALL
    SELECT 5, 'Without a structured obstetric code', COUNT(*), COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_strict)
    FROM tmp_fa WHERE NOT has_structured_obst
) s
ORDER BY o;

-- Q-B3. Agreement of the label with the stillbirth code of the delivery flag (maternal audit: 109 deliveries)
SELECT 'Q-B3 label vs has_stillbirth_code' AS q, fd_strict, has_stillbirth_code, is_delivery_v2, icd_era,
       COUNT(*) AS n_admissions
FROM   tmp_fa
WHERE  fd_any OR has_stillbirth_code
GROUP  BY fd_strict, has_stillbirth_code, is_delivery_v2, icd_era
ORDER  BY fd_strict DESC, has_stillbirth_code DESC, is_delivery_v2 DESC, icd_era;

-- Q-B4. Gestational weeks of the events (ICD-10 admissions only have Z3A codes)
SELECT 'Q-B4 gestational weeks of events' AS q, icd_era,
       CASE WHEN fd_strict THEN 'strict' ELSE 'partial only' END AS tier,
       CASE WHEN gest_weeks IS NULL THEN '4 no Z3A code'
            WHEN gest_weeks <  22   THEN '1 under 22 weeks'
            WHEN gest_weeks <  28   THEN '2 22-27 weeks'
            ELSE                         '3 28 weeks or more' END AS gestational_age,
       COUNT(*) AS n_events
FROM   tmp_fa
WHERE  fd_any
GROUP  BY 2, 3, 4
ORDER  BY 2, 3, 4;

-- Q-B5. Position of the fetal-death code in the diagnosis list, and events where no other obstetric code exists
SELECT 'Q-B5 position of the fetal-death code' AS q,
       CASE WHEN min_fd_seq <= 4 THEN '1-4' WHEN min_fd_seq <= 10 THEN '5-10' ELSE 'over 10' END AS lowest_position,
       COUNT(*)                                  AS n_events,
       COUNT(*) FILTER (WHERE n_obst_other = 0)  AS n_events_without_other_obstetric_code
FROM   tmp_fa
WHERE  fd_any
GROUP  BY 2 ORDER BY 2;

-- Q-B6. Strict fetal-death codes in admissions OUTSIDE the obstetric universe (by sex and approximate age)
WITH out_adm AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM   mimiciv.diagnoses_icd d
    JOIN   tmp_fa_patterns p
           ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_prefix || '%' AND p.tier = 'strict'
    WHERE  d.hadm_id NOT IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
)
SELECT 'Q-B6 strict codes outside the universe' AS q, pt.gender,
       CASE WHEN pt.anchor_age + (DATE_PART('year', a.admittime) - pt.anchor_year) < 12 THEN 'under 12'
            WHEN pt.anchor_age + (DATE_PART('year', a.admittime) - pt.anchor_year) <= 55 THEN '12-55'
            ELSE 'over 55' END AS approx_age,
       COUNT(DISTINCT o.hadm_id) AS n_admissions
FROM   out_adm o
JOIN   mimiciv.admissions a ON a.hadm_id = o.hadm_id
JOIN   mimiciv.patients pt  ON pt.subject_id = o.subject_id
GROUP  BY 2, 3 ORDER BY 2, 3;

-- Q-B7. Overlap with severe maternal morbidity and with death in the same admission (legacy: 2 and 0 among strict)
SELECT 'Q-B7 overlap with SMM and maternal death' AS q,
       CASE WHEN fd_strict IS NULL THEN 'all events' WHEN fd_strict THEN 'strict' ELSE 'partial only' END AS tier,
       COUNT(*)                                              AS n_events,
       COUNT(*) FILTER (WHERE smm_any)                       AS n_with_smm,
       COUNT(*) FILTER (WHERE died_same_admission)           AS n_maternal_death_same_admission,
       COUNT(*) FILTER (WHERE smm_any AND died_same_admission) AS n_both
FROM   tmp_fa
WHERE  fd_any
GROUP  BY ROLLUP (fd_strict)
ORDER  BY fd_strict NULLS FIRST;

-- Q-B8. Events whose admission also carries an abortive, ectopic or molar code (pre-viable losses)
SELECT 'Q-B8 events with abortive or ectopic codes' AS q, has_abortive_code, is_delivery_v2,
       COUNT(*)                        AS n_events_strict_or_partial,
       COUNT(*) FILTER (WHERE fd_strict) AS n_events_strict
FROM   tmp_fa
WHERE  fd_any
GROUP  BY 2, 3 ORDER BY 2, 3;

-- ============================================================================
-- GROUP C -- patient overlap and same pregnancy
-- ============================================================================

-- Q-C1. Event admissions per patient
WITH pe AS (
    SELECT subject_id, COUNT(*) AS n_adm, COUNT(*) FILTER (WHERE fd_any) AS n_event_adm
    FROM   tmp_fa GROUP BY subject_id
)
SELECT 'Q-C1 event admissions per patient' AS q, n_event_adm AS event_admissions_of_the_patient,
       COUNT(*)  AS n_patients,
       SUM(n_adm) AS n_admissions_of_these_patients
FROM   pe
WHERE  n_event_adm >= 1
GROUP  BY 2 ORDER BY 2;

-- Q-C2. Gap to the previous admission of the same patient, by event status of the admission
SELECT 'Q-C2 gap to the previous admission' AS q,
       CASE WHEN gap_days IS NULL THEN '0 first admission of the patient'
            WHEN gap_days <  90   THEN '1 under 90 days'
            WHEN gap_days < 180   THEN '2 90-179 days'
            WHEN gap_days < 365   THEN '3 180-364 days'
            ELSE                       '4 365 days or more' END AS gap_to_previous_admission,
       COUNT(*)                         AS n_admissions,
       COUNT(*) FILTER (WHERE fd_any)   AS n_events
FROM   tmp_fa
GROUP  BY 2 ORDER BY 2;

-- Q-C3. Gap to an EARLIER admission that already carries a fetal-death code
--       (legacy figures disagree: 17 admissions, 5 events, described as under 90 days and as within 180 days)
SELECT 'Q-C3 gap to an earlier fetal-death admission' AS q,
       CASE WHEN days_since_prior_fd IS NULL THEN '0 no earlier fetal-death admission'
            WHEN days_since_prior_fd <  90   THEN '1 under 90 days'
            WHEN days_since_prior_fd < 180   THEN '2 90-179 days'
            WHEN days_since_prior_fd < 365   THEN '3 180-364 days'
            ELSE                                  '4 365 days or more' END AS gap_to_earlier_event,
       COUNT(*)                          AS n_admissions,
       COUNT(*) FILTER (WHERE fd_any)    AS n_events,
       COUNT(*) FILTER (WHERE NOT fd_any) AS n_non_events
FROM   tmp_fa
GROUP  BY 2 ORDER BY 2;

-- Q-C3b. Event admissions that are the first admission of the patient in the universe, or a later one
SELECT 'Q-C3b event admissions by rank' AS q,
       CASE WHEN adm_rank = 1 THEN 'first admission' ELSE 'later admission' END AS admission_rank,
       COUNT(*) FILTER (WHERE fd_any)    AS n_events,
       COUNT(*) FILTER (WHERE fd_strict) AS n_events_strict
FROM   tmp_fa
GROUP  BY 2 ORDER BY 2;

-- Q-C4. Events under each candidate unit of analysis
--       Pregnancy chain = admissions of the same patient linked by a gap of at most G days to the previous one
WITH g AS (SELECT * FROM (VALUES (30), (90), (180)) AS v(gap_limit)),
chain AS (
    SELECT g.gap_limit, f.subject_id, f.hadm_id, f.fd_any, f.fd_strict,
           SUM(CASE WHEN f.gap_days IS NULL OR f.gap_days > g.gap_limit THEN 1 ELSE 0 END)
               OVER (PARTITION BY g.gap_limit, f.subject_id ORDER BY f.admittime, f.hadm_id) AS chain_id
    FROM   tmp_fa f CROSS JOIN g
),
chain_units AS (
    SELECT gap_limit, subject_id, chain_id,
           BOOL_OR(fd_any) AS has_event, BOOL_OR(fd_strict) AS has_strict
    FROM   chain GROUP BY gap_limit, subject_id, chain_id
)
SELECT 'Q-C4 events by unit of analysis' AS q, unit, n_units, n_units_with_event, n_units_with_strict_event, n_patients_with_event
FROM (
    SELECT 1 AS o, 'Admission (any obstetric)' AS unit, COUNT(*) AS n_units,
           COUNT(*) FILTER (WHERE fd_any) AS n_units_with_event, COUNT(*) FILTER (WHERE fd_strict) AS n_units_with_strict_event,
           COUNT(DISTINCT subject_id) FILTER (WHERE fd_any) AS n_patients_with_event
    FROM tmp_fa
    UNION ALL
    SELECT 2, 'Delivery hospitalization', COUNT(*), COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_strict),
           COUNT(DISTINCT subject_id) FILTER (WHERE fd_any)
    FROM tmp_fa WHERE is_delivery_v2
    UNION ALL
    SELECT 3, 'First admission per patient', COUNT(*), COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_strict),
           COUNT(DISTINCT subject_id) FILTER (WHERE fd_any)
    FROM tmp_fa WHERE adm_rank = 1
    UNION ALL
    SELECT 3 + gap_limit / 30 AS o, 'Pregnancy chain, gap of at most ' || gap_limit || ' days', COUNT(*),
           COUNT(*) FILTER (WHERE has_event), COUNT(*) FILTER (WHERE has_strict),
           COUNT(DISTINCT subject_id) FILTER (WHERE has_event)
    FROM chain_units GROUP BY gap_limit
) s
ORDER BY o;

-- ============================================================================
-- GROUP D -- era and coding
-- ============================================================================

-- Q-D1. Events and rate per 1,000 delivery hospitalizations, by ICD version
--       (rate = events in delivery hospitalizations / delivery hospitalizations; it is NOT per 1,000 total births)
SELECT 'Q-D1 events by ICD version' AS q, icd_era,
       COUNT(*) FILTER (WHERE is_delivery_v2)                                  AS n_deliveries,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_any)                       AS n_events_in_deliveries,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_strict)                    AS n_strict_in_deliveries,
       COUNT(*) FILTER (WHERE NOT is_delivery_v2 AND fd_any)                   AS n_events_not_deliveries,
       ROUND(1000.0 * COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_any)
             / NULLIF(COUNT(*) FILTER (WHERE is_delivery_v2), 0), 2)           AS events_per_1000_deliveries
FROM   tmp_fa
GROUP  BY ROLLUP (icd_era)
ORDER  BY icd_era NULLS LAST;

-- Q-D1b. Same, by anchor-year group (the patient's anchor window, NOT the date of each admission)
SELECT 'Q-D1b events by anchor-year group' AS q, anchor_year_group,
       COUNT(*) FILTER (WHERE is_delivery_v2)                                  AS n_deliveries,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_any)                       AS n_events_in_deliveries,
       COUNT(*) FILTER (WHERE NOT is_delivery_v2 AND fd_any)                   AS n_events_not_deliveries,
       ROUND(1000.0 * COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_any)
             / NULLIF(COUNT(*) FILTER (WHERE is_delivery_v2), 0), 2)           AS events_per_1000_deliveries
FROM   tmp_fa
GROUP  BY anchor_year_group ORDER BY anchor_year_group;

-- Q-D1c. Approximate admission year (lower bound of the anchor window + offset) by ICD version: is the era confounded?
SELECT 'Q-D1c approximate year by ICD version' AS q, icd_era, COUNT(*) AS n_admissions,
       PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY approx_year_low) AS p05_year,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY approx_year_low) AS median_year,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY approx_year_low) AS p95_year
FROM   tmp_fa
GROUP  BY icd_era ORDER BY icd_era;

-- Q-D2. Availability of gestational weeks (Z3A codes exist only in ICD-10)
SELECT 'Q-D2 gestational weeks by ICD version' AS q, icd_era,
       COUNT(*) FILTER (WHERE fd_any)                                   AS n_events,
       COUNT(*) FILTER (WHERE fd_any AND gest_weeks IS NOT NULL)        AS n_events_with_weeks,
       COUNT(*) FILTER (WHERE is_delivery_v2)                           AS n_deliveries,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND gest_weeks IS NOT NULL) AS n_deliveries_with_weeks
FROM   tmp_fa
GROUP  BY ROLLUP (icd_era)
ORDER  BY icd_era NULLS LAST;

-- Q-D3. Rates per 1,000 delivery hospitalizations under four definitions, to compare with a published
--       stillbirth rate (source to be cited; mind that published rates use total births as denominator)
SELECT 'Q-D3 rates per 1,000 deliveries' AS q, definition, n_events, n_deliveries,
       ROUND(1000.0 * n_events / NULLIF(n_deliveries, 0), 2) AS rate_per_1000_deliveries
FROM (
    SELECT 1 AS o, 'A. Stillbirth code of the delivery flag (Z37.1/.4/.7, V27.1/.4/.7)' AS definition,
           COUNT(*) FILTER (WHERE has_stillbirth_code) AS n_events, COUNT(*) AS n_deliveries
    FROM tmp_fa WHERE is_delivery_v2
    UNION ALL
    SELECT 2, 'B. Strict fetal-death label', COUNT(*) FILTER (WHERE fd_strict), COUNT(*)
    FROM tmp_fa WHERE is_delivery_v2
    UNION ALL
    SELECT 3, 'C. Strict or partial fetal-death label', COUNT(*) FILTER (WHERE fd_any), COUNT(*)
    FROM tmp_fa WHERE is_delivery_v2
    UNION ALL
    SELECT 4, 'D. ICD-10 only, strict, 28 weeks or more (late stillbirth)',
           COUNT(*) FILTER (WHERE fd_strict AND gest_weeks >= 28), COUNT(*)
    FROM tmp_fa WHERE is_delivery_v2 AND icd_era = 'ICD-10 only'
) s
ORDER BY o;

-- ============================================================================
-- Q-A2 -- reconciliation with the legacy dataset (keep LAST: it fails if the table does not exist)
-- ============================================================================
SELECT to_regclass('mimiciv.cohort_fetal_death_dataset') IS NOT NULL AS legacy_dataset_exists;

SELECT 'Q-A2 reconciliation with the legacy dataset' AS q,
       COUNT(*) FILTER (WHERE f.hadm_id IS NOT NULL AND l.hadm_id IS NOT NULL) AS in_both,
       COUNT(*) FILTER (WHERE f.hadm_id IS NOT NULL AND l.hadm_id IS NULL)     AS only_in_revised_cohort,
       COUNT(*) FILTER (WHERE f.hadm_id IS NULL AND l.hadm_id IS NOT NULL)     AS only_in_legacy_dataset,
       COUNT(*) FILTER (WHERE l.outcome_fetal_death = 1)                       AS legacy_events,
       COUNT(*) FILTER (WHERE f.fd_any)                                        AS revised_events,
       COUNT(*) FILTER (WHERE l.outcome_fetal_death = 1 AND f.fd_any)          AS events_in_both,
       COUNT(*) FILTER (WHERE l.outcome_fetal_death = 1 AND NOT COALESCE(f.fd_any, FALSE)) AS legacy_event_not_event_now,
       COUNT(*) FILTER (WHERE COALESCE(l.outcome_fetal_death, 0) = 0 AND f.fd_any)         AS new_event_not_in_legacy
FROM   tmp_fa f
FULL JOIN mimiciv.cohort_fetal_death_dataset l ON l.hadm_id = f.hadm_id;
