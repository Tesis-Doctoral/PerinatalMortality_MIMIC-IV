-- ============================================================================
-- 01_labels / 02_fetal_death_label_by_admission.sql
-- Etiqueta de muerte fetal por admisión (plan v2, tarea T16)
-- ============================================================================
-- Propósito: construir mimiciv.fetal_death_label_v2, UNA FILA POR ADMISIÓN del universo obstétrico
--   revisado (mimiciv.cohort_obstetric_v2), con la etiqueta y todo lo que los análisis posteriores
--   necesitan para definir las sensibilidades como COLUMNAS, no como filtros:
--   nivel del evento (estricto / parcial), familias de código, posición del código, códigos de
--   pérdida temprana y de registro del recién nacido, semanas de gestación (Z3A), era de CIE,
--   bandera de población de D3 y bandera de D8 (admisión de menos de 6 horas).
--   La tabla es la fuente de la etiqueta para todos los scripts siguientes: ningún paso posterior
--   debe recalcular el evento desde diagnoses_icd.
--
-- Decisiones aplicadas (2026-10-28):
--   D3  población = bandera de parto v2 O código de mortinato  -> columna in_pop_d3
--   D5  etiqueta principal = código estricto a cualquier edad gestacional  -> columna label_main
--       sensibilidades: estricta + parcial, >= 22 semanas, >= 28 semanas (solo admisiones CIE-10,
--       las únicas con códigos Z3A) y la bandera has_early_loss_code (para excluir eventos)
--   D6  punto de predicción = ingreso + 6 h
--   D8  las admisiones que terminan antes de ingreso + 6 h se excluyen del modelo y se reportan
--       aparte  -> columna ends_before_6h
--   La etiqueta NO tiene momento del evento (es un código de egreso): ver analysis_plan_es.md.
--
-- Prerrequisitos: mimiciv.cohort_obstetric_v2, mimiciv.hadm_delivery_v2,
--   mimiciv.predictors_24h_v2 (proyecto materno, sql/04_labels y sql/05_predictors) y
--   mimiciv.fetal_death_code_patterns_v2 (script 01_fetal_death_codes_official.sql, T15).
--
-- Columnas que son NULL a propósito: label_ge22 y label_ge28 son NULL para un evento estricto
--   cuya edad gestacional se desconoce (sin código Z3A); un análisis de sensibilidad debe reportar
--   esos eventos aparte. Los no eventos son FALSE.
--
-- Ejecutar el script completo en una sola conexión (DBeaver: Alt+X). La tabla es persistente, así
--   que las verificaciones se pueden repetir solas. Solo se producen resultados agregados: NO
--   publicar filas con subject_id ni hadm_id.
-- ============================================================================

SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS mimiciv.fetal_death_label_v2;

