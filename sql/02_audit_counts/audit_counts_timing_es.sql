-- ============================================================================
-- AUDITORÍA DE CONTEOS, grupo E (elegibilidad y tiempos) -- modelos de muerte fetal (plan v2, tarea T20)
-- ============================================================================
-- Propósito: medir, en eventos y no eventos, cuánto dura la hospitalización, cuántos
-- eventos se pierden en cada punto de predicción candidato, y cuándo ocurren el primer valor
-- de laboratorio, el primer ingreso a UCI, el registro en urgencias y los procedimientos
-- de parto. Estos conteos cierran D6 (punto de predicción), D7 (tiempo cero y ventana)
-- y D8 (admisiones que terminan antes del punto de predicción).
-- SOLO LECTURA: únicamente crea tablas temporales y ejecuta SELECT. Los resultados son
-- conteos agregados; NO publicar filas con subject_id ni hadm_id.
--
-- Población (decisión D3, 28/10/2026): hospitalizaciones de parto (marca v2) más admisiones con
-- código de mortinato (Z37.1/.4/.7, V27.1/.4/.7). Q-E2 muestra también los dos ámbitos de sensibilidad.
-- La etiqueta de muerte fetal es PROVISIONAL (los mismos 13 patrones de audit_counts.sql); la
-- tabla de códigos verificada es la tarea T15. La etiqueta NO tiene hora del evento: la única
-- evidencia de tiempos disponible son las fechas de los procedimientos (solo fecha), ver Q-E4.
--
-- Prerrequisitos (construidos por MaternalMortality_MIMIC-IV, sql/04_labels y sql/05_predictors):
--   mimiciv.cohort_obstetric_v2, mimiciv.predictors_24h_v2 (tiempo cero = hora de ingreso,
--   punto de predicción t_end = hora de ingreso + 24 h, ventana desde 24 h antes hasta t_end)
-- Q-E3b lee mimiciv.labevents solo para las admisiones de la población (puede tardar
-- unos minutos).
--
-- Ejecutar el script completo en UNA sola conexión (DBeaver: Alt+X): las tablas temporales
-- deben sobrevivir entre sentencias. Cada resultado empieza con una columna q
-- que coincide con el identificador de la hoja 'Conteos' del libro de seguimiento.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0. Tablas de trabajo
-- ----------------------------------------------------------------------------
-- Patrones provisionales de código de muerte fetal (misma lista de audit_counts.sql)
DROP TABLE IF EXISTS tmp_fe_patterns;
CREATE TEMP TABLE tmp_fe_patterns (
    icd_version INT,
    code_prefix VARCHAR(10),
    tier        VARCHAR(10)
);
INSERT INTO tmp_fe_patterns VALUES
 (10, 'O364', 'strict'), (10, 'Z371', 'strict'), (10, 'Z374', 'strict'), (10, 'Z377', 'strict'),
 (10, 'Z373', 'partial'), (10, 'Z376', 'partial'), (10, 'O312', 'partial'),
 (9,  '6564', 'strict'), (9,  'V271', 'strict'), (9,  'V274', 'strict'), (9,  'V277', 'strict'),
 (9,  'V273', 'partial'), (9,  'V276', 'partial');

-- Una fila por admisión con un código de muerte fetal
DROP TABLE IF EXISTS tmp_fe_event;
CREATE TEMP TABLE tmp_fe_event AS
SELECT d.hadm_id,
       TRUE                      AS fd_any,
       BOOL_OR(p.tier = 'strict') AS fd_strict
FROM   mimiciv.diagnoses_icd d
JOIN   tmp_fe_patterns p
       ON p.icd_version = d.icd_version AND d.icd_code LIKE p.code_prefix || '%'
WHERE  d.hadm_id IN (SELECT hadm_id FROM mimiciv.cohort_obstetric_v2)
GROUP  BY d.hadm_id;

