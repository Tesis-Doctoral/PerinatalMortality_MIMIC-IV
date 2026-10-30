-- ============================================================================
-- 00_mimic_layer / 01_unit_of_analysis.sql
-- MIMIC-IV adapter of framework stage E4 (unit of analysis and overlap) -- plan v2, task T17
-- ============================================================================
-- Purpose: build mimiciv.unit_of_analysis_v2, ONE ROW PER ADMISSION of the revised obstetric
--   universe (mimiciv.cohort_obstetric_v2), with everything the method layer needs to define the
--   unit, the grouping, the timing and the overlap between records, and NOTHING about the outcome.
--   This script is OUTCOME-AGNOSTIC: no label, no event, no diagnosis code of an outcome.
--   The same table serves the fetal-death (perinatal) model and the maternal models; the outcome
--   modules (for example 01_labels/02_fetal_death_label_by_admission.sql) join to it by hadm_id.
--
-- Data contract of the framework (framework.md, section 3.1) -> columns of this table:
--   unit_id    = hadm_id                      (one record = one hospital admission)
--   group_id   = subject_id                   (all validation splits are grouped by patient)
--   t0         = admittime                    (time zero, decision D7)
--   t_pred     = admittime + 6 hours          (prediction point, decision D6)
--   t_end      = dischtime                    (end of the admission; the label has no event time)
--   period     = icd_era, anchor_year_group, approx_year_low
--   Overlap    = adm_rank, gap_days, chain_30 / chain_90 / chain_180 (pregnancy chains)
--   unit_id and group_id are duplicated aliases of hadm_id and subject_id on purpose: the method
--   layer reads the contract names, the joins to MIMIC tables read the native names.
--
-- Decisions applied:
--   D4  one record per delivery hospitalization, grouped by patient; the chain of admissions
--       linked by a gap of at most 90 days is a SENSITIVITY analysis -> columns chain_*.
--       The population (D3) is NOT applied here: it depends on a stillbirth code, which is part of
--       the outcome, so the flag in_pop_d3 stays in the label table. Here only is_delivery_v2.
--   D6  prediction point = admission + 6 h (the 6 is written once, in column t_pred).
--   D8  admissions that end before admission + 6 h are flagged (ends_before_6h), not deleted.
--
-- Definitions (the same as the count audit, Q-C2 and Q-C4, so the figures can be reproduced):
--   adm_rank   = order of the admission among the patient's admissions of the universe
--                (by admittime, ties broken by hadm_id).
--   gap_days   = calendar days between the admission date and the date of the previous admission
--                of the same patient (NULL for the first one). Date based, as in the audit.
--   chain_G    = number of the pregnancy chain of the patient: a new chain starts when the gap to
--                the previous admission is NULL or greater than G days (G = 30, 90, 180).
--   chainG_pos / chainG_n_adm / chainG_n_delivery / is_chainG_last (only G = 90, the one of D4).
--   Dates in MIMIC-IV are shifted per patient: gaps and lengths of stay are valid within a
--   patient, calendar years are not (hence anchor_year_group and approx_year_low).
--
-- Prerequisites: mimiciv.cohort_obstetric_v2 (maternal project, sql/04_labels), mimiciv.admissions,
--   mimiciv.patients. The checks Q-T17e also need mimiciv.fetal_death_label_v2 (task T16), and
--   Q-T17c / Q-T17d use its event column fd_any only to reproduce the audit figures.
--
-- Run the whole script in one connection (DBeaver: Alt+X). The table is persistent, so the checks
--   can be re-run alone. Only aggregate results are produced: do NOT publish rows with subject_id
--   or hadm_id.
-- ============================================================================

SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS mimiciv.unit_of_analysis_v2;

