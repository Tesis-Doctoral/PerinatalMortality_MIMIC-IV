-- ============================================================================
-- 01_labels / 01_fetal_death_codes_official.sql
-- Verified fetal-death code catalogue (ICD-9-CM + ICD-10-CM) -- plan v2, task T15
-- ============================================================================
-- Purpose: replace the provisional list of 13 code patterns inherited from the legacy
--   scripts by a documented catalogue (table fetal_death_code_patterns_v2) in which every
--   pattern carries its official title, its tier (strict / partial / excluded) and its source.
--   The old table mimiciv.fetal_death_code_patterns is NOT touched.
--
-- Sources (checked 2026-10-28; the pages reproduce the US code sets, the CDC and CMS files
--   themselves were not downloaded and should be cross-checked before submission):
--   ICD-10-CM: O36.4, O02.1, P95, Z37 and O31.2 on AAPC / Kodex pages (copyright 2026);
--     Z3A on findacode.com. The O36.4 inclusion term reads "after completion of 20 weeks of
--     gestation"; O02.1 reads "early fetal death, before completion of 20 weeks of gestation,
--     with retention of dead fetus", and its Excludes1 note sends fetal death (late) to O36.4.
--     Z37 is "for use as an additional code to identify the outcome of delivery on the mother's
--     record. It is not for use on the newborn record" (Excludes1: P95).
--     Chapter P (P95 stillbirth): "for use on newborn records only, never on maternal records".
--   WHO ICD-10 (2019 browser, screenshot supplied by the author on 2026-10-28): O36.4 "Maternal care for intrauterine death", Excludes: missed abortion (O02.1); the WHO text has no gestational-age wording.
--   WHO ICD-10 Z37 (2019 browser, screenshot supplied by the author on 2026-10-28): same nine titles Z37.0 to Z37.9; note "intended for use as an additional code to identify the outcome of delivery on the mother's record".
--   WHO ICD-10 P95 (2019 browser, screenshot supplied by the author on 2026-10-28): titled "Fetal death of unspecified cause", Incl.: deadborn fetus NOS, stillbirth NOS; it sits in the perinatal chapter (P).
--   ICD-9-CM (icd9data.com): V27.x 2012; 656.4 2014 ("Fetal death: NOS, after completion of 22
--     weeks gestation, late; missed delivery", Excludes: missed abortion 632); 632 2008
--     ("early fetal death before completion of 22 weeks gestation with retention of dead fetus");
--     768.0 / 768.1 (perinatal chapter, newborn/neonate-only diagnoses, age 0 years; valid until 2015-09-30; the 768.1 page of 2014 converts to P84).
--     656.4 2012 (screenshot supplied by the author on 2026-10-28): same title, Excludes (632) and Applies To; "3 ICD-9-CM codes below 656.4" (656.40, 656.41, 656.43).
--   Stillbirth definition: WHO / ICD-11 (22 weeks), NCHS (20 weeks); see analysis_plan.md.
--
-- Tiers
--   strict    fetal death of the whole pregnancy at an obstetric stage (decision D5: main definition)
--   partial   one or more fetuses died while others were liveborn or the pregnancy continued
--             (sensitivity only; one stillborn fetus of a multiple birth is still a stillbirth,
--             but the outcome of the mother is mixed)
--   excluded  listed for audit, never used by the labels: early (pre-viable) fetal death and
--             codes that belong to newborn records
--
-- Conventions: MIMIC-IV stores codes WITHOUT dots; patterns are PREFIXES (icd_code LIKE pattern || '%').
--   ICD-10-CM O36.4 has the 7th characters 0, 1-5 and 9 (fetus); ICD-9-CM 656.4 has the 5th digits 0, 1 and 3.
-- Run the whole script in one connection (DBeaver: Alt+X). Only aggregate results are produced.
-- ============================================================================

DROP TABLE IF EXISTS mimiciv.fetal_death_code_patterns_v2;

CREATE TABLE mimiciv.fetal_death_code_patterns_v2 (
    code_group     VARCHAR(50),
    icd_version    SMALLINT,       -- 9 | 10
    code_pattern   VARCHAR(10),    -- no dots, as stored in MIMIC-IV
    match_type     VARCHAR(6),     -- 'PREFIX'
    tier           VARCHAR(10),    -- 'strict' | 'partial' | 'excluded'
    official_title VARCHAR(120),
    gestational_note VARCHAR(160),
    source_note    VARCHAR(80),
    verified_on    DATE
);

INSERT INTO mimiciv.fetal_death_code_patterns_v2
    (code_group, icd_version, code_pattern, match_type, tier, official_title, gestational_note, source_note, verified_on) VALUES

-- ICD-10-CM | intrauterine death (maternal record)
('Intrauterine death', 10, 'O364', 'PREFIX', 'strict', 'Maternal care for intrauterine death', 'Inclusion term: after completion of 20 weeks of gestation', 'ICD-10-CM O36.4 (AAPC); WHO ICD-10 2019', DATE '2026-10-28'),

-- ICD-10-CM | outcome of delivery, all fetuses stillborn
('Stillbirth outcome of delivery', 10, 'Z371', 'PREFIX', 'strict', 'Single stillbirth', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 10, 'Z374', 'PREFIX', 'strict', 'Twins, both stillborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 10, 'Z377', 'PREFIX', 'strict', 'Other multiple births, all stillborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),

-- ICD-10-CM | multiple birth with mixed outcome, or pregnancy continuing after the death of a fetus
('Mixed outcome of a multiple pregnancy', 10, 'Z373', 'PREFIX', 'partial', 'Twins, one liveborn and one stillborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Mixed outcome of a multiple pregnancy', 10, 'Z376', 'PREFIX', 'partial', 'Other multiple births, some liveborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Mixed outcome of a multiple pregnancy', 10, 'O312', 'PREFIX', 'partial', 'Continuing pregnancy after intrauterine death of one fetus or more', NULL, 'ICD-10-CM O31.2 (AAPC)', DATE '2026-10-28'),

-- ICD-10-CM | excluded: early fetal death before 20 weeks, and newborn-record stillbirth
('Early fetal death (pre-viable)', 10, 'O021', 'PREFIX', 'excluded', 'Missed abortion', 'Inclusion term: early fetal death, before completion of 20 weeks of gestation, with retention of dead fetus', 'ICD-10-CM O02.1 (Kodex, AAPC)', DATE '2026-10-28'),
('Newborn-record code', 10, 'P95', 'PREFIX', 'excluded', 'Stillbirth', 'Chapter P: for use on newborn records only, never on maternal records', 'ICD-10-CM P95 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),

-- ICD-9-CM | intrauterine death (maternal record)
('Intrauterine death', 9, '6564', 'PREFIX', 'strict', 'Intrauterine death affecting management of mother', 'Fetal death after completion of 22 weeks gestation, late; missed delivery', 'ICD-9-CM 656.4 (icd9data 2012, 2014)', DATE '2026-10-28'),

-- ICD-9-CM | outcome of delivery, all fetuses stillborn
('Stillbirth outcome of delivery', 9, 'V271', 'PREFIX', 'strict', 'Outcome of delivery, single stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 9, 'V274', 'PREFIX', 'strict', 'Outcome of delivery, twins, both stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 9, 'V277', 'PREFIX', 'strict', 'Outcome of delivery, other multiple birth, all stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),

-- ICD-9-CM | multiple birth with mixed outcome
('Mixed outcome of a multiple pregnancy', 9, 'V273', 'PREFIX', 'partial', 'Outcome of delivery, twins, one liveborn and one stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),
('Mixed outcome of a multiple pregnancy', 9, 'V276', 'PREFIX', 'partial', 'Outcome of delivery, other multiple birth, some liveborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),

-- ICD-9-CM | excluded: early fetal death before 22 weeks, and newborn-record fetal death
('Early fetal death (pre-viable)', 9, '632', 'PREFIX', 'excluded', 'Missed abortion', 'Early fetal death before completion of 22 weeks gestation with retention of dead fetus', 'ICD-9-CM 632 (icd9data 2008)', DATE '2026-10-28'),
('Newborn-record code', 9, '7680', 'PREFIX', 'excluded', 'Fetal death from asphyxia or anoxia before onset of labor or at unspecified time', 'Perinatal chapter (newborn records); valid until 2015-09-30', 'ICD-9-CM 768.0 (icd9data 2014)', DATE '2026-10-28'),
('Newborn-record code', 9, '7681', 'PREFIX', 'excluded', 'Fetal death from asphyxia or anoxia during labor', 'Perinatal chapter (newborn records); newborn/neonate only (age 0); valid until 2015-09-30', 'ICD-9-CM 768.1 (icd9data 2014, 2015)', DATE '2026-10-28');

-- ============================================================================
-- CHECKS (aggregate only) -- run each and paste the result
-- ============================================================================

-- Q-T15a. Content of the table: patterns by tier and ICD version (expected: strict 4 + 4, partial 3 + 2, excluded 2 + 3)
SELECT 'Q-T15a patterns by tier' AS q, tier, icd_version, COUNT(*) AS n_patterns
FROM   mimiciv.fetal_death_code_patterns_v2
GROUP  BY 2, 3 ORDER BY 2, 3;

-- Q-T15b. Admissions per pattern: whole database, obstetric universe and population of D3 (delivery flag or stillbirth code)
WITH hits AS (
    SELECT p.tier, p.icd_version, p.code_pattern, d.hadm_id
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.fetal_death_code_patterns_v2 p
           ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
)
SELECT 'Q-T15b admissions per pattern' AS q, h.tier, h.icd_version, h.code_pattern,
       COUNT(DISTINCT h.hadm_id)                                                             AS n_admissions_database,
       COUNT(DISTINCT h.hadm_id) FILTER (WHERE c.hadm_id IS NOT NULL)                        AS n_in_obstetric_universe,
       COUNT(DISTINCT h.hadm_id) FILTER (WHERE c.hadm_id IS NOT NULL
                                           AND (c.is_delivery_v2 OR c.has_stillbirth_code))  AS n_in_population_d3
FROM   hits h
LEFT JOIN mimiciv.cohort_obstetric_v2 c ON c.hadm_id = h.hadm_id
GROUP  BY 2, 3, 4 ORDER BY 2, 3, 4;

-- Q-T15c. Full codes (7th character / 5th digit) of the strict and partial patterns in the obstetric universe
SELECT 'Q-T15c full codes in the universe' AS q, p.tier, d.icd_version, d.icd_code,
       COUNT(DISTINCT d.hadm_id) AS n_admissions
FROM   mimiciv.diagnoses_icd d
JOIN   mimiciv.fetal_death_code_patterns_v2 p
       ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
JOIN   mimiciv.cohort_obstetric_v2 c ON c.hadm_id = d.hadm_id
WHERE  p.tier <> 'excluded'
GROUP  BY 2, 3, 4 ORDER BY 2, 3, 4;

-- Q-T15d. Events with the verified table (expected, same as the provisional label: 154 events, 136 strict, 18 partial only; population of D3: 142 and 129)
WITH ev AS (
    SELECT d.hadm_id, BOOL_OR(p.tier = 'strict') AS fd_strict
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.fetal_death_code_patterns_v2 p
           ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
    WHERE  p.tier IN ('strict', 'partial')
      AND  d.hadm_id IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
    GROUP  BY d.hadm_id
)
SELECT 'Q-T15d events with the verified table' AS q,
       COUNT(*)                                                    AS n_events,
       COUNT(*) FILTER (WHERE ev.fd_strict)                        AS n_strict,
       COUNT(*) FILTER (WHERE NOT ev.fd_strict)                    AS n_partial_only,
       COUNT(*) FILTER (WHERE c.is_delivery_v2 OR c.has_stillbirth_code)                    AS n_events_population_d3,
       COUNT(*) FILTER (WHERE ev.fd_strict AND (c.is_delivery_v2 OR c.has_stillbirth_code)) AS n_strict_population_d3
FROM   ev
JOIN   mimiciv.cohort_obstetric_v2 c ON c.hadm_id = ev.hadm_id;

-- Q-T15e. Admissions of the obstetric universe with an excluded family: how many also carry an event code, and how many would be missed events
WITH ev AS (
    SELECT DISTINCT d.hadm_id
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.fetal_death_code_patterns_v2 p
           ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
    WHERE  p.tier IN ('strict', 'partial')
),
ex AS (
    SELECT d.hadm_id,
           CASE WHEN p.code_pattern IN ('O021', '632') THEN 'early loss (O02.1 / 632)'
                ELSE 'newborn-record code (P95 / 768.0 / 768.1)' END AS family
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.fetal_death_code_patterns_v2 p
           ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
    WHERE  p.tier = 'excluded'
      AND  d.hadm_id IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
    GROUP  BY d.hadm_id, 2
)
SELECT 'Q-T15e excluded families in the universe' AS q, ex.family,
       COUNT(*)                                          AS n_admissions,
       COUNT(*) FILTER (WHERE ev.hadm_id IS NOT NULL)    AS n_also_with_event_code,
       COUNT(*) FILTER (WHERE ev.hadm_id IS NULL)        AS n_without_event_code
FROM   ex
LEFT JOIN ev ON ev.hadm_id = ex.hadm_id
GROUP  BY 2 ORDER BY 2;
