-- ============================================================================
-- 01_labels / 02_fetal_death_label_by_admission.sql
-- Fetal-death label by admission (plan v2, task T16)
-- ============================================================================
-- Purpose: build mimiciv.fetal_death_label_v2, ONE ROW PER ADMISSION of the revised
--   obstetric universe (mimiciv.cohort_obstetric_v2), with the label and everything that
--   later analyses need to define sensitivity analyses as COLUMNS, not as filters:
--   tier of the event (strict / partial), code families, position of the code, early-loss
--   and newborn-record codes, gestational weeks (Z3A), ICD era, population flag of D3,
--   and the flag of D8 (admission shorter than 6 hours).
--   The table is the label source for every later script: nothing downstream should
--   recompute the event from diagnoses_icd.
--
-- Decisions applied (2026-10-28):
--   D3  population = delivery flag v2 OR stillbirth code  -> column in_pop_d3
--   D5  main label = strict code at any gestational age   -> column label_main
--       sensitivities: strict + partial, >= 22 weeks, >= 28 weeks (ICD-10 admissions only,
--       the only ones with Z3A codes), and the flag has_early_loss_code (to exclude events)
--   D6  prediction point = admission + 6 h
--   D8  admissions that end before admission + 6 h are excluded from the model and
--       reported apart  -> column ends_before_6h
--   The label has NO event time (it is a discharge code): see analysis_plan.md.
--
-- Prerequisites: mimiciv.cohort_obstetric_v2, mimiciv.hadm_delivery_v2,
--   mimiciv.predictors_24h_v2 (maternal project, sql/04_labels and sql/05_predictors) and
--   mimiciv.fetal_death_code_patterns_v2 (script 01_fetal_death_codes_official.sql, T15).
--
-- Columns that are NULL on purpose: label_ge22 and label_ge28 are NULL for a strict event
--   whose gestational age is unknown (no Z3A code); a sensitivity analysis must report
--   those events apart. Non-events are FALSE.
--
-- Run the whole script in one connection (DBeaver: Alt+X). The table is persistent, so the
--   checks can be re-run alone. Only aggregate results are produced: do NOT publish rows
--   with subject_id or hadm_id.
-- ============================================================================

SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS mimiciv.fetal_death_label_v2;