CREATE TABLE mimiciv.unit_of_analysis_v2 AS
WITH base AS (
    -- one row per admission of the universe, with order, gap and period
    SELECT c.subject_id,
           c.hadm_id,
           c.admittime,
           a.dischtime,
           COALESCE(c.is_delivery_v2, FALSE)                                         AS is_delivery_v2,
           CASE WHEN c.has_icd10_dx AND NOT c.has_icd9_dx THEN 'ICD-10 only'
                WHEN c.has_icd9_dx AND NOT c.has_icd10_dx THEN 'ICD-9 only'
                WHEN c.has_icd9_dx AND c.has_icd10_dx     THEN 'both'
                ELSE 'no diagnoses' END                                              AS icd_era,
           pt.anchor_year_group,
           CAST(LEFT(pt.anchor_year_group, 4) AS int)
             + (EXTRACT(YEAR FROM c.admittime)::int - pt.anchor_year)                AS approx_year_low,
           ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.admittime, c.hadm_id) AS adm_rank,
           COUNT(*)     OVER (PARTITION BY c.subject_id)                             AS n_adm_patient,
           (c.admittime::date - LAG(c.admittime::date)
                OVER (PARTITION BY c.subject_id ORDER BY c.admittime, c.hadm_id))    AS gap_days
    FROM   mimiciv.cohort_obstetric_v2 c
    JOIN   mimiciv.admissions a  ON a.hadm_id    = c.hadm_id
    JOIN   mimiciv.patients   pt ON pt.subject_id = c.subject_id
),
chains AS (
    -- chain number for each candidate gap limit: a new chain starts after a gap above the limit
    SELECT b.*,
           SUM(CASE WHEN b.gap_days IS NULL OR b.gap_days >  30 THEN 1 ELSE 0 END)
               OVER (PARTITION BY b.subject_id ORDER BY b.admittime, b.hadm_id) AS chain_30,
           SUM(CASE WHEN b.gap_days IS NULL OR b.gap_days >  90 THEN 1 ELSE 0 END)
               OVER (PARTITION BY b.subject_id ORDER BY b.admittime, b.hadm_id) AS chain_90,
           SUM(CASE WHEN b.gap_days IS NULL OR b.gap_days > 180 THEN 1 ELSE 0 END)
               OVER (PARTITION BY b.subject_id ORDER BY b.admittime, b.hadm_id) AS chain_180
    FROM   base b
),
chain90 AS (
    -- position and size of the 90-day chain (the one of decision D4)
    SELECT k.*,
           ROW_NUMBER() OVER (PARTITION BY k.subject_id, k.chain_90 ORDER BY k.admittime, k.hadm_id) AS chain90_pos,
           COUNT(*)     OVER (PARTITION BY k.subject_id, k.chain_90)                                 AS chain90_n_adm,
           COUNT(*) FILTER (WHERE k.is_delivery_v2)
                        OVER (PARTITION BY k.subject_id, k.chain_90)                                 AS chain90_n_delivery
    FROM   chains k
)
SELECT h.hadm_id                                                   AS unit_id,
       h.subject_id                                                AS group_id,
       h.hadm_id,
       h.subject_id,
       -- timing of the contract (D6, D7); the label has no event time
       h.admittime                                                 AS t0,
       h.admittime + INTERVAL '6 hours'                            AS t_pred,
       h.dischtime                                                 AS t_end,
       h.admittime,
       h.dischtime,
       EXTRACT(EPOCH FROM (h.dischtime - h.admittime)) / 3600.0    AS los_hours,
       COALESCE(h.dischtime < h.admittime + INTERVAL '6 hours', FALSE) AS ends_before_6h,
       -- period
       h.icd_era,
       h.anchor_year_group,
       h.approx_year_low,
       -- unit and overlap
       h.is_delivery_v2,
       h.adm_rank,
       (h.adm_rank = 1)                                            AS is_first_admission,
       h.n_adm_patient,
       h.gap_days,
       h.chain_30,
       h.chain_90,
       h.chain_180,
       h.chain90_pos,
       h.chain90_n_adm,
       h.chain90_n_delivery,
       (h.chain90_pos = h.chain90_n_adm)                           AS is_chain90_last
FROM   chain90 h;

ALTER TABLE mimiciv.unit_of_analysis_v2 ADD PRIMARY KEY (hadm_id);
CREATE INDEX idx_unit_of_analysis_v2_subject ON mimiciv.unit_of_analysis_v2 (subject_id);

-- ============================================================================
-- CHECKS (aggregate only) -- run each and paste the result
-- ============================================================================

