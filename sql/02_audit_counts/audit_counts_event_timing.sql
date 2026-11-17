-- ============================================================================
-- COUNT AUDIT, group G (timing of the fetal-death event) -- fetal-death models (plan v2, task T45)
-- Framework: stage S3 (outcome definition: event timing) and gate G1; prepares criteria C1 and C2 of gate G4
-- ============================================================================
-- Purpose: the fetal-death label is a discharge code and carries NO event time. Criterion C1
-- (events already present at the prediction point) needs a landmark population without the
-- deaths already present at T, and criterion C2 (outcome with time) needs events dated after T.
-- This script COUNTS the proxies that could place each event in time, for events and
-- non-events, so that the timing rule is fixed with numbers and before any model
-- (outcome card, docs/outcome_card_fetal_death.md, section 5).
--
-- Proxies counted (none of them is used as a predictor):
--   P1 intrauterine-death code (ICD-10 O36.4, ICD-9 656.4): care for a fetal death already known
--      during the stay, i.e. death before labor (antepartum); untimed.
--   P2 fetal-death code as principal diagnosis (seq_num = 1): the death was the reason for the
--      admission; untimed (assigned after discharge).
--   P3 laboratory work-up of a fetal death with a TIME: fetal hemoglobin / Kleihauer-Betke and
--      related items found in d_labitems by name (Q-G2 lists them; check each item before use).
--   P4 medication with a TIME: mifepristone (used for fetal demise or termination, rarely for
--      induction of a live pregnancy) and misoprostol (also used for induction and hemorrhage,
--      so it is NOT specific) in prescriptions.
--   P5 delivery procedure dated on the admission day (date only, no time).
-- Prediction point T = admission time + 6 h (decision D6). Population of decision D3 without
-- the admissions that end before T (decision D8).
--
-- READ-ONLY: it only creates temporary tables and runs SELECTs. Results are aggregated counts;
-- do NOT publish rows with subject_id or hadm_id, and replace counts under 5 by "<5" in any
-- published file (decision D13).
--
-- Prerequisites: mimiciv.fetal_death_label_v2 (task T16, sql/01_labels/02_...), MIMIC-IV hosp
-- tables admissions, labevents, d_labitems, prescriptions, procedures_icd.
-- Q-G3 reads labevents and Q-G4 reads prescriptions only for the admissions of the
-- population (each can take a few minutes).
--
-- Run the whole script in ONE connection (DBeaver: Alt+X): the temporary tables must survive
-- between statements. Each result set starts with a label column q.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0. Working tables
-- ----------------------------------------------------------------------------
-- Population of D3 still in hospital at T (D8), with the label and the untimed proxies P1 and P2
DROP TABLE IF EXISTS tmp_ft_base;
CREATE TEMP TABLE tmp_ft_base AS
SELECT l.subject_id, l.hadm_id, l.admittime, l.dischtime,
       l.admittime + INTERVAL '6 hours'                                   AS t_pred,
       a.edregtime,
       l.icd_era,
       l.fd_strict,
       l.fd_any,
       CASE WHEN l.fd_strict THEN '1 strict event'
            WHEN l.fd_any    THEN '2 partial-only event'
            ELSE                  '3 non-event' END                       AS ev_group,
       l.has_intrauterine_death_code                                      AS p1_intrauterine_code,
       (l.fd_strict AND l.min_strict_seq = 1)                             AS p2_principal_dx,
       l.has_stillbirth_outcome_code,
       l.has_early_loss_code,
       l.gest_band
FROM   mimiciv.fetal_death_label_v2 l
JOIN   mimiciv.admissions a ON a.hadm_id = l.hadm_id
WHERE  l.in_pop_d3
  AND  NOT l.ends_before_6h;

-- Candidate laboratory items of a fetal-death work-up, found by name (P3)
DROP TABLE IF EXISTS tmp_ft_labitems;
CREATE TEMP TABLE tmp_ft_labitems AS
SELECT itemid, label, fluid, category
FROM   mimiciv.d_labitems
WHERE  label ILIKE '%fetal hemoglobin%'
   OR  label ILIKE '%fetal hgb%'
   OR  label ILIKE '%kleihauer%'
   OR  label ILIKE '%fetal cell%'
   OR  label ILIKE '%fetal screen%'
   OR  label ILIKE '%fetal-maternal%'
   OR  label ILIKE '%fetomaternal%';

