-- ============================================================================
-- 03_antenatal / 02_fetal_death_label.sql
-- Fetal-death code catalogue and label by admission of the antenatal model (task A0)
-- Framework: stage S3 (outcome definition); its reference counts are checked at gate G1
-- ============================================================================
-- Purpose:
--   1. mimiciv.antenatal_fetal_death_codes: catalogue of fetal-death code patterns, each with
--      its official title, tier (strict / partial / excluded) and source.
--   2. mimiciv.antenatal_fetal_death_label: ONE ROW PER ADMISSION of the obstetric universe
--      (script 01), with the main label and the sensitivity definitions as COLUMNS, not filters.
--   The label carries NO event time: it is a discharge diagnosis code.
--
-- Code sources (checked on 2026-10-28):
--   ICD-10-CM: O36.4, O02.1, P95, Z37 and O31.2 (AAPC, Kodex), Z3A (findacode.com).
--     O36.4 "Maternal care for intrauterine death" (inclusion term: after completion of 20 weeks);
--     O02.1 "Missed abortion" (early fetal death before 20 weeks); Z37 is an additional code for
--     the outcome of delivery on the mother's record; P95 belongs to newborn records only.
--   WHO ICD-10 2019 browser: O36.4, Z37, P95.
--   ICD-9-CM (icd9data.com): V27.x; 656.4 "Intrauterine death affecting management of mother"
--     (after completion of 22 weeks); 632 "Missed abortion"; 768.0 and 768.1 (newborn records).
--
-- Tiers
--   strict    fetal death of the whole pregnancy at an obstetric stage (main definition)
--   partial   one or more fetuses died while others were liveborn or the pregnancy continued
--             (sensitivity only)
--   excluded  listed for audit, never used by the labels: early (pre-viable) fetal death and
--             codes that belong to newborn records
-- Conventions: MIMIC-IV stores codes without dots; patterns are prefixes (icd_code LIKE pattern || '%').
--
-- Label columns
--   in_population         delivery hospitalization OR stillbirth code (population of the model)
--   label_main            strict code at any gestational age (main definition)
--   label_strict_partial  strict or partial code (sensitivity)
--   label_ge22, label_ge28  strict code at 22 or 28 completed weeks or more; NULL for a strict
--                         event without gestational weeks (Z3A codes exist only in ICD-10)
--   has_early_loss_code   early-loss code present (sensitivity: exclude these events)
--
-- Prerequisite: script 01 of this folder (mimiciv.antenatal_obstetric_universe).
-- Run the whole script in one connection (DBeaver: Alt+X). Only aggregate results are produced:
-- do NOT publish rows with subject_id or hadm_id.
-- ============================================================================

SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS mimiciv.antenatal_fetal_death_label;
DROP TABLE IF EXISTS mimiciv.antenatal_fetal_death_codes;

-- ----------------------------------------------------------------------------
-- 1. Code catalogue
-- ----------------------------------------------------------------------------
CREATE TABLE mimiciv.antenatal_fetal_death_codes (
    code_group       VARCHAR(50),
    icd_version      SMALLINT,       -- 9 | 10
    code_pattern     VARCHAR(10),    -- no dots, as stored in MIMIC-IV
    tier             VARCHAR(10),    -- 'strict' | 'partial' | 'excluded'
    official_title   VARCHAR(120),
    gestational_note VARCHAR(160),
    source_note      VARCHAR(80)
);

INSERT INTO mimiciv.antenatal_fetal_death_codes
    (code_group, icd_version, code_pattern, tier, official_title, gestational_note, source_note) VALUES
