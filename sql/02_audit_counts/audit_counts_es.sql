-- ============================================================================
-- AUDITORÍA DE CONTEOS, grupos A-D -- modelos de muerte fetal (plan v2, tarea T08)
-- ============================================================================
-- Propósito: medir, sobre la cohorte obstétrica revisada del proyecto materno, los
-- números necesarios para cerrar las decisiones D3 (población), D4 (unidad de análisis y
-- mismo embarazo) y D5 (definición del desenlace) ANTES de construir cualquier modelo.
-- SOLO LECTURA: únicamente crea tablas temporales y ejecuta SELECT. Los resultados son
-- conteos agregados; NO publicar filas con subject_id ni hadm_id.
--
-- Prerrequisitos (construidos por MaternalMortality_MIMIC-IV, sql/04_labels y sql/05_predictors):
--   mimiciv.cohort_obstetric_v2, mimiciv.hadm_delivery_v2, mimiciv.obstetric_dx_v2,
--   mimiciv.predictors_24h_v2
-- Q-A2 (última consulta) también necesita mimiciv.cohort_fetal_death_dataset (tabla heredada de
-- sql/fetal_death_dataset.sql); si no existe, solo falla esa consulta.
--
-- La etiqueta de muerte fetal usada aquí es PROVISIONAL: los mismos 13 patrones de código de los
-- scripts heredados (estricto / parcial). La tabla de códigos verificada es la tarea T15.
-- Q-C5 (pacientes en ambos lados de una partición por admisión) se calcula en el
-- cuaderno 01_patient_overlap (tarea T13). Los grupos E y F son scripts aparte.
--
-- Ejecutar el script completo en UNA sola conexión (DBeaver: Alt+X): las tablas temporales
-- deben sobrevivir entre sentencias. Cada resultado empieza con una columna q
-- que coincide con el identificador de la hoja 'Conteos' del libro de seguimiento.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0. Tablas de trabajo
-- ----------------------------------------------------------------------------
-- Patrones provisionales de código de muerte fetal (misma lista de los scripts heredados)
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

-- Códigos de muerte fetal en CUALQUIER admisión de las pacientes de la cohorte (necesario para ver eventos previos)
DROP TABLE IF EXISTS tmp_fa_hits_all;
CREATE TEMP TABLE tmp_fa_hits_all AS
SELECT d.subject_id, d.hadm_id, d.icd_version, d.icd_code, d.seq_num, p.tier
FROM   mimiciv.diagnoses_icd d
JOIN   tmp_fa_patterns p
       ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_prefix || '%'
WHERE  d.subject_id IN (SELECT subject_id FROM mimiciv.cohort_obstetric_v2);

-- Una fila por admisión con un código de muerte fetal
DROP TABLE IF EXISTS tmp_fa_event;
CREATE TEMP TABLE tmp_fa_event AS
SELECT hadm_id,
       TRUE                      AS fd_any,
       BOOL_OR(tier = 'strict')  AS fd_strict,
       MIN(seq_num)              AS min_fd_seq,
       COUNT(*)                  AS n_fd_codes
FROM   tmp_fa_hits_all
GROUP  BY hadm_id;

-- Semanas de gestación a partir de los códigos Z3A.xx (solo CIE-10; Z3A.00 / Z3A.01 = no especificado / < 8 semanas)
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

-- Diagnósticos obstétricos de la admisión que NO son códigos de muerte fetal
DROP TABLE IF EXISTS tmp_fa_obst;
CREATE TEMP TABLE tmp_fa_obst AS
SELECT o.hadm_id, COUNT(*) FILTER (WHERE p.tier IS NULL) AS n_obst_other
FROM   mimiciv.obstetric_dx_v2 o
LEFT JOIN tmp_fa_patterns p
       ON p.icd_version = o.icd_version AND o.icd_code LIKE p.code_prefix || '%'
GROUP  BY o.hadm_id;

-- Tabla de trabajo: una fila por admisión del universo obstétrico
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

-- Días desde la admisión ANTERIOR más cercana de la misma paciente que tiene un código de muerte fetal
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
-- GRUPO A -- base
-- ============================================================================

-- Q-A1. Conteos base (auditoría materna: 25,736 / 15,084 / 19,425 / 19,383)
SELECT 'Q-A1 base' AS q,
       COUNT(*)                                                    AS n_admissions,
       COUNT(DISTINCT f.subject_id)                                AS n_patients,
       COUNT(*) FILTER (WHERE f.is_delivery_v2)                    AS n_delivery_hospitalizations,
       COUNT(DISTINCT f.subject_id) FILTER (WHERE f.is_delivery_v2) AS n_patients_with_delivery,
       COUNT(*) FILTER (WHERE f.is_delivery_v2 AND p.eligible_24h) AS n_deliveries_eligible_24h,
       (SELECT COUNT(*) FROM mimiciv.predictors_24h_v2)            AS n_rows_predictors_24h