-- First value of each candidate item per admission (window: 24 h before admission until discharge)
DROP TABLE IF EXISTS tmp_ft_lab;
CREATE TEMP TABLE tmp_ft_lab AS
SELECT b.hadm_id, li.itemid, li.label, MIN(le.charttime) AS first_time
FROM   tmp_ft_base b
JOIN   mimiciv.labevents le
       ON  le.subject_id = b.subject_id
       AND le.charttime >= b.admittime - INTERVAL '24 hours'
       AND le.charttime <= b.dischtime
       AND (le.hadm_id = b.hadm_id OR le.hadm_id IS NULL)
JOIN   tmp_ft_labitems li ON li.itemid = le.itemid
GROUP  BY b.hadm_id, li.itemid, li.label;

-- First start of mifepristone and of misoprostol per admission (P4)
DROP TABLE IF EXISTS tmp_ft_med;
CREATE TEMP TABLE tmp_ft_med AS
SELECT p.hadm_id,
       MIN(p.starttime) FILTER (WHERE p.drug ILIKE '%mifepris%' OR p.drug ILIKE '%mifeprex%') AS first_mifepristone,
       MIN(p.starttime) FILTER (WHERE p.drug ILIKE '%misopros%' OR p.drug ILIKE '%cytotec%')  AS first_misoprostol
FROM   mimiciv.prescriptions p
WHERE  p.hadm_id IN (SELECT hadm_id FROM tmp_ft_base)
GROUP  BY p.hadm_id;

-- First delivery procedure date (P5; same delivery list as hadm_delivery_v2 and audit_counts_timing.sql)
DROP TABLE IF EXISTS tmp_ft_proc;
CREATE TEMP TABLE tmp_ft_proc AS
SELECT p.hadm_id,
       MIN(p.chartdate::date) FILTER (WHERE
              (p.icd_version = 10 AND p.icd_code IN ('10D00Z0','10D00Z1','10D00Z2','10E0XZZ',
                                                     '10D07Z3','10D07Z4','10D07Z5','10D07Z6','10D07Z7','10D07Z8'))
           OR (p.icd_version = 9  AND (p.icd_code LIKE '720%' OR p.icd_code LIKE '721%' OR p.icd_code LIKE '7221%'
                                        OR p.icd_code LIKE '7229%' OR p.icd_code LIKE '7231%' OR p.icd_code LIKE '7239%'
                                        OR p.icd_code LIKE '724%' OR p.icd_code LIKE '726%'
                                        OR p.icd_code IN ('7251','7252','7253','7254','7271','7279')
                                        OR p.icd_code LIKE '728%' OR p.icd_code LIKE '729%'
                                        OR p.icd_code LIKE '7322%' OR p.icd_code LIKE '7359%' OR p.icd_code LIKE '736%'
                                        OR p.icd_code LIKE '740%' OR p.icd_code LIKE '741%' OR p.icd_code LIKE '742%'
                                        OR p.icd_code LIKE '744%' OR p.icd_code LIKE '7499%'))
       ) AS first_delivery_proc_date
FROM   mimiciv.procedures_icd p
WHERE  p.hadm_id IN (SELECT hadm_id FROM tmp_ft_base)
GROUP  BY p.hadm_id;

-- One row per admission with every proxy as a column
DROP TABLE IF EXISTS tmp_ft_proxy;
CREATE TEMP TABLE tmp_ft_proxy AS
SELECT b.*,
       lb.first_lab_time,
       (lb.first_lab_time IS NOT NULL AND lb.first_lab_time <= b.t_pred)     AS p3_lab_by_t,
       (lb.first_lab_time IS NOT NULL AND lb.first_lab_time >  b.t_pred)     AS p3_lab_after_t,
       m.first_mifepristone,
       m.first_misoprostol,
       (m.first_mifepristone IS NOT NULL AND m.first_mifepristone <= b.t_pred) AS p4_mifepristone_by_t,
       (m.first_misoprostol  IS NOT NULL AND m.first_misoprostol  <= b.t_pred) AS p4_misoprostol_by_t,
       (pr.first_delivery_proc_date IS NOT NULL
        AND pr.first_delivery_proc_date - b.admittime::date = 0)             AS p5_delivery_day0