-- ICD-10-CM
('Intrauterine death',                    10, 'O364', 'strict',   'Maternal care for intrauterine death', 'Inclusion term: after completion of 20 weeks of gestation', 'ICD-10-CM O36.4; WHO ICD-10 2019'),
('Stillbirth outcome of delivery',        10, 'Z371', 'strict',   'Single stillbirth', NULL, 'ICD-10-CM Z37; WHO ICD-10 2019'),
('Stillbirth outcome of delivery',        10, 'Z374', 'strict',   'Twins, both stillborn', NULL, 'ICD-10-CM Z37; WHO ICD-10 2019'),
('Stillbirth outcome of delivery',        10, 'Z377', 'strict',   'Other multiple births, all stillborn', NULL, 'ICD-10-CM Z37; WHO ICD-10 2019'),
('Mixed outcome of a multiple pregnancy', 10, 'Z373', 'partial',  'Twins, one liveborn and one stillborn', NULL, 'ICD-10-CM Z37; WHO ICD-10 2019'),
('Mixed outcome of a multiple pregnancy', 10, 'Z376', 'partial',  'Other multiple births, some liveborn', NULL, 'ICD-10-CM Z37; WHO ICD-10 2019'),
('Mixed outcome of a multiple pregnancy', 10, 'O312', 'partial',  'Continuing pregnancy after intrauterine death of one fetus or more', NULL, 'ICD-10-CM O31.2'),
('Early fetal death (pre-viable)',        10, 'O021', 'excluded', 'Missed abortion', 'Early fetal death, before completion of 20 weeks of gestation, with retention of dead fetus', 'ICD-10-CM O02.1'),
('Newborn-record code',                   10, 'P95',  'excluded', 'Stillbirth', 'Chapter P: for use on newborn records only, never on maternal records', 'ICD-10-CM P95; WHO ICD-10 2019'),
-- ICD-9-CM
('Intrauterine death',                    9,  '6564', 'strict',   'Intrauterine death affecting management of mother', 'Fetal death after completion of 22 weeks gestation, late; missed delivery', 'ICD-9-CM 656.4'),
('Stillbirth outcome of delivery',        9,  'V271', 'strict',   'Outcome of delivery, single stillborn', NULL, 'ICD-9-CM V27'),
('Stillbirth outcome of delivery',        9,  'V274', 'strict',   'Outcome of delivery, twins, both stillborn', NULL, 'ICD-9-CM V27'),
('Stillbirth outcome of delivery',        9,  'V277', 'strict',   'Outcome of delivery, other multiple birth, all stillborn', NULL, 'ICD-9-CM V27'),
('Mixed outcome of a multiple pregnancy', 9,  'V273', 'partial',  'Outcome of delivery, twins, one liveborn and one stillborn', NULL, 'ICD-9-CM V27'),
('Mixed outcome of a multiple pregnancy', 9,  'V276', 'partial',  'Outcome of delivery, other multiple birth, some liveborn', NULL, 'ICD-9-CM V27'),
('Early fetal death (pre-viable)',        9,  '632',  'excluded', 'Missed abortion', 'Early fetal death before completion of 22 weeks gestation with retention of dead fetus', 'ICD-9-CM 632'),
('Newborn-record code',                   9,  '7680', 'excluded', 'Fetal death from asphyxia or anoxia before onset of labor or at unspecified time', 'Perinatal chapter (newborn records)', 'ICD-9-CM 768.0'),
('Newborn-record code',                   9,  '7681', 'excluded', 'Fetal death from asphyxia or anoxia during labor', 'Perinatal chapter (newborn records)', 'ICD-9-CM 768.1');

-- ----------------------------------------------------------------------------
-- 2. Label by admission
-- ----------------------------------------------------------------------------
CREATE TABLE mimiciv.antenatal_fetal_death_label AS
WITH hits AS (
    SELECT d.hadm_id, d.icd_version, d.icd_code, d.seq_num, c.tier, c.code_group
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.antenatal_fetal_death_codes c
           ON c.icd_version = d.icd_version AND d.icd_code LIKE c.code_pattern || '%'
    WHERE  d.hadm_id IN (SELECT hadm_id FROM mimiciv.antenatal_obstetric_universe)
),
ev AS (
    SELECT hadm_id,
           COUNT(*) FILTER (WHERE tier = 'strict')                                   AS n_strict_codes,
           COUNT(*) FILTER (WHERE tier = 'partial')                                  AS n_partial_codes,
           MIN(seq_num) FILTER (WHERE tier = 'strict')                               AS min_strict_seq,
           BOOL_OR(tier = 'strict' AND code_group = 'Intrauterine death')            AS has_intrauterine_death_code,
           BOOL_OR(tier = 'strict' AND code_group = 'Stillbirth outcome of delivery') AS has_stillbirth_outcome_code,
           BOOL_OR(code_group = 'Early fetal death (pre-viable)')                    AS has_early_loss_code,
           BOOL_OR(code_group = 'Newborn-record code')                               AS has_newborn_record_code
    FROM   hits
    GROUP  BY hadm_id
),
z3a AS (
    -- gestational weeks from Z3A.xx (ICD-10 only); Z3A.00 and Z3A.01 = unspecified or under 8 weeks
    SELECT hadm_id,
           MAX(CASE WHEN substring(icd_code FROM 4 FOR 2)::INT >= 8
                    THEN substring(icd_code FROM 4 FOR 2)::INT END)                  AS gest_weeks
    FROM   mimiciv.diagnoses_icd
    WHERE  icd_version = 10 AND icd_code ~ '^Z3A[0-9]{2}'
      AND  hadm_id IN (SELECT hadm_id FROM mimiciv.antenatal_obstetric_universe)
    GROUP  BY hadm_id
)
SELECT u.subject_id,
       u.hadm_id,
       u.admittime,
       u.dischtime,
       -- population
       u.is_delivery,
       u.has_stillbirth_code,
       (u.is_delivery OR u.has_stillbirth_code)                                      AS in_population,
       u.has_abortive_code,
       -- event and tier
       (COALESCE(e.n_strict_codes, 0) > 0)                                           AS fd_strict,
       (COALESCE(e.n_strict_codes, 0) + COALESCE(e.n_partial_codes, 0) > 0)          AS fd_any,
       CASE WHEN COALESCE(e.n_strict_codes, 0) > 0  THEN 'strict'
            WHEN COALESCE(e.n_partial_codes, 0) > 0 THEN 'partial only'
            ELSE                                         'no event' END              AS fd_tier,
       COALESCE(e.has_intrauterine_death_code, FALSE)                                AS has_intrauterine_death_code,
       COALESCE(e.has_stillbirth_outcome_code, FALSE)                                AS has_stillbirth_outcome_code,
       e.min_strict_seq,
       COALESCE(e.has_early_loss_code, FALSE)                                        AS has_early_loss_code,
       COALESCE(e.has_newborn_record_code, FALSE)                                    AS has_newborn_record_code,
       -- gestational age (ICD-10 only)
       g.gest_weeks,
       CASE WHEN g.gest_weeks IS NULL THEN 'unknown'
            WHEN g.gest_weeks < 22    THEN 'under 22'
            WHEN g.gest_weeks < 28    THEN '22 to 27'
            ELSE                           '28 or more' END                          AS gest_band,
       -- coding era and anchor-year group
       CASE WHEN u.has_icd10_dx AND NOT u.has_icd9_dx THEN 'ICD-10 only'
            WHEN u.has_icd9_dx AND NOT u.has_icd10_dx THEN 'ICD-9 only'
            WHEN u.has_icd9_dx AND u.has_icd10_dx     THEN 'both'
            ELSE 'no diagnoses' END                                                  AS icd_era,
       pt.anchor_year_group,
       -- labels: main definition and sensitivity definitions as columns
       (COALESCE(e.n_strict_codes, 0) > 0)                                           AS label_main,
       (COALESCE(e.n_strict_codes, 0) + COALESCE(e.n_partial_codes, 0) > 0)          AS label_strict_partial,
       CASE WHEN COALESCE(e.n_strict_codes, 0) = 0 THEN FALSE
            WHEN g.gest_weeks IS NULL THEN NULL
            ELSE g.gest_weeks >= 22 END                                              AS label_ge22,
       CASE WHEN COALESCE(e.n_strict_codes, 0) = 0 THEN FALSE
            WHEN g.gest_weeks IS NULL THEN NULL
            ELSE g.gest_weeks >= 28 END                                              AS label_ge28