-- Tabla de trabajo: una fila por admisión del universo obstétrico, con tiempos y elegibilidad
DROP TABLE IF EXISTS tmp_fe_base;
CREATE TEMP TABLE tmp_fe_base AS
SELECT c.subject_id, c.hadm_id, a.admittime, a.dischtime, a.edregtime,
       pr.t_end, pr.los_hours, pr.hours_to_death, pr.hours_to_first_icu,
       COALESCE(pr.eligible_24h, FALSE)                                   AS eligible_24h,
       COALESCE(pr.icu_in_24h, FALSE)                                     AS icu_in_24h,
       (pr.deathtime IS NOT NULL AND pr.deathtime <= pr.t_end)            AS died_before_t_end,
       COALESCE(c.is_delivery_v2, FALSE)                                  AS is_delivery_v2,
       (COALESCE(c.is_delivery_v2, FALSE) OR COALESCE(c.has_stillbirth_code, FALSE)) AS in_pop,
       COALESCE(e.fd_any, FALSE)                                          AS fd_any,
       COALESCE(e.fd_strict, FALSE)                                       AS fd_strict,
       CASE WHEN e.fd_strict THEN '1 strict event'
            WHEN e.fd_any    THEN '2 partial-only event'
            ELSE                  '3 non-event' END                       AS ev_group
FROM   mimiciv.cohort_obstetric_v2 c
JOIN   mimiciv.admissions a          ON a.hadm_id  = c.hadm_id
JOIN   mimiciv.predictors_24h_v2 pr  ON pr.hadm_id = c.hadm_id
LEFT JOIN tmp_fe_event e             ON e.hadm_id  = c.hadm_id;

-- Primer valor de laboratorio de cada admisión de la población (ventana: desde 24 h antes del ingreso hasta el alta)
DROP TABLE IF EXISTS tmp_fe_lab;
CREATE TEMP TABLE tmp_fe_lab AS
SELECT b.hadm_id, MIN(l.charttime) AS first_lab_time
FROM   tmp_fe_base b
JOIN   mimiciv.labevents l
       ON  l.subject_id = b.subject_id
       AND l.charttime >= b.admittime - INTERVAL '24 hours'
       AND l.charttime <= b.dischtime
       AND (l.hadm_id = b.hadm_id OR l.hadm_id IS NULL)
WHERE  b.in_pop
GROUP  BY b.hadm_id;

-- Primer procedimiento de parto y primer procedimiento de inducción (solo fechas, convertidas a date porque chartdate puede ser timestamp; misma lista de parto que hadm_delivery_v2)
-- La lista de inducción (CIE-9 73.0, 73.1, 73.4; CIE-10-PCS 10907ZC) es PROVISIONAL y debe verificarse antes de citarla
DROP TABLE IF EXISTS tmp_fe_proc;
CREATE TEMP TABLE tmp_fe_proc AS
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
       ) AS first_delivery_proc_date,
       MIN(p.chartdate::date) FILTER (WHERE
              (p.icd_version = 9  AND (p.icd_code LIKE '730%' OR p.icd_code LIKE '731%' OR p.icd_code LIKE '734%'))
           OR (p.icd_version = 10 AND p.icd_code = '10907ZC')
       ) AS first_induction_proc_date
FROM   mimiciv.procedures_icd p
WHERE  p.hadm_id IN (SELECT hadm_id FROM tmp_fe_base WHERE in_pop)
GROUP  BY p.hadm_id;

-- ============================================================================
-- GRUPO E -- elegibilidad y tiempos
-- ============================================================================

-- Q-E0. Verificación de la población (esperado según la auditoría de conteos: 19,440 admisiones, 142 eventos, 129 estrictos; solo marca de parto 19,425 y 114)
SELECT 'Q-E0 population check' AS q,
       COUNT(*) FILTER (WHERE in_pop)                       AS n_population,
       COUNT(*) FILTER (WHERE in_pop AND fd_any)            AS n_events_strict_or_partial,
       COUNT(*) FILTER (WHERE in_pop AND fd_strict)         AS n_events_strict,
       COUNT(*) FILTER (WHERE is_delivery_v2)               AS n_delivery_flag,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND fd_strict) AS n_strict_delivery_flag
FROM   tmp_fe_base;

-- Q-E1. Duración de la estancia (horas) en eventos y no eventos, población de D3
SELECT 'Q-E1 length of stay' AS q, ev_group,
       COUNT(*)                                                         AS n_admissions,
       COUNT(*) FILTER (WHERE los_hours IS NULL OR los_hours <= 0)      AS n_los_missing_or_not_positive,
       ROUND(PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY los_hours)::numeric, 1) AS p05_hours,
       ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_hours)::numeric, 1) AS p25_hours,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY los_hours)::numeric, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_hours)::numeric, 1) AS p75_hours,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY los_hours)::numeric, 1) AS p95_hours,
       COUNT(*) FILTER (WHERE los_hours <  12)                          AS n_under_12h,
       COUNT(*) FILTER (WHERE los_hours >= 12 AND los_hours < 24)       AS n_12_to_24h,
       COUNT(*) FILTER (WHERE los_hours >= 24 AND los_hours < 48)       AS n_24_to_48h,
       COUNT(*) FILTER (WHERE los_hours >= 48)                          AS n_48h_or_more
