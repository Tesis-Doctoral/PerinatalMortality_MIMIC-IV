-- ============================================================================
-- 01_labels / 01_fetal_death_codes_official.sql
-- Catálogo verificado de códigos de muerte fetal (CIE-9-CM + CIE-10-CM) -- plan v2, tarea T15
-- ============================================================================
-- Propósito: reemplazar la lista provisional de 13 patrones de código heredada de los scripts
--   antiguos por un catálogo documentado (tabla fetal_death_code_patterns_v2) en el que cada
--   patrón lleva su título oficial, su nivel (estricto / parcial / excluido) y su fuente.
--   La tabla antigua mimiciv.fetal_death_code_patterns NO se toca.
--
-- Fuentes (revisadas el 28/10/2026; las páginas reproducen los listados de códigos de EE. UU.,
--   no se descargaron los archivos del CDC ni de CMS y conviene cotejarlos antes de enviar):
--   CIE-10-CM: O36.4, O02.1, P95, Z37 y O31.2 en páginas de AAPC / Kodex (copyright 2026);
--     Z3A en findacode.com. El término de inclusión de O36.4 dice "after completion of 20 weeks of
--     gestation"; O02.1 dice "early fetal death, before completion of 20 weeks of gestation,
--     with retention of dead fetus", y su nota Excludes1 envía la muerte fetal (tardía) a O36.4.
--     Z37 es "for use as an additional code to identify the outcome of delivery on the mother's
--     record. It is not for use on the newborn record" (Excludes1: P95).
--     Capítulo P (P95 mortinato): "for use on newborn records only, never on maternal records".
--   OMS CIE-10 (navegador 2019, captura aportada por el autor el 28/10/2026): O36.4 "Maternal care for intrauterine death", Excludes: missed abortion (O02.1); el texto de la OMS no trae redacción de edad gestacional.
--   OMS CIE-10 Z37 (navegador 2019, captura aportada por el autor el 28/10/2026): los mismos nueve títulos Z37.0 a Z37.9; nota "intended for use as an additional code to identify the outcome of delivery on the mother's record".
--   OMS CIE-10 P95 (navegador 2019, captura aportada por el autor el 28/10/2026): titulado "Fetal death of unspecified cause", Incl.: deadborn fetus NOS, stillbirth NOS; está en el capítulo perinatal (P).
--   CIE-9-CM (icd9data.com): V27.x 2012; 656.4 2014 ("Fetal death: NOS, after completion of 22
--     weeks gestation, late; missed delivery", Excludes: missed abortion 632); 632 2008
--     ("early fetal death before completion of 22 weeks gestation with retention of dead fetus");
--     768.0 / 768.1 (capítulo perinatal, diagnósticos solo de recién nacidos, edad 0 años; vigentes hasta el 30/09/2015; la página de 768.1 de 2014 se convierte a P84).
--     656.4 2012 (captura aportada por el autor el 28/10/2026): mismo título, Excludes (632) y Applies To; "3 ICD-9-CM codes below 656.4" (656.40, 656.41, 656.43).
--   Definición de mortinato: OMS / CIE-11 (22 semanas), NCHS (20 semanas); ver analysis_plan_es.md.
--
-- Niveles
--   strict    muerte fetal de todo el embarazo en etapa obstétrica (decisión D5: definición principal)
--   partial   uno o más fetos murieron mientras otros nacieron vivos o el embarazo continuó
--             (solo sensibilidad; un feto mortinato de un parto múltiple sigue siendo un mortinato,
--             pero el desenlace de la madre es mixto)
--   excluded  listados para auditoría, nunca usados por las etiquetas: muerte fetal temprana
--             (pre-viable) y códigos que pertenecen a registros de recién nacidos
--
-- Convenciones: MIMIC-IV guarda los códigos SIN puntos; los patrones son PREFIJOS (icd_code LIKE patrón || '%').
--   CIE-10-CM O36.4 tiene los caracteres 7.º 0, 1-5 y 9 (feto); CIE-9-CM 656.4 tiene los quintos dígitos 0, 1 y 3.
-- Ejecutar el script completo en una sola conexión (DBeaver: Alt+X). Solo produce resultados agregados.
-- ============================================================================

DROP TABLE IF EXISTS mimiciv.fetal_death_code_patterns_v2;

CREATE TABLE mimiciv.fetal_death_code_patterns_v2 (
    code_group     VARCHAR(50),
    icd_version    SMALLINT,       -- 9 | 10
    code_pattern   VARCHAR(10),    -- sin puntos, tal como se guarda en MIMIC-IV
    match_type     VARCHAR(6),     -- 'PREFIX'
    tier           VARCHAR(10),    -- 'strict' | 'partial' | 'excluded'
    official_title VARCHAR(120),
    gestational_note VARCHAR(160),
    source_note    VARCHAR(80),
    verified_on    DATE
);

INSERT INTO mimiciv.fetal_death_code_patterns_v2
    (code_group, icd_version, code_pattern, match_type, tier, official_title, gestational_note, source_note, verified_on) VALUES

-- CIE-10-CM | muerte intrauterina (registro de la madre)
('Intrauterine death', 10, 'O364', 'PREFIX', 'strict', 'Maternal care for intrauterine death', 'Inclusion term: after completion of 20 weeks of gestation', 'ICD-10-CM O36.4 (AAPC); WHO ICD-10 2019', DATE '2026-10-28'),

-- CIE-10-CM | desenlace del parto, todos los fetos mortinatos
('Stillbirth outcome of delivery', 10, 'Z371', 'PREFIX', 'strict', 'Single stillbirth', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 10, 'Z374', 'PREFIX', 'strict', 'Twins, both stillborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 10, 'Z377', 'PREFIX', 'strict', 'Other multiple births, all stillborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),

-- CIE-10-CM | parto múltiple con desenlace mixto, o embarazo que continúa tras la muerte de un feto
('Mixed outcome of a multiple pregnancy', 10, 'Z373', 'PREFIX', 'partial', 'Twins, one liveborn and one stillborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Mixed outcome of a multiple pregnancy', 10, 'Z376', 'PREFIX', 'partial', 'Other multiple births, some liveborn', NULL, 'ICD-10-CM Z37 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),
('Mixed outcome of a multiple pregnancy', 10, 'O312', 'PREFIX', 'partial', 'Continuing pregnancy after intrauterine death of one fetus or more', NULL, 'ICD-10-CM O31.2 (AAPC)', DATE '2026-10-28'),

-- CIE-10-CM | excluidos: muerte fetal temprana antes de 20 semanas y mortinato del registro del recién nacido
('Early fetal death (pre-viable)', 10, 'O021', 'PREFIX', 'excluded', 'Missed abortion', 'Inclusion term: early fetal death, before completion of 20 weeks of gestation, with retention of dead fetus', 'ICD-10-CM O02.1 (Kodex, AAPC)', DATE '2026-10-28'),
('Newborn-record code', 10, 'P95', 'PREFIX', 'excluded', 'Stillbirth', 'Chapter P: for use on newborn records only, never on maternal records', 'ICD-10-CM P95 (Kodex); WHO ICD-10 2019', DATE '2026-10-28'),

-- CIE-9-CM | muerte intrauterina (registro de la madre)
('Intrauterine death', 9, '6564', 'PREFIX', 'strict', 'Intrauterine death affecting management of mother', 'Fetal death after completion of 22 weeks gestation, late; missed delivery', 'ICD-9-CM 656.4 (icd9data 2012, 2014)', DATE '2026-10-28'),

-- CIE-9-CM | desenlace del parto, todos los fetos mortinatos
('Stillbirth outcome of delivery', 9, 'V271', 'PREFIX', 'strict', 'Outcome of delivery, single stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 9, 'V274', 'PREFIX', 'strict', 'Outcome of delivery, twins, both stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),
('Stillbirth outcome of delivery', 9, 'V277', 'PREFIX', 'strict', 'Outcome of delivery, other multiple birth, all stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),

-- CIE-9-CM | parto múltiple con desenlace mixto
('Mixed outcome of a multiple pregnancy', 9, 'V273', 'PREFIX', 'partial', 'Outcome of delivery, twins, one liveborn and one stillborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),
('Mixed outcome of a multiple pregnancy', 9, 'V276', 'PREFIX', 'partial', 'Outcome of delivery, other multiple birth, some liveborn', NULL, 'ICD-9-CM V27 (icd9data 2012)', DATE '2026-10-28'),

-- CIE-9-CM | excluidos: muerte fetal temprana antes de 22 semanas y muerte fetal del registro del recién nacido
('Early fetal death (pre-viable)', 9, '632', 'PREFIX', 'excluded', 'Missed abortion', 'Early fetal death before completion of 22 weeks gestation with retention of dead fetus', 'ICD-9-CM 632 (icd9data 2008)', DATE '2026-10-28'),
('Newborn-record code', 9, '7680', 'PREFIX', 'excluded', 'Fetal death from asphyxia or anoxia before onset of labor or at unspecified time', 'Perinatal chapter (newborn records); valid until 2015-09-30', 'ICD-9-CM 768.0 (icd9data 2014)', DATE '2026-10-28'),
('Newborn-record code', 9, '7681', 'PREFIX', 'excluded', 'Fetal death from asphyxia or anoxia during labor', 'Perinatal chapter (newborn records); newborn/neonate only (age 0); valid until 2015-09-30', 'ICD-9-CM 768.1 (icd9data 2014, 2015)', DATE '2026-10-28');

-- ============================================================================
-- VERIFICACIONES (solo agregados) -- ejecutar cada una y pegar el resultado
-- ============================================================================

-- Q-T15a. Contenido de la tabla: patrones por nivel y versión CIE (esperado: strict 4 + 4, partial 3 + 2, excluded 2 + 3)
SELECT 'Q-T15a patterns by tier' AS q, tier, icd_version, COUNT(*) AS n_patterns
FROM   mimiciv.fetal_death_code_patterns_v2
GROUP  BY 2, 3 ORDER BY 2, 3;

-- Q-T15b. Admisiones por patrón: toda la base, universo obstétrico y población de D3 (marca de parto o código de mortinato)
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

-- Q-T15c. Códigos completos (7.º carácter / 5.º dígito) de los patrones estrictos y parciales en el universo obstétrico
SELECT 'Q-T15c full codes in the universe' AS q, p.tier, d.icd_version, d.icd_code,
       COUNT(DISTINCT d.hadm_id) AS n_admissions
FROM   mimiciv.diagnoses_icd d
JOIN   mimiciv.fetal_death_code_patterns_v2 p
       ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
JOIN   mimiciv.cohort_obstetric_v2 c ON c.hadm_id = d.hadm_id
WHERE  p.tier <> 'excluded'
GROUP  BY 2, 3, 4 ORDER BY 2, 3, 4;

-- Q-T15d. Eventos con la tabla verificada (esperado, igual que la etiqueta provisional: 154 eventos, 136 estrictos, 18 solo parciales; población de D3: 142 y 129)
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

-- Q-T15e. Admisiones del universo obstétrico con una familia excluida: cuántas también tienen un código de evento y cuántas serían eventos no captados
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