FROM   mimiciv.antenatal_obstetric_universe u
JOIN   mimiciv.patients pt ON pt.subject_id = u.subject_id
LEFT JOIN ev  e ON e.hadm_id = u.hadm_id
LEFT JOIN z3a g ON g.hadm_id = u.hadm_id;

ALTER TABLE mimiciv.antenatal_fetal_death_label ADD PRIMARY KEY (hadm_id);
CREATE INDEX ON mimiciv.antenatal_fetal_death_label (subject_id);

-- ============================================================================
-- CHECKS (aggregate only)
-- ============================================================================

-- Q-L1. Catalogue: patterns by tier and ICD version (expected, ICD-9 + ICD-10: strict 4 + 4, partial 2 + 3, excluded 3 + 2)
SELECT 'Q-L1 code patterns by tier' AS q, tier, icd_version, COUNT(*) AS n_patterns
FROM   mimiciv.antenatal_fetal_death_codes
GROUP  BY 2, 3 ORDER BY 2, 3;

-- Q-L2. Reference counts of the population (expected: 19,440 admissions, 13,735 patients,
--       129 strict events, 142 events with partial codes)
SELECT 'Q-L2 reference counts' AS q,
       COUNT(*)                          AS n_admissions,
       COUNT(DISTINCT subject_id)        AS n_patients,
       COUNT(*) FILTER (WHERE fd_strict) AS n_strict,
       COUNT(*) FILTER (WHERE fd_any)    AS n_events_any
FROM   mimiciv.antenatal_fetal_death_label
WHERE  in_population;

-- Q-L3. Size of every label definition in the population
SELECT 'Q-L3 label sizes' AS q,
       COUNT(*) FILTER (WHERE label_main)                                     AS n_main_strict,
       COUNT(*) FILTER (WHERE label_strict_partial)                           AS n_strict_plus_partial,
       COUNT(*) FILTER (WHERE label_main AND NOT has_early_loss_code)         AS n_strict_without_early_loss_code,
       COUNT(*) FILTER (WHERE label_ge22)                                     AS n_ge22_weeks,
       COUNT(*) FILTER (WHERE label_ge28)                                     AS n_ge28_weeks,
       COUNT(*) FILTER (WHERE fd_strict AND label_ge22 IS NULL)               AS n_strict_weeks_unknown,
       COUNT(*) FILTER (WHERE fd_strict AND has_newborn_record_code)          AS n_strict_with_newborn_record_code
FROM   mimiciv.antenatal_fetal_death_label
WHERE  in_population;