CREATE TABLE mimiciv.fetal_death_label_v2 AS
WITH hits AS (
    -- every code of the universe that matches a pattern, whatever its tier
    SELECT d.hadm_id, d.icd_version, d.icd_code, d.seq_num, p.tier, p.code_group
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.fetal_death_code_patterns_v2 p
           ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
    WHERE  d.hadm_id IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
),
ev AS (
    -- one row per admission with at least one matching code
    SELECT hadm_id,
           COUNT(*) FILTER (WHERE tier = 'strict')                                   AS n_strict_codes,
           COUNT(*) FILTER (WHERE tier = 'partial')                                  AS n_partial_codes,
           MIN(seq_num) FILTER (WHERE tier = 'strict')                               AS min_strict_seq,
           MIN(seq_num) FILTER (WHERE tier IN ('strict', 'partial'))                 AS min_event_seq,
           BOOL_OR(tier = 'strict' AND code_group = 'Intrauterine death')            AS has_intrauterine_death_code,
           BOOL_OR(tier = 'strict' AND code_group = 'Stillbirth outcome of delivery') AS has_stillbirth_outcome_code,
           BOOL_OR(code_group = 'Mixed outcome of a multiple pregnancy')             AS has_mixed_outcome_code,
           BOOL_OR(icd_version = 9 AND icd_code LIKE '65643%')                       AS has_antepartum_6564_code,
           BOOL_OR(code_group = 'Early fetal death (pre-viable)')                    AS has_early_loss_code,
           BOOL_OR(code_group = 'Newborn-record code')                               AS has_newborn_record_code
    FROM   hits
    GROUP  BY hadm_id
),
z3a AS (
    -- gestational weeks from Z3A.xx (ICD-10 only); Z3A.00 / Z3A.01 = unspecified / under 8 weeks
    SELECT hadm_id,
           TRUE                                                                      AS has_z3a_code,
           MAX(CASE WHEN substring(icd_code FROM 4 FOR 2)::INT >= 8
                    THEN substring(icd_code FROM 4 FOR 2)::INT END)                  AS gest_weeks
    FROM   mimiciv.diagnoses_icd
    WHERE  icd_version = 10 AND icd_code ~ '^Z3A[0-9]{2}'
      AND  hadm_id IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
    GROUP  BY hadm_id
)
SELECT c.subject_id,
       c.hadm_id,
       c.admittime,
       a.dischtime,
       -- population (D3) and its two components
       COALESCE(c.is_delivery_v2, FALSE)                                             AS is_delivery_v2,
       COALESCE(c.has_stillbirth_code, FALSE)                                        AS has_stillbirth_code,
       (COALESCE(c.is_delivery_v2, FALSE) OR COALESCE(c.has_stillbirth_code, FALSE)) AS in_pop_d3,
       COALESCE(dv.has_abortive_code, FALSE)                                         AS has_abortive_code,
       -- event and tier
       (COALESCE(e.n_strict_codes, 0) > 0)                                           AS fd_strict,
       (COALESCE(e.n_strict_codes, 0) = 0 AND COALESCE(e.n_partial_codes, 0) > 0)    AS fd_partial_only,
       (COALESCE(e.n_strict_codes, 0) + COALESCE(e.n_partial_codes, 0) > 0)          AS fd_any,
       CASE WHEN COALESCE(e.n_strict_codes, 0) > 0  THEN 'strict'
            WHEN COALESCE(e.n_partial_codes, 0) > 0 THEN 'partial only'
            ELSE                                         'no event' END              AS fd_tier,
       COALESCE(e.n_strict_codes, 0)                                                 AS n_strict_codes,
       COALESCE(e.n_partial_codes, 0)                                                AS n_partial_codes,
       -- code families and position of the code (seq_num 1 = principal diagnosis)
       COALESCE(e.has_intrauterine_death_code, FALSE)                                AS has_intrauterine_death_code,
       COALESCE(e.has_stillbirth_outcome_code, FALSE)                                AS has_stillbirth_outcome_code,
       COALESCE(e.has_mixed_outcome_code, FALSE)                                     AS has_mixed_outcome_code,
       COALESCE(e.has_antepartum_6564_code, FALSE)                                   AS has_antepartum_6564_code,
       e.min_strict_seq,
       e.min_event_seq,
       -- early-loss and newborn-record codes (never used by the label; flags for sensitivity and audit)
       COALESCE(e.has_early_loss_code, FALSE)                                        AS has_early_loss_code,
       COALESCE(e.has_newborn_record_code, FALSE)                                    AS has_newborn_record_code,
       -- gestational age (ICD-10 only)
       COALESCE(g.has_z3a_code, FALSE)                                               AS has_z3a_code,
       g.gest_weeks,
       CASE WHEN g.gest_weeks IS NULL THEN 'unknown'
            WHEN g.gest_weeks < 22    THEN 'under 22'
            WHEN g.gest_weeks < 28    THEN '22 to 27'
            ELSE                           '28 or more' END                          AS gest_band,
       -- era of coding
       CASE WHEN c.has_icd10_dx AND NOT c.has_icd9_dx THEN 'ICD-10 only'
            WHEN c.has_icd9_dx AND NOT c.has_icd10_dx THEN 'ICD-9 only'
            WHEN c.has_icd9_dx AND c.has_icd10_dx     THEN 'both'
            ELSE 'no diagnoses' END                                                  AS icd_era,
       pt.anchor_year_group,
       -- labels: main (D5) and sensitivity definitions as columns
       (COALESCE(e.n_strict_codes, 0) > 0)                                           AS label_main,
       (COALESCE(e.n_strict_codes, 0) + COALESCE(e.n_partial_codes, 0) > 0)          AS label_strict_partial,
       CASE WHEN COALESCE(e.n_strict_codes, 0) = 0 THEN FALSE
            WHEN g.gest_weeks IS NULL THEN NULL
            ELSE g.gest_weeks >= 22 END                                              AS label_ge22,
       CASE WHEN COALESCE(e.n_strict_codes, 0) = 0 THEN FALSE
            WHEN g.gest_weeks IS NULL THEN NULL
            ELSE g.gest_weeks >= 28 END                                              AS label_ge28,
       -- strict events that the population of D3 leaves out (see Q-T16b)
       (COALESCE(e.n_strict_codes, 0) > 0
        AND NOT (COALESCE(c.is_delivery_v2, FALSE) OR COALESCE(c.has_stillbirth_code, FALSE))) AS strict_outside_pop_d3,
       -- length of stay and flag of D8 (admission that ends before admission + 6 h)
       pr.los_hours,
       COALESCE(pr.los_hours < 6, FALSE)                                             AS ends_before_6h