FROM   tmp_fe_base
WHERE  in_pop
GROUP  BY ROLLUP (ev_group)
ORDER  BY ev_group NULLS LAST;

-- Q-E2. Elegibilidad a 24 horas por ámbito y eventos perdidos (alta o muerte antes del ingreso + 24 h)
SELECT 'Q-E2 eligibility at 24 hours' AS q, scope,
       n_admissions, n_eligible, n_died_before_24h, n_discharged_before_24h,
       n_events, n_events_lost, n_strict, n_strict_lost,
       ROUND(100.0 * n_strict_lost / NULLIF(n_strict, 0), 1) AS pct_strict_lost
FROM (
    SELECT 1 AS o, 'Population of D3 (delivery flag or stillbirth code)' AS scope,
           COUNT(*) AS n_admissions,
           COUNT(*) FILTER (WHERE eligible_24h) AS n_eligible,
           COUNT(*) FILTER (WHERE died_before_t_end) AS n_died_before_24h,
           COUNT(*) FILTER (WHERE NOT eligible_24h AND NOT died_before_t_end) AS n_discharged_before_24h,
           COUNT(*) FILTER (WHERE fd_any) AS n_events,
           COUNT(*) FILTER (WHERE fd_any AND NOT eligible_24h) AS n_events_lost,
           COUNT(*) FILTER (WHERE fd_strict) AS n_strict,
           COUNT(*) FILTER (WHERE fd_strict AND NOT eligible_24h) AS n_strict_lost
    FROM tmp_fe_base WHERE in_pop
    UNION ALL
    SELECT 2, 'Delivery flag alone',
           COUNT(*), COUNT(*) FILTER (WHERE eligible_24h), COUNT(*) FILTER (WHERE died_before_t_end),
           COUNT(*) FILTER (WHERE NOT eligible_24h AND NOT died_before_t_end),
           COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_any AND NOT eligible_24h),
           COUNT(*) FILTER (WHERE fd_strict), COUNT(*) FILTER (WHERE fd_strict AND NOT eligible_24h)
    FROM tmp_fe_base WHERE is_delivery_v2
    UNION ALL
    SELECT 3, 'Any obstetric admission',
           COUNT(*), COUNT(*) FILTER (WHERE eligible_24h), COUNT(*) FILTER (WHERE died_before_t_end),
           COUNT(*) FILTER (WHERE NOT eligible_24h AND NOT died_before_t_end),
           COUNT(*) FILTER (WHERE fd_any), COUNT(*) FILTER (WHERE fd_any AND NOT eligible_24h),
           COUNT(*) FILTER (WHERE fd_strict), COUNT(*) FILTER (WHERE fd_strict AND NOT eligible_24h)
    FROM tmp_fe_base
) s
ORDER BY o;

-- Q-E2b. Admisiones y eventos que siguen hospitalizados en otros puntos de predicción candidatos (población de D3)
SELECT 'Q-E2b remaining at other prediction points' AS q, t.hours_after_admission,
       COUNT(*)                                                         AS n_remaining,
       COUNT(*) FILTER (WHERE b.fd_any)                                 AS n_events_remaining,
       COUNT(*) FILTER (WHERE b.fd_strict)                              AS n_strict_remaining,
       ROUND(100.0 * COUNT(*) FILTER (WHERE b.fd_strict)
             / NULLIF((SELECT COUNT(*) FROM tmp_fe_base WHERE in_pop AND fd_strict), 0), 1) AS pct_strict_retained
FROM   tmp_fe_base b
CROSS JOIN (VALUES (0), (6), (12), (24), (36), (48)) AS t(hours_after_admission)
WHERE  b.in_pop
  AND  b.los_hours >= t.hours_after_admission
  AND  (b.hours_to_death IS NULL OR b.hours_to_death > t.hours_after_admission)
GROUP  BY t.hours_after_admission
ORDER  BY t.hours_after_admission;