FROM   tmp_fa f
LEFT JOIN mimiciv.predictors_24h_v2 p ON p.hadm_id = f.hadm_id;

-- Q-A3. Admisiones por paciente
WITH pa AS (SELECT subject_id, COUNT(*) AS n FROM tmp_fa GROUP BY subject_id)
SELECT 'Q-A3 admissions per patient' AS q,
       CASE WHEN n >= 5 THEN '5 or more' ELSE n::text END AS admissions_per_patient,
       COUNT(*)  AS n_patients,
       SUM(n)    AS n_admissions
FROM   pa GROUP BY 2 ORDER BY 2;

-- Q-A3b. Resumen (auditoría materna: 6,793 de 15,084 pacientes con más de una admisión; máximo 27)
WITH pa AS (SELECT subject_id, COUNT(*) AS n FROM tmp_fa GROUP BY subject_id)
SELECT 'Q-A3b summary' AS q,
       COUNT(*)                                                    AS n_patients,
       COUNT(*) FILTER (WHERE n > 1)                               AS n_patients_with_more_than_one,
       ROUND(100.0 * COUNT(*) FILTER (WHERE n > 1) / COUNT(*), 1)  AS pct_more_than_one,
       MAX(n)                                                      AS max_admissions
FROM   pa;

-- ============================================================================
-- GRUPO B -- eventos y definición
-- ============================================================================

-- Q-B1. Eventos por nivel y versión CIE (heredado: 154 eventos, 136 estrictos)
SELECT 'Q-B1 events by tier and ICD version' AS q, icd_era,
       COUNT(*)                                           AS n_admissions,
       COUNT(*) FILTER (WHERE fd_any)                     AS n_events_strict_or_partial,
       COUNT(*) FILTER (WHERE fd_strict)                  AS n_events_strict,
       COUNT(*) FILTER (WHERE fd_any AND NOT fd_strict)   AS n_events_partial_only,
       COUNT(DISTINCT subject_id) FILTER (WHERE fd_any)   AS n_patients_with_event
FROM   tmp_fa
GROUP  BY ROLLUP (icd_era)
ORDER  BY icd_era NULLS LAST;

-- Q-B2. Eventos por ámbito
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

-- Q-B3. Concordancia de la etiqueta con el código de mortinato de la marca de parto (auditoría materna: 109 partos)
SELECT 'Q-B3 label vs has_stillbirth_code' AS q, fd_strict, has_stillbirth_code, is_delivery_v2, icd_era,
       COUNT(*) AS n_admissions
FROM   tmp_fa
WHERE  fd_any OR has_stillbirth_code
GROUP  BY fd_strict, has_stillbirth_code, is_delivery_v2, icd_era
ORDER  BY fd_strict DESC, has_stillbirth_code DESC, is_delivery_v2 DESC, icd_era;

-- Q-B3b. Admisiones con código de mortinato pero SIN la marca de parto: ¿tienen un código de aborto, ectópico o molar?
SELECT 'Q-B3b stillbirth code without delivery flag' AS q, has_abortive_code,
       COUNT(*)                          AS n_admissions,
       COUNT(*) FILTER (WHERE fd_strict) AS n_events_strict
FROM   tmp_fa
WHERE  has_stillbirth_code AND NOT is_delivery_v2
GROUP  BY 2 ORDER BY 2;

-- Q-B4. Semanas de gestación de los eventos (solo las admisiones CIE-10 tienen códigos Z3A)
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

-- Q-B4b. Eventos por franja de edad gestacional más fina, marca de parto y código de aborto, ectópico o molar (admisiones CIE-10 con código Z3A)
--        Aclara si los eventos de menos de 22 semanas son los que quedan fuera de la marca de parto
SELECT 'Q-B4b weeks by delivery flag and abortive code' AS q,
       CASE WHEN gest_weeks < 20 THEN '1 under 20 weeks'
            WHEN gest_weeks < 22 THEN '2 20-21 weeks'
            WHEN gest_weeks < 28 THEN '3 22-27 weeks'
            WHEN gest_weeks < 37 THEN '4 28-36 weeks'
            ELSE                      '5 37 weeks or more' END AS gestational_age,
       is_delivery_v2, has_abortive_code,
       COUNT(*)                          AS n_events_strict_or_partial,
       COUNT(*) FILTER (WHERE fd_strict) AS n_events_strict
FROM   tmp_fa
WHERE  fd_any AND gest_weeks IS NOT NULL
GROUP  BY 2, 3, 4 ORDER BY 2, 3, 4;

-- Q-B5. Posición del código de muerte fetal en la lista de diagnósticos y eventos sin otro código obstétrico
SELECT 'Q-B5 position of the fetal-death code' AS q,
       CASE WHEN min_fd_seq <= 4 THEN '1-4' WHEN min_fd_seq <= 10 THEN '5-10' ELSE 'over 10' END AS lowest_position,
       COUNT(*)                                  AS n_events,
       COUNT(*) FILTER (WHERE n_obst_other = 0)  AS n_events_without_other_obstetric_code