FROM   mimiciv.cohort_obstetric_v2 c
JOIN   mimiciv.admissions a   ON a.hadm_id    = c.hadm_id
JOIN   mimiciv.patients   pt  ON pt.subject_id = c.subject_id
LEFT JOIN mimiciv.hadm_delivery_v2   dv ON dv.hadm_id = c.hadm_id
LEFT JOIN mimiciv.predictors_24h_v2  pr ON pr.hadm_id = c.hadm_id
LEFT JOIN ev  e ON e.hadm_id = c.hadm_id
LEFT JOIN z3a g ON g.hadm_id = c.hadm_id;

ALTER TABLE mimiciv.fetal_death_label_v2 ADD PRIMARY KEY (hadm_id);
CREATE INDEX idx_fetal_death_label_v2_subject ON mimiciv.fetal_death_label_v2 (subject_id);

-- ============================================================================
-- CHECKS (aggregate only) -- run each and paste the result
-- ============================================================================

-- Q-T16a. Integrity: one row per admission and the counts of the earlier audit
--   (expected: 25,736 rows and 25,736 distinct admissions; 154 events, 136 strict, 18 partial only;
--    population D3 19,440 with 142 events and 129 strict; 7 strict events outside the population;
--    11 events with an early-loss code)
SELECT 'Q-T16a integrity' AS q,
       COUNT(*)                                                AS n_rows,
       COUNT(DISTINCT hadm_id)                                 AS n_distinct_admissions,
       COUNT(*) FILTER (WHERE fd_any)                          AS n_events,
       COUNT(*) FILTER (WHERE fd_strict)                       AS n_strict,
       COUNT(*) FILTER (WHERE fd_partial_only)                 AS n_partial_only,
       COUNT(*) FILTER (WHERE in_pop_d3)                       AS n_population_d3,
       COUNT(*) FILTER (WHERE in_pop_d3 AND fd_any)            AS n_events_population_d3,
       COUNT(*) FILTER (WHERE in_pop_d3 AND fd_strict)         AS n_strict_population_d3,
       COUNT(*) FILTER (WHERE strict_outside_pop_d3)           AS n_strict_outside_population,
       COUNT(*) FILTER (WHERE fd_any AND has_early_loss_code)  AS n_events_with_early_loss_code
FROM   mimiciv.fetal_death_label_v2;

-- Q-T16b. The strict events outside the population of D3: which codes they carry and how far away the
--   next delivery admission of the same patient is (hypothesis: ICD-9 656.43 antepartum admissions whose delivery comes later)
WITH nxt AS (
    SELECT l.hadm_id,
           MIN(c2.admittime::date - l.admittime::date) AS days_to_next_delivery_adm
    FROM   mimiciv.fetal_death_label_v2 l
    JOIN   mimiciv.cohort_obstetric_v2 c2
           ON c2.subject_id = l.subject_id AND c2.admittime > l.admittime AND c2.is_delivery_v2
    WHERE  l.strict_outside_pop_d3
    GROUP  BY l.hadm_id
)
SELECT 'Q-T16b strict events outside population D3' AS q, l.icd_era,
       l.has_intrauterine_death_code, l.has_stillbirth_outcome_code, l.has_antepartum_6564_code,
       CASE WHEN n.days_to_next_delivery_adm IS NULL THEN '4 no later delivery admission'
            WHEN n.days_to_next_delivery_adm <= 7    THEN '1 within 7 days'
            WHEN n.days_to_next_delivery_adm <= 90   THEN '2 8 to 90 days'
            ELSE                                          '3 more than 90 days' END AS next_delivery_admission,
       COUNT(*) AS n_events
FROM   mimiciv.fetal_death_label_v2 l
LEFT JOIN nxt n ON n.hadm_id = l.hadm_id
WHERE  l.strict_outside_pop_d3
GROUP  BY 2, 3, 4, 5, 6 ORDER BY 2, 3, 4, 5, 6;