FROM   tmp_ft_base b
LEFT JOIN (SELECT hadm_id, MIN(first_time) AS first_lab_time FROM tmp_ft_lab GROUP BY hadm_id) lb
       ON lb.hadm_id = b.hadm_id
LEFT JOIN tmp_ft_med  m  ON m.hadm_id  = b.hadm_id
LEFT JOIN tmp_ft_proc pr ON pr.hadm_id = b.hadm_id;

-- ============================================================================
-- GROUP G -- timing of the fetal-death event
-- ============================================================================

-- Q-G0. Population check (expected: 19,437 admissions; 129 strict events; 142 events with partial codes)
SELECT 'Q-G0 population check' AS q,
       COUNT(*)                          AS n_admissions,
       COUNT(*) FILTER (WHERE fd_strict) AS n_strict,
       COUNT(*) FILTER (WHERE fd_any)    AS n_events_any
FROM   tmp_ft_base;

-- Q-G1. Untimed proxies P1 and P2 among strict events, by code family and ICD era
SELECT 'Q-G1 untimed proxies (strict events)' AS q, icd_era, code_family,
       COUNT(*)                                        AS n_events,
       COUNT(*) FILTER (WHERE p2_principal_dx)         AS n_principal_dx,
       COUNT(*) FILTER (WHERE edregtime IS NOT NULL)   AS n_with_ed_registration
FROM  (SELECT b.*,
              CASE WHEN p1_intrauterine_code AND has_stillbirth_outcome_code THEN '3 both families'
                   WHEN p1_intrauterine_code                                  THEN '1 intrauterine death code only'
                   ELSE                                                            '2 stillbirth outcome code only' END AS code_family
       FROM   tmp_ft_base b
       WHERE  b.fd_strict) s
GROUP  BY ROLLUP (icd_era, code_family)
ORDER  BY icd_era NULLS LAST, code_family NULLS LAST;

-- Q-G2. Candidate laboratory items of the work-up (P3): how many admissions have each item, by event group.
--       Check the list: an item for Rh-negative screening (fetal cell screen, rosette) is ordered after
--       many normal deliveries and is NOT specific of a fetal death.
SELECT 'Q-G2 candidate work-up laboratory items' AS q, li.itemid, li.label, li.fluid, li.category,
       COUNT(DISTINCT lb.hadm_id) FILTER (WHERE b.fd_strict)            AS n_strict_events_with_item,
       COUNT(DISTINCT lb.hadm_id) FILTER (WHERE b.ev_group = '3 non-event') AS n_non_events_with_item
FROM   tmp_ft_labitems li
LEFT JOIN tmp_ft_lab  lb ON lb.itemid = li.itemid
LEFT JOIN tmp_ft_base b  ON b.hadm_id = lb.hadm_id
GROUP  BY li.itemid, li.label, li.fluid, li.category
ORDER  BY li.label;

-- Q-G3. Time of the first work-up laboratory value relative to T (hours), by item and event group
SELECT 'Q-G3 first work-up laboratory value relative to T' AS q, lb.itemid, lb.label, b.ev_group,
       COUNT(*)                                                                         AS n_admissions_with_value,
       COUNT(*) FILTER (WHERE lb.first_time <= b.t_pred)                                AS n_by_t,
       COUNT(*) FILTER (WHERE lb.first_time >  b.t_pred
                          AND lb.first_time <= b.admittime + INTERVAL '24 hours')       AS n_t_to_24h,
       COUNT(*) FILTER (WHERE lb.first_time >  b.admittime + INTERVAL '24 hours')       AS n_after_24h,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (lb.first_time - b.admittime)) / 3600.0)::numeric, 1) AS median_hours_from_admission