-- Q-T17a. Integrity: one row per admission of the universe and the figures of the count audit
--         (expected: 25,736 units, 15,084 patients, 19,425 delivery hospitalizations, 15,084 first admissions)
SELECT 'Q-T17a integrity' AS q,
       COUNT(*)                                       AS n_rows,
       COUNT(DISTINCT hadm_id)                        AS n_units,
       COUNT(DISTINCT subject_id)                     AS n_patients,
       COUNT(*) FILTER (WHERE is_delivery_v2)         AS n_delivery_hosp,
       COUNT(*) FILTER (WHERE is_first_admission)     AS n_first_admission,
       (SELECT COUNT(*) FROM mimiciv.cohort_obstetric_v2) AS n_universe,
       COUNT(*) FILTER (WHERE t0 IS NULL OR t_end IS NULL)   AS n_time_missing,
       COUNT(*) FILTER (WHERE los_hours < 0)          AS n_negative_los,
       COUNT(*) FILTER (WHERE ends_before_6h)         AS n_end_before_6h
FROM   mimiciv.unit_of_analysis_v2;

-- Q-T17b. Pregnancy chains for each gap limit (expected chains: 23,257 / 22,080 / 21,485)
--         and chains that hold more than one delivery hospitalization (what the 90-day sensitivity of D4 changes)
SELECT 'Q-T17b pregnancy chains' AS q, g.gap_limit,
       COUNT(*)                                                      AS n_chains,
       COUNT(*) FILTER (WHERE c.n_adm > 1)                           AS n_chains_with_2plus_adm,
       MAX(c.n_adm)                                                  AS max_adm_in_chain,
       COUNT(*) FILTER (WHERE c.n_delivery >= 2)                     AS n_chains_with_2plus_deliveries
FROM  (VALUES (30), (90), (180)) AS g(gap_limit)
JOIN  LATERAL (
        SELECT u.subject_id,
               CASE g.gap_limit WHEN 30 THEN u.chain_30 WHEN 90 THEN u.chain_90 ELSE u.chain_180 END AS chain_id,
               COUNT(*)                                  AS n_adm,
               COUNT(*) FILTER (WHERE u.is_delivery_v2)  AS n_delivery
        FROM   mimiciv.unit_of_analysis_v2 u
        GROUP  BY 1, 2
      ) c ON TRUE
GROUP  BY g.gap_limit
ORDER  BY g.gap_limit;

-- Q-T17c. Gap to the previous admission of the same patient, with the events of the label table
--         (reproduces audit Q-C2; the event column comes from T16 and is used only to count)
SELECT 'Q-T17c gap to the previous admission' AS q,
       CASE WHEN u.gap_days IS NULL THEN '0 first admission of the patient'
            WHEN u.gap_days <  90   THEN '1 under 90 days'
            WHEN u.gap_days < 180   THEN '2 90-179 days'
            WHEN u.gap_days < 365   THEN '3 180-364 days'
            ELSE                         '4 365 days or more' END AS gap_to_previous_admission,
       COUNT(*)                         AS n_admissions,
       COUNT(*) FILTER (WHERE l.fd_any) AS n_events
FROM   mimiciv.unit_of_analysis_v2 u
LEFT JOIN mimiciv.fetal_death_label_v2 l ON l.hadm_id = u.hadm_id
GROUP  BY 2 ORDER BY 2;

-- Q-T17d. Gap to an EARLIER admission of the same patient that already carries an event
--         (reproduces audit Q-C3: 17 admissions and 5 events under 90 days)
WITH prior AS (
    SELECT u.hadm_id, MIN(u.admittime::date - e.admittime::date) AS days_since_prior_event
    FROM   mimiciv.unit_of_analysis_v2 u
    JOIN   mimiciv.unit_of_analysis_v2 e   ON e.subject_id = u.subject_id AND e.admittime < u.admittime
    JOIN   mimiciv.fetal_death_label_v2 le ON le.hadm_id = e.hadm_id AND le.fd_any
    GROUP  BY u.hadm_id
)
SELECT 'Q-T17d gap to an earlier event admission' AS q,
       CASE WHEN p.days_since_prior_event IS NULL THEN '0 no earlier event admission'
            WHEN p.days_since_prior_event <  90   THEN '1 under 90 days'
            WHEN p.days_since_prior_event < 180   THEN '2 90-179 days'
            WHEN p.days_since_prior_event < 365   THEN '3 180-364 days'
            ELSE                                       '4 365 days or more' END AS gap_to_earlier_event,
       COUNT(*)                          AS n_admissions,
       COUNT(*) FILTER (WHERE l.fd_any)  AS n_events