-- Q-E3a. Registro en urgencias antes de la hora de ingreso (horas), población de D3
SELECT 'Q-E3a ED registration before admission' AS q, ev_group,
       COUNT(*)                                                          AS n_admissions,
       COUNT(edregtime)                                                  AS n_with_ed_registration,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (admittime - edregtime)) / 3600.0)::numeric, 1) AS median_hours_before_admission,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (admittime - edregtime)) / 3600.0)::numeric, 1) AS p95_hours_before_admission,
       COUNT(*) FILTER (WHERE edregtime IS NOT NULL AND admittime - edregtime > INTERVAL '24 hours') AS n_ed_more_than_24h_before,
       COUNT(*) FILTER (WHERE edregtime > admittime)                     AS n_ed_after_admission_time
FROM   tmp_fe_base
WHERE  in_pop
GROUP  BY ROLLUP (ev_group)
ORDER  BY ev_group NULLS LAST;

-- Q-E3b. Primer valor de laboratorio respecto de la hora de ingreso (horas; ventana desde 24 h antes del ingreso hasta el alta)
SELECT 'Q-E3b first laboratory value' AS q, b.ev_group,
       COUNT(*)                                                          AS n_admissions,
       COUNT(*) FILTER (WHERE lb.hadm_id IS NULL)                        AS n_without_laboratory_value,
       ROUND(PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (lb.first_lab_time - b.admittime)) / 3600.0)::numeric, 1) AS p05_hours,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (lb.first_lab_time - b.admittime)) / 3600.0)::numeric, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (lb.first_lab_time - b.admittime)) / 3600.0)::numeric, 1) AS p95_hours,
       COUNT(*) FILTER (WHERE lb.first_lab_time <  b.admittime)          AS n_first_lab_before_admission,
       COUNT(*) FILTER (WHERE lb.first_lab_time >  b.t_end)              AS n_first_lab_after_24h
FROM   tmp_fe_base b
LEFT JOIN tmp_fe_lab lb ON lb.hadm_id = b.hadm_id
WHERE  b.in_pop
GROUP  BY ROLLUP (b.ev_group)
ORDER  BY b.ev_group NULLS LAST;

-- Q-E3c. Primer ingreso a UCI respecto de la hora de ingreso (horas), población de D3
SELECT 'Q-E3c first ICU admission' AS q, ev_group,
       COUNT(*)                                                          AS n_admissions,
       COUNT(*) FILTER (WHERE hours_to_first_icu IS NOT NULL)            AS n_with_icu_stay,
       COUNT(*) FILTER (WHERE icu_in_24h)                                AS n_icu_in_first_24h,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY hours_to_first_icu)::numeric, 1) AS median_hours_to_icu,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY hours_to_first_icu)::numeric, 1) AS p95_hours_to_icu
FROM   tmp_fe_base
WHERE  in_pop
GROUP  BY ROLLUP (ev_group)
ORDER  BY ev_group NULLS LAST;

-- Q-E4. Fecha del primer procedimiento de parto y del primer procedimiento de inducción respecto de la fecha de ingreso (días calendario)
--       Un procedimiento en el día 0 o 1 puede caer dentro o fuera de ingreso + 24 h: los códigos de procedimiento llevan fecha, no hora
SELECT 'Q-E4 delivery and induction procedure dates' AS q, b.ev_group,
       COUNT(*)                                                                        AS n_admissions,
       COUNT(*) FILTER (WHERE pr.first_delivery_proc_date IS NULL)                     AS n_no_delivery_procedure,
       COUNT(*) FILTER (WHERE pr.first_delivery_proc_date::date - b.admittime::date <  0)    AS n_delivery_before_admission_date,
       COUNT(*) FILTER (WHERE pr.first_delivery_proc_date::date - b.admittime::date =  0)    AS n_delivery_day_0,
       COUNT(*) FILTER (WHERE pr.first_delivery_proc_date::date - b.admittime::date =  1)    AS n_delivery_day_1,
       COUNT(*) FILTER (WHERE pr.first_delivery_proc_date::date - b.admittime::date >= 2)    AS n_delivery_day_2_or_later,
       COUNT(*) FILTER (WHERE pr.first_induction_proc_date IS NOT NULL)                AS n_with_induction_procedure,
       COUNT(*) FILTER (WHERE pr.first_induction_proc_date::date - b.admittime::date =  0)   AS n_induction_day_0,
       COUNT(*) FILTER (WHERE pr.first_induction_proc_date::date - b.admittime::date >= 1)   AS n_induction_day_1_or_later
FROM   tmp_fe_base b
LEFT JOIN tmp_fe_proc pr ON pr.hadm_id = b.hadm_id
WHERE  b.in_pop
GROUP  BY ROLLUP (b.ev_group)
ORDER  BY b.ev_group NULLS LAST;