FROM   tmp_fa
WHERE  fd_any
GROUP  BY 2 ORDER BY 2;

-- Q-B6. Códigos estrictos de muerte fetal en admisiones FUERA del universo obstétrico (por sexo y edad aproximada)
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

-- Q-B7. Solapamiento con morbilidad materna grave y con muerte en la misma admisión (heredado: 2 y 0 entre estrictos)
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

-- Q-B8. Eventos cuya admisión también tiene un código de aborto, ectópico o molar (pérdidas pre-viables)
SELECT 'Q-B8 events with abortive or ectopic codes' AS q, has_abortive_code, is_delivery_v2,
       COUNT(*)                        AS n_events_strict_or_partial,
       COUNT(*) FILTER (WHERE fd_strict) AS n_events_strict
FROM   tmp_fa
WHERE  fd_any
GROUP  BY 2, 3 ORDER BY 2, 3;

-- ============================================================================
-- GRUPO C -- solapamiento de pacientes y mismo embarazo
-- ============================================================================

-- Q-C1. Admisiones con evento por paciente
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

-- Q-C2. Intervalo con la admisión previa de la misma paciente, según el estado de evento de la admisión
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

-- Q-C3. Intervalo con una admisión ANTERIOR que ya tiene un código de muerte fetal
--       (las cifras heredadas no coinciden: 17 admisiones, 5 eventos, descritas como menos de 90 días y como dentro de 180 días)
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

-- Q-C3b. Admisiones con evento que son la primera admisión de la paciente en el universo, o una posterior
SELECT 'Q-C3b event admissions by rank' AS q,
       CASE WHEN adm_rank = 1 THEN 'first admission' ELSE 'later admission' END AS admission_rank,
       COUNT(*) FILTER (WHERE fd_any)    AS n_events,
       COUNT(*) FILTER (WHERE fd_strict) AS n_events_strict
FROM   tmp_fa
GROUP  BY 2 ORDER BY 2;

-- Q-C4. Eventos según cada unidad de análisis candidata
--       Cadena de embarazo = admisiones de la misma paciente unidas por un intervalo de como máximo G días con la anterior
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
-- GRUPO D -- época y codificación
-- ============================================================================

-- Q-D1. Eventos y tasa por 1,000 hospitalizaciones de parto, por versión CIE
--       (tasa = eventos en hospitalizaciones de parto / hospitalizaciones de parto; NO es por 1,000 nacimientos totales)
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

-- Q-D1b. Igual, por grupo de año ancla (la ventana ancla de la paciente, NO la fecha de cada admisión)
SELECT 'Q-D1b events by anchor-year group' AS q, anchor_year_group,
       COUNT(*) FILTER (WHERE is_delivery_v2)                                  AS n_deliveries,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_any)                       AS n_events_in_deliveries,
       COUNT(*) FILTER (WHERE NOT is_delivery_v2 AND fd_any)                   AS n_events_not_deliveries,
       ROUND(1000.0 * COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_any)
             / NULLIF(COUNT(*) FILTER (WHERE is_delivery_v2), 0), 2)           AS events_per_1000_deliveries
FROM   tmp_fa
GROUP  BY anchor_year_group ORDER BY anchor_year_group;

-- Q-D1c. Año aproximado de admisión (límite inferior de la ventana ancla + desplazamiento) por versión CIE: ¿está confundida la época?
SELECT 'Q-D1c approximate year by ICD version' AS q, icd_era, COUNT(*) AS n_admissions,
       PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY approx_year_low) AS p05_year,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY approx_year_low) AS median_year,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY approx_year_low) AS p95_year
FROM   tmp_fa
GROUP  BY icd_era ORDER BY icd_era;

-- Q-D2. Disponibilidad de semanas de gestación (los códigos Z3A solo existen en CIE-10)
SELECT 'Q-D2 gestational weeks by ICD version' AS q, icd_era,
       COUNT(*) FILTER (WHERE fd_any)                                   AS n_events,
       COUNT(*) FILTER (WHERE fd_any AND gest_weeks IS NOT NULL)        AS n_events_with_weeks,
       COUNT(*) FILTER (WHERE is_delivery_v2)                           AS n_deliveries,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND gest_weeks IS NOT NULL) AS n_deliveries_with_weeks
FROM   tmp_fa
GROUP  BY ROLLUP (icd_era)
ORDER  BY icd_era NULLS LAST;

-- Q-D3. Tasas por 1,000 hospitalizaciones de parto con cuatro definiciones, para comparar con una tasa
--       publicada de mortinatos (citar la fuente; ojo: las tasas publicadas usan nacimientos totales como denominador)
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
-- Q-A2 -- conciliación con el dataset heredado (dejar al FINAL: falla si la tabla no existe)
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