FROM   mimiciv.unit_of_analysis_v2 u
LEFT JOIN prior p ON p.hadm_id = u.hadm_id
LEFT JOIN mimiciv.fetal_death_label_v2 l ON l.hadm_id = u.hadm_id
GROUP  BY 2 ORDER BY 2;

-- Q-T17e. Consistency with the label table (T16): same units, same flag of D8, same era and anchor group
--         (expected: every mismatch = 0)
SELECT 'Q-T17e consistency with the label table' AS q,
       COUNT(*) FILTER (WHERE l.hadm_id IS NULL)                              AS n_unit_only,
       (SELECT COUNT(*) FROM mimiciv.fetal_death_label_v2 x
         WHERE NOT EXISTS (SELECT 1 FROM mimiciv.unit_of_analysis_v2 y WHERE y.hadm_id = x.hadm_id)) AS n_label_only,
       COUNT(*) FILTER (WHERE u.ends_before_6h IS DISTINCT FROM l.ends_before_6h) AS n_mismatch_d8_flag,
       COUNT(*) FILTER (WHERE u.icd_era IS DISTINCT FROM l.icd_era)           AS n_mismatch_icd_era,
       COUNT(*) FILTER (WHERE u.anchor_year_group IS DISTINCT FROM l.anchor_year_group) AS n_mismatch_anchor,
       COUNT(*) FILTER (WHERE u.is_delivery_v2 IS DISTINCT FROM l.is_delivery_v2) AS n_mismatch_delivery,
       COUNT(*) FILTER (WHERE ABS(u.los_hours - l.los_hours) > 0.01)          AS n_mismatch_los_hours
FROM   mimiciv.unit_of_analysis_v2 u
LEFT JOIN mimiciv.fetal_death_label_v2 l ON l.hadm_id = u.hadm_id;

-- Q-T17f. Overlapping or tied admissions of the same patient (an admission that starts before the previous
--         one ends, or at the same minute): they affect the order and the chain, so they are reported
WITH o AS (
    SELECT u.hadm_id, u.admittime,
           LAG(u.dischtime) OVER (PARTITION BY u.subject_id ORDER BY u.admittime, u.hadm_id) AS prev_dischtime,
           LAG(u.admittime) OVER (PARTITION BY u.subject_id ORDER BY u.admittime, u.hadm_id) AS prev_admittime
    FROM   mimiciv.unit_of_analysis_v2 u
)
SELECT 'Q-T17f overlaps and ties' AS q,
       COUNT(*) FILTER (WHERE prev_admittime IS NOT NULL)                          AS n_with_previous,
       COUNT(*) FILTER (WHERE admittime < prev_dischtime)                          AS n_starts_before_previous_ends,
       COUNT(*) FILTER (WHERE admittime = prev_admittime)                          AS n_same_admittime_as_previous
FROM   o;

-- Q-T17g. Admissions per patient and length of stay by delivery flag: does the prediction point (admission + 6 h)
--         fall inside the admission? (the flag of D8 for the whole universe, not only for the population of D3)
SELECT 'Q-T17g prediction point inside the admission' AS q, is_delivery_v2,
       COUNT(*)                                                   AS n_admissions,
       COUNT(*) FILTER (WHERE ends_before_6h)                     AS n_end_before_6h,
       ROUND(AVG(los_hours)::numeric, 1)                          AS mean_los_hours,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_hours))::numeric, 1) AS median_los_hours,
       ROUND(AVG(n_adm_patient)::numeric, 2)                      AS mean_adm_per_patient
FROM   mimiciv.unit_of_analysis_v2
GROUP  BY ROLLUP (is_delivery_v2)
ORDER  BY is_delivery_v2 NULLS LAST;