CREATE TABLE mimiciv.fetal_death_label_v2 AS
WITH hits AS (
    -- todos los códigos del universo que coinciden con un patrón, de cualquier nivel
    SELECT d.hadm_id, d.icd_version, d.icd_code, d.seq_num, p.tier, p.code_group
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.fetal_death_code_patterns_v2 p
           ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_pattern || '%'
    WHERE  d.hadm_id IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
),
ev AS (
    -- una fila por admisión con al menos un código coincidente
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
    -- semanas de gestación a partir de Z3A.xx (solo CIE-10); Z3A.00 / Z3A.01 = no especificada / menos de 8 semanas
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
       -- población (D3) y sus dos componentes
       COALESCE(c.is_delivery_v2, FALSE)                                             AS is_delivery_v2,
       COALESCE(c.has_stillbirth_code, FALSE)                                        AS has_stillbirth_code,
       (COALESCE(c.is_delivery_v2, FALSE) OR COALESCE(c.has_stillbirth_code, FALSE)) AS in_pop_d3,
       COALESCE(dv.has_abortive_code, FALSE)                                         AS has_abortive_code,
       -- evento y nivel
       (COALESCE(e.n_strict_codes, 0) > 0)                                           AS fd_strict,
       (COALESCE(e.n_strict_codes, 0) = 0 AND COALESCE(e.n_partial_codes, 0) > 0)    AS fd_partial_only,
       (COALESCE(e.n_strict_codes, 0) + COALESCE(e.n_partial_codes, 0) > 0)          AS fd_any,
       CASE WHEN COALESCE(e.n_strict_codes, 0) > 0  THEN 'strict'
            WHEN COALESCE(e.n_partial_codes, 0) > 0 THEN 'partial only'
            ELSE                                         'no event' END              AS fd_tier,
       COALESCE(e.n_strict_codes, 0)                                                 AS n_strict_codes,
       COALESCE(e.n_partial_codes, 0)                                                AS n_partial_codes,
       -- familias de código y posición del código (seq_num 1 = diagnóstico principal)
       COALESCE(e.has_intrauterine_death_code, FALSE)                                AS has_intrauterine_death_code,
       COALESCE(e.has_stillbirth_outcome_code, FALSE)                                AS has_stillbirth_outcome_code,
       COALESCE(e.has_mixed_outcome_code, FALSE)                                     AS has_mixed_outcome_code,
       COALESCE(e.has_antepartum_6564_code, FALSE)                                   AS has_antepartum_6564_code,
       e.min_strict_seq,
       e.min_event_seq,
       -- códigos de pérdida temprana y de registro del recién nacido (nunca los usa la etiqueta; banderas para sensibilidad y auditoría)
       COALESCE(e.has_early_loss_code, FALSE)                                        AS has_early_loss_code,
       COALESCE(e.has_newborn_record_code, FALSE)                                    AS has_newborn_record_code,
       -- edad gestacional (solo CIE-10)
       COALESCE(g.has_z3a_code, FALSE)                                               AS has_z3a_code,
       g.gest_weeks,
       CASE WHEN g.gest_weeks IS NULL THEN 'unknown'
            WHEN g.gest_weeks < 22    THEN 'under 22'
            WHEN g.gest_weeks < 28    THEN '22 to 27'
            ELSE                           '28 or more' END                          AS gest_band,
       -- era de codificación
       CASE WHEN c.has_icd10_dx AND NOT c.has_icd9_dx THEN 'ICD-10 only'
            WHEN c.has_icd9_dx AND NOT c.has_icd10_dx THEN 'ICD-9 only'
            WHEN c.has_icd9_dx AND c.has_icd10_dx     THEN 'both'
            ELSE 'no diagnoses' END                                                  AS icd_era,
       pt.anchor_year_group,
       -- etiquetas: principal (D5) y definiciones de sensibilidad como columnas
       (COALESCE(e.n_strict_codes, 0) > 0)                                           AS label_main,
       (COALESCE(e.n_strict_codes, 0) + COALESCE(e.n_partial_codes, 0) > 0)          AS label_strict_partial,
       CASE WHEN COALESCE(e.n_strict_codes, 0) = 0 THEN FALSE
            WHEN g.gest_weeks IS NULL THEN NULL
            ELSE g.gest_weeks >= 22 END                                              AS label_ge22,
       CASE WHEN COALESCE(e.n_strict_codes, 0) = 0 THEN FALSE
            WHEN g.gest_weeks IS NULL THEN NULL
            ELSE g.gest_weeks >= 28 END                                              AS label_ge28,
       -- eventos estrictos que la población de D3 deja fuera (ver Q-T16b)
       (COALESCE(e.n_strict_codes, 0) > 0
        AND NOT (COALESCE(c.is_delivery_v2, FALSE) OR COALESCE(c.has_stillbirth_code, FALSE))) AS strict_outside_pop_d3,
       -- estancia y bandera de D8 (admisión que termina antes de ingreso + 6 h)
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
-- VERIFICACIONES (solo agregados) -- ejecutar cada una y pegar el resultado
-- ============================================================================

-- Q-T16a. Integridad: una fila por admisión y los conteos de la auditoría anterior
--   (esperado: 25.736 filas y 25.736 admisiones distintas; 154 eventos, 136 estrictos, 18 solo parciales;
--    población D3 19.440 con 142 eventos y 129 estrictos; 7 eventos estrictos fuera de la población;
--    11 eventos con un código de pérdida temprana)
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

-- Q-T16b. Los eventos estrictos fuera de la población de D3: qué códigos tienen y qué tan lejos está la
--   siguiente admisión de parto de la misma paciente (hipótesis: admisiones anteparto con CIE-9 656.43 cuyo parto viene después)
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

-- Q-T16c. Eventos estrictos por familia de código y era, dentro y fuera de la población de D3
SELECT 'Q-T16c strict events by code family' AS q, icd_era, in_pop_d3,
       CASE WHEN has_intrauterine_death_code AND has_stillbirth_outcome_code THEN '3 both families'
            WHEN has_intrauterine_death_code                                  THEN '1 intrauterine death code only'
            ELSE                                                                   '2 stillbirth outcome code only' END AS code_family,
       COUNT(*)                                                 AS n_events,
       COUNT(*) FILTER (WHERE has_antepartum_6564_code)         AS n_with_antepartum_6564
FROM   mimiciv.fetal_death_label_v2
WHERE  fd_strict
GROUP  BY 2, 3, 4 ORDER BY 2, 3, 4;

-- Q-T16d. Posición del primer código estricto en la lista de diagnósticos (1 = diagnóstico principal), por familia de código
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

-- Q-T16e. Eventos que además tienen un código de pérdida temprana, por nivel, código abortivo y banda gestacional (población de D3)
SELECT 'Q-T16e events with early-loss code' AS q, fd_tier, has_early_loss_code, has_abortive_code, gest_band,
       COUNT(*) AS n_admissions
FROM   mimiciv.fetal_death_label_v2
WHERE  in_pop_d3 AND fd_any
GROUP  BY 2, 3, 4, 5 ORDER BY 2, 3, 4, 5;

-- Q-T16f. Tamaño de cada definición de etiqueta (eventos y, donde aplica, eventos de edad gestacional desconocida)
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

-- Q-T16g. Decisión D8: admisiones de la población que terminan antes de ingreso + 6 h, por nivel del evento
SELECT 'Q-T16g D8 admissions shorter than 6 h' AS q, fd_tier,
       COUNT(*)                                       AS n_admissions,
       COUNT(*) FILTER (WHERE ends_before_6h)         AS n_end_before_6h,
       COUNT(*) FILTER (WHERE los_hours IS NULL)      AS n_los_missing
FROM   mimiciv.fetal_death_label_v2
WHERE  in_pop_d3
GROUP  BY 2 ORDER BY 2;