FROM   tmp_ft_lab lb
JOIN   tmp_ft_base b ON b.hadm_id = lb.hadm_id
GROUP  BY lb.itemid, lb.label, b.ev_group
ORDER  BY lb.label, lb.itemid, b.ev_group;

-- Q-G4. Mifepristone and misoprostol (P4): admissions with a prescription, and with a start at or before T, by event group
SELECT 'Q-G4 mifepristone and misoprostol' AS q, ev_group,
       COUNT(*)                                                       AS n_admissions,
       COUNT(*) FILTER (WHERE first_mifepristone IS NOT NULL)         AS n_mifepristone,
       COUNT(*) FILTER (WHERE p4_mifepristone_by_t)                   AS n_mifepristone_by_t,
       COUNT(*) FILTER (WHERE first_misoprostol IS NOT NULL)          AS n_misoprostol,
       COUNT(*) FILTER (WHERE p4_misoprostol_by_t)                    AS n_misoprostol_by_t,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (first_mifepristone - admittime)) / 3600.0)::numeric, 1) AS median_hours_to_mifepristone
FROM   tmp_ft_proxy
GROUP  BY ROLLUP (ev_group)
ORDER  BY ev_group NULLS LAST;

-- Q-G5. How often each proxy is found, events against non-events (specificity check: a proxy that is
--       frequent among non-events cannot mark a fetal death already present)
SELECT 'Q-G5 proxies in events and non-events' AS q, ev_group,
       COUNT(*)                                          AS n_admissions,
       COUNT(*) FILTER (WHERE p1_intrauterine_code)      AS n_p1_intrauterine_code,
       COUNT(*) FILTER (WHERE p2_principal_dx)           AS n_p2_principal_dx,
       COUNT(*) FILTER (WHERE p3_lab_by_t)               AS n_p3_lab_by_t,
       COUNT(*) FILTER (WHERE p3_lab_after_t)            AS n_p3_lab_after_t,
       COUNT(*) FILTER (WHERE p4_mifepristone_by_t)      AS n_p4_mifepristone_by_t,
       COUNT(*) FILTER (WHERE p4_misoprostol_by_t)       AS n_p4_misoprostol_by_t,
       COUNT(*) FILTER (WHERE p5_delivery_day0)          AS n_p5_delivery_day0
FROM   tmp_ft_proxy
GROUP  BY ev_group
ORDER  BY ev_group;

-- Q-G6. Candidate timing classes of the strict events (PROPOSAL, to be confirmed with Q-G2 to Q-G5).
--   1 present at T, timed     : a work-up laboratory value or mifepristone at or before T
--   2 present at T, by code   : intrauterine-death code as principal diagnosis (no timed evidence)
--   3 antepartum, time unknown: intrauterine-death code not principal (no timed evidence)
--   4 indeterminate           : stillbirth outcome code only, no timed evidence at or before T
--   No class "documented after T" is proposed: no source in these tables can date a death after T.
--   Class 1 uses every item of Q-G2: drop the non-specific items from tmp_ft_labitems before reading it.
SELECT 'Q-G6 candidate timing classes (strict events)' AS q, timing_class,
       COUNT(*)                                                AS n_events,
       COUNT(*) FILTER (WHERE icd_era = 'ICD-10 only')         AS n_icd10,
       COUNT(*) FILTER (WHERE has_early_loss_code)             AS n_with_early_loss_code,
       COUNT(*) FILTER (WHERE gest_band IN ('22 to 27', '28 or more')) AS n_22_weeks_or_more,
       COUNT(*) FILTER (WHERE p3_lab_after_t)                  AS n_work_up_only_after_t
FROM  (SELECT p.*,
              CASE WHEN p3_lab_by_t OR p4_mifepristone_by_t           THEN '1 present at T, timed'
                   WHEN p1_intrauterine_code AND p2_principal_dx      THEN '2 present at T, by code'
                   WHEN p1_intrauterine_code                          THEN '3 antepartum, time unknown'
                   ELSE                                                    '4 indeterminate' END AS timing_class
       FROM   tmp_ft_proxy p
       WHERE  p.fd_strict) s
GROUP  BY ROLLUP (timing_class)
ORDER  BY timing_class NULLS LAST;