-- Q-T16c. Strict events by code family and era, inside and outside the population of D3
SELECT 'Q-T16c strict events by code family' AS q, icd_era, in_pop_d3,
       CASE WHEN has_intrauterine_death_code AND has_stillbirth_outcome_code THEN '3 both families'
            WHEN has_intrauterine_death_code                                  THEN '1 intrauterine death code only'
            ELSE                                                                   '2 stillbirth outcome code only' END AS code_family,
       COUNT(*)                                                 AS n_events,
       COUNT(*) FILTER (WHERE has_antepartum_6564_code)         AS n_with_antepartum_6564
FROM   mimiciv.fetal_death_label_v2
WHERE  fd_strict
GROUP  BY 2, 3, 4 ORDER BY 2, 3, 4;

-- Q-T16d. Position of the first strict code in the diagnosis list (1 = principal diagnosis), by code family
SELECT 'Q-T16d position of the strict code' AS q,
       CASE WHEN has_intrauterine_death_code AND has_stillbirth_outcome_code THEN '3 both families'
            WHEN has_intrauterine_death_code                                  THEN '1 intrauterine death code only'
            ELSE                                                                   '2 stillbirth outcome code only' END AS code_family,
       CASE WHEN min_strict_seq = 1  THEN '1 position 1'
            WHEN min_strict_seq <= 3 THEN '2 positions 2 to 3'
            WHEN min_strict_seq <= 10 THEN '3 positions 4 to 10'
            ELSE                           '4 position 11 or later' END AS position_band,
       COUNT(*) AS n_events
FROM   mimiciv.fetal_death_label_v2
WHERE  fd_strict AND in_pop_d3
GROUP  BY 2, 3 ORDER BY 2, 3;

-- Q-T16e. Events that also carry an early-loss code, by tier, abortive code and gestational band (population of D3)
SELECT 'Q-T16e events with early-loss code' AS q, fd_tier, has_early_loss_code, has_abortive_code, gest_band,
       COUNT(*) AS n_admissions
FROM   mimiciv.fetal_death_label_v2
WHERE  in_pop_d3 AND fd_any
GROUP  BY 2, 3, 4, 5 ORDER BY 2, 3, 4, 5;

-- Q-T16f. Size of every label definition (events and, where it applies, events of unknown gestational age)
SELECT 'Q-T16f label sizes' AS q, s.scope,
       COUNT(*)                                                                    AS n_admissions,
       COUNT(*) FILTER (WHERE l.label_main)                                        AS n_main_strict,
       COUNT(*) FILTER (WHERE l.label_strict_partial)                              AS n_strict_plus_partial,
       COUNT(*) FILTER (WHERE l.label_main AND NOT l.has_early_loss_code)          AS n_strict_without_early_loss_code,
       COUNT(*) FILTER (WHERE l.label_ge22)                                        AS n_ge22_weeks,
       COUNT(*) FILTER (WHERE l.fd_strict AND l.label_ge22 IS NULL)                AS n_strict_weeks_unknown,
       COUNT(*) FILTER (WHERE l.label_ge28)                                        AS n_ge28_weeks
FROM   mimiciv.fetal_death_label_v2 l
JOIN   LATERAL (VALUES ('1 population D3',                        l.in_pop_d3),
                       ('2 population D3, ICD-10 admissions only', l.in_pop_d3 AND l.icd_era = 'ICD-10 only'),
                       ('3 population D3, with Z3A weeks',         l.in_pop_d3 AND l.gest_weeks IS NOT NULL)
               ) s(scope, keep) ON s.keep
GROUP  BY 2 ORDER BY 2;

-- Q-T16g. Decision D8: admissions of the population that end before admission + 6 h, by event tier
SELECT 'Q-T16g D8 admissions shorter than 6 h' AS q, fd_tier,
       COUNT(*)                                       AS n_admissions,
       COUNT(*) FILTER (WHERE ends_before_6h)         AS n_end_before_6h,
       COUNT(*) FILTER (WHERE los_hours IS NULL)      AS n_los_missing
FROM   mimiciv.fetal_death_label_v2
WHERE  in_pop_d3
GROUP  BY 2 ORDER BY 2;
