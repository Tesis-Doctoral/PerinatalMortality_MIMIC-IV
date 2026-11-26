-- ============================================================================
-- AUDITORÍA DE CONTEOS A -- información disponible antes del ingreso para el parto (modelo prenatal, tarea A1)
-- Framework: etapas E4 (auditoría de conteos) y E7 (predictores); informa los parámetros candidatos antes de la puerta P3
-- ============================================================================
-- Propósito: el modelo prenatal solo puede usar lo registrado al menos 7 días antes del
-- ingreso para el parto (ficha del desenlace, docs/outcome_card_antenatal_es.md, sección 3). Este script
-- mide cuántas admisiones de la población tienen alguna información de ese tipo, y con qué frecuencia
-- se registra cada predictor candidato, para que la lista de predictores se fije con números.
--
-- Fuentes de la ventana de información (margen de B días antes de la hora de ingreso t0):
--   admisiones anteriores de la misma paciente con egreso hasta t0 - B (sus diagnósticos y
--   procedimientos); mediciones ambulatorias (omr) fechadas hasta t0 - B; valores de laboratorio
--   ambulatorios (labevents sin hadm_id) registrados hasta t0 - B.
-- Márgenes: 7 días (principal), 1 y 30 días (sensibilidad).
--
-- Regla contra la selección por desenlace: la disponibilidad de un
-- BLOQUE completo de información se muestra en eventos y no eventos (Q-A1 a Q-A3), porque
-- decide si el modelo es factible. La frecuencia de cada condición individual (Q-A4 a Q-A7) se
-- muestra solo para toda la población, nunca separada por desenlace, para que ningún predictor se elija
-- por su asociación con la muerte fetal.
--
-- SOLO LECTURA: solo crea tablas temporales y ejecuta SELECT. Los resultados son conteos agregados;
-- NO publicar filas con subject_id o hadm_id, y mostrar los conteos menores de 5 como "<5" en todo
-- archivo publicado.
--
-- Requisitos: tablas derivadas mimiciv.antenatal_fetal_death_label (etiqueta por admisión) y
-- mimiciv.antenatal_obstetric_universe (universo obstétrico), construidas por sql/03_antenatal/01_ and 02_, y las tablas hosp de MIMIC-IV
-- admissions, patients, diagnoses_icd, procedures_icd, omr, labevents, d_labitems.
-- Las tablas de laboratorio ambulatorio (paso 0.5) leen labevents para las pacientes de la
-- población; puede tardar varios minutos.
--
-- Ejecutar el script completo en UNA conexión (DBeaver: Alt+X): las tablas temporales deben sobrevivir
-- entre sentencias. Cada resultado empieza con una columna de etiqueta q.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0.1 Población (hospitalizaciones de parto más admisiones con código de mortinato) y márgenes
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ai_base;
CREATE TEMP TABLE tmp_ai_base AS
SELECT l.subject_id, l.hadm_id, l.admittime AS t0, l.icd_era, l.anchor_year_group,
       l.fd_strict, l.fd_any,
       CASE WHEN l.fd_strict THEN '1 strict event'
            WHEN l.fd_any    THEN '2 partial-only event'
            ELSE                  '3 non-event' END AS ev_group
FROM   mimiciv.antenatal_fetal_death_label l
WHERE  l.in_population;
CREATE INDEX ON tmp_ai_base (subject_id);

DROP TABLE IF EXISTS tmp_ai_buffer;
CREATE TEMP TABLE tmp_ai_buffer (buffer_days INT);
INSERT INTO tmp_ai_buffer VALUES (1), (7), (30);

-- ----------------------------------------------------------------------------
-- 0.2 Admisiones anteriores de la misma paciente, con egreso hasta t0 - margen
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ai_prior_adm;
CREATE TEMP TABLE tmp_ai_prior_adm AS
SELECT b.hadm_id, bf.buffer_days, a2.hadm_id AS prior_hadm_id, a2.dischtime AS prior_dischtime,
       (c2.hadm_id IS NOT NULL) AS prior_is_obstetric
FROM   tmp_ai_base b
CROSS JOIN tmp_ai_buffer bf
JOIN   mimiciv.admissions a2
       ON  a2.subject_id = b.subject_id
       AND a2.hadm_id   <> b.hadm_id
       AND a2.dischtime <= b.t0 - make_interval(days => bf.buffer_days)
LEFT JOIN mimiciv.antenatal_obstetric_universe c2 ON c2.hadm_id = a2.hadm_id;

-- ----------------------------------------------------------------------------
-- 0.3 Condiciones registradas en admisiones anteriores (margen principal de 7 días)
--     Las listas de códigos son PROVISIONALES (prefijos CIE-10-CM y CIE-9-CM) y deben verificarse antes
--     de construir la tabla de predictores.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ai_prior_dx;
CREATE TEMP TABLE tmp_ai_prior_dx AS
SELECT p.hadm_id,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^O601')
            OR (d.icd_version = 9  AND d.icd_code ~ '^6442'))                                   AS hx_preterm_delivery,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(O11|O13|O14|O15|O16)')
            OR (d.icd_version = 9  AND d.icd_code ~ '^642[3-7]'))                               AS hx_hypertensive_pregnancy,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^O244')
            OR (d.icd_version = 9  AND d.icd_code ~ '^6488'))                                   AS hx_gestational_diabetes,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(I1[0-5]|O10)')
            OR (d.icd_version = 9  AND d.icd_code ~ '^(40[1-5]|642[0-2])'))                     AS hx_chronic_hypertension,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(E0[89]|E1[013]|O240|O241|O243)')
            OR (d.icd_version = 9  AND d.icd_code ~ '^(250|6480)'))                             AS hx_pregestational_diabetes,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(E66|Z683|Z684|O9921)')
            OR (d.icd_version = 9  AND d.icd_code ~ '^(2780|V853|V854|6491)'))                  AS hx_obesity,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^N18')
            OR (d.icd_version = 9  AND d.icd_code ~ '^585'))                                    AS hx_chronic_kidney_disease,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^E0[0-7]')
            OR (d.icd_version = 9  AND d.icd_code ~ '^(24[0-6]|6481)'))                         AS hx_thyroid_disease,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(M32|D68[56])')
            OR (d.icd_version = 9  AND d.icd_code ~ '^(7100|2898[12])'))                        AS hx_lupus_aps_thrombophilia,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(F1[0-9]|Z720|O993[1-3])')
            OR (d.icd_version = 9  AND d.icd_code ~ '^(30[345]|6483|V1582)'))                   AS hx_substance_use,
       BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(B20|Z21|O987|A5[0-3]|O981)')
            OR (d.icd_version = 9  AND d.icd_code ~ '^(042|V08|09[0-7]|6470)'))                 AS hx_hiv_syphilis
FROM   tmp_ai_prior_adm p
JOIN   mimiciv.diagnoses_icd d ON d.hadm_id = p.prior_hadm_id
WHERE  p.buffer_days = 7
GROUP  BY p.hadm_id;

-- Muerte fetal anterior (la etiqueta verificada de una admisión obstétrica anterior) y cesárea anterior (procedimiento)
DROP TABLE IF EXISTS tmp_ai_prior_ob;
CREATE TEMP TABLE tmp_ai_prior_ob AS
SELECT p.hadm_id,
       BOOL_OR(COALESCE(l2.label_main, FALSE)) AS hx_fetal_death,
       BOOL_OR(EXISTS (SELECT 1 FROM mimiciv.procedures_icd pr
                       WHERE pr.hadm_id = p.prior_hadm_id
                         AND ((pr.icd_version = 10 AND pr.icd_code IN ('10D00Z0','10D00Z1','10D00Z2'))
                           OR (pr.icd_version = 9  AND pr.icd_code ~ '^(740|741|742|744|7499)')))) AS hx_cesarean
FROM   tmp_ai_prior_adm p
LEFT JOIN mimiciv.antenatal_fetal_death_label l2 ON l2.hadm_id = p.prior_hadm_id
WHERE  p.buffer_days = 7
GROUP  BY p.hadm_id;

-- ----------------------------------------------------------------------------
-- 0.4 Mediciones ambulatorias (omr), fechadas hasta t0 - margen (omr tiene fecha, no hora)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ai_omr;
CREATE TEMP TABLE tmp_ai_omr AS
SELECT b.hadm_id, bf.buffer_days, o.result_name,
       MAX(o.chartdate)::date AS last_date
FROM   tmp_ai_base b
CROSS JOIN tmp_ai_buffer bf
JOIN   mimiciv.omr o
       ON  o.subject_id = b.subject_id
       AND o.chartdate::date <= (b.t0 - make_interval(days => bf.buffer_days))::date
GROUP  BY b.hadm_id, bf.buffer_days, o.result_name;

-- ----------------------------------------------------------------------------
-- 0.5 Valores de laboratorio ambulatorios (labevents sin hadm_id), registrados hasta t0 - margen
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ai_labitems;
CREATE TEMP TABLE tmp_ai_labitems AS
SELECT itemid,
       CASE WHEN label ILIKE '%A1c%'                          THEN 'hemoglobin A1c'
            WHEN label = 'Hemoglobin' AND fluid = 'Blood'      THEN 'hemoglobin'
            WHEN label = 'Creatinine' AND fluid = 'Blood'      THEN 'creatinine' END AS lab_name
FROM   mimiciv.d_labitems
WHERE  label ILIKE '%A1c%'
   OR (label IN ('Hemoglobin', 'Creatinine') AND fluid = 'Blood');

-- Valores ambulatorios de las pacientes de la población, leídos una sola vez (el paso lento)
DROP TABLE IF EXISTS tmp_ai_lab_raw;
CREATE TEMP TABLE tmp_ai_lab_raw AS
SELECT le.subject_id, le.charttime, COALESCE(li.lab_name, 'any other test') AS lab_name
FROM   mimiciv.labevents le
LEFT JOIN tmp_ai_labitems li ON li.itemid = le.itemid
WHERE  le.hadm_id IS NULL
  AND  le.subject_id IN (SELECT DISTINCT subject_id FROM tmp_ai_base);
CREATE INDEX ON tmp_ai_lab_raw (subject_id);

DROP TABLE IF EXISTS tmp_ai_lab;
CREATE TEMP TABLE tmp_ai_lab AS
SELECT b.hadm_id, bf.buffer_days, r.lab_name, MAX(r.charttime) AS last_time
FROM   tmp_ai_base b
CROSS JOIN tmp_ai_buffer bf
JOIN   tmp_ai_lab_raw r
       ON  r.subject_id = b.subject_id
       AND r.charttime <= b.t0 - make_interval(days => bf.buffer_days)
GROUP  BY b.hadm_id, bf.buffer_days, r.lab_name;

-- ----------------------------------------------------------------------------
-- 0.6 Una fila por admisión y margen con la disponibilidad de cada bloque
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ai_avail;
CREATE TEMP TABLE tmp_ai_avail AS
SELECT b.*, bf.buffer_days,
       EXISTS (SELECT 1 FROM tmp_ai_prior_adm p WHERE p.hadm_id = b.hadm_id AND p.buffer_days = bf.buffer_days) AS has_prior_admission,
       EXISTS (SELECT 1 FROM tmp_ai_prior_adm p WHERE p.hadm_id = b.hadm_id AND p.buffer_days = bf.buffer_days
                                                  AND p.prior_is_obstetric)                                     AS has_prior_obstetric_admission,
       EXISTS (SELECT 1 FROM tmp_ai_omr o WHERE o.hadm_id = b.hadm_id AND o.buffer_days = bf.buffer_days)       AS has_omr,
       EXISTS (SELECT 1 FROM tmp_ai_lab x WHERE x.hadm_id = b.hadm_id AND x.buffer_days = bf.buffer_days)       AS has_outpatient_lab
FROM   tmp_ai_base b
CROSS JOIN tmp_ai_buffer bf;

-- ============================================================================
-- CONTEOS
-- ============================================================================

-- Q-A0. Verificación de la población (esperado: 19.440 admisiones; 129 eventos estrictos; 142 eventos con códigos parciales)
SELECT 'Q-A0 population check' AS q,
       COUNT(*)                          AS n_admissions,
       COUNT(DISTINCT subject_id)        AS n_patients,
       COUNT(*) FILTER (WHERE fd_strict) AS n_strict,
       COUNT(*) FILTER (WHERE fd_any)    AS n_events_any
FROM   tmp_ai_base;

-- Q-A1. Alguna información en la ventana, por margen y grupo de evento (el conteo de factibilidad)
SELECT 'Q-A1 information available before admission' AS q, buffer_days, ev_group,
       COUNT(*)                                                                            AS n_admissions,
       COUNT(*) FILTER (WHERE has_prior_admission OR has_omr OR has_outpatient_lab)        AS n_any_information,
       ROUND(100.0 * COUNT(*) FILTER (WHERE has_prior_admission OR has_omr OR has_outpatient_lab) / COUNT(*), 1) AS pct_any_information,
       COUNT(*) FILTER (WHERE has_prior_admission)                                         AS n_prior_admission,
       COUNT(*) FILTER (WHERE has_prior_obstetric_admission)                               AS n_prior_obstetric_admission,
       COUNT(*) FILTER (WHERE has_omr)                                                     AS n_omr,
       COUNT(*) FILTER (WHERE has_outpatient_lab)                                          AS n_outpatient_lab
FROM   tmp_ai_avail
GROUP  BY buffer_days, ev_group
ORDER  BY buffer_days, ev_group;

-- Q-A2. Alguna información en la ventana (7 días) por era CIE y grupo de año ancla, eventos y no eventos
SELECT 'Q-A2 information by period (7 days)' AS q, icd_era, anchor_year_group,
       COUNT(*)                                                                                   AS n_admissions,
       COUNT(*) FILTER (WHERE has_prior_admission OR has_omr OR has_outpatient_lab)               AS n_any_information,
       COUNT(*) FILTER (WHERE fd_strict)                                                          AS n_strict,
       COUNT(*) FILTER (WHERE fd_strict AND (has_prior_admission OR has_omr OR has_outpatient_lab)) AS n_strict_any_information
FROM   tmp_ai_avail
WHERE  buffer_days = 7
GROUP  BY icd_era, anchor_year_group
ORDER  BY icd_era, anchor_year_group;

-- Q-A3. Admisiones anteriores (7 días): cuántas y cuánto tiempo antes del ingreso para el parto
SELECT 'Q-A3 earlier admissions (7 days)' AS q, ev_group,
       COUNT(*)                                                     AS n_admissions,
       COUNT(*) FILTER (WHERE n_prior = 0)                          AS n_none,
       COUNT(*) FILTER (WHERE n_prior = 1)                          AS n_one,
       COUNT(*) FILTER (WHERE n_prior BETWEEN 2 AND 3)              AS n_two_to_three,
       COUNT(*) FILTER (WHERE n_prior >= 4)                         AS n_four_or_more,
       COUNT(*) FILTER (WHERE days_since_last <= 90)                AS n_last_within_90_days,
       COUNT(*) FILTER (WHERE days_since_last BETWEEN 91 AND 365)   AS n_last_91_to_365_days,
       COUNT(*) FILTER (WHERE days_since_last > 365)                AS n_last_over_365_days
FROM  (SELECT b.hadm_id, b.ev_group,
              COUNT(p.prior_hadm_id)                                 AS n_prior,
              MIN(b.t0::date - p.prior_dischtime::date)              AS days_since_last
       FROM   tmp_ai_base b
       LEFT JOIN tmp_ai_prior_adm p ON p.hadm_id = b.hadm_id AND p.buffer_days = 7
       GROUP  BY b.hadm_id, b.ev_group) s
GROUP  BY ROLLUP (ev_group)
ORDER  BY ev_group NULLS LAST;

-- Q-A4. Condiciones registradas en admisiones anteriores (7 días): SOLO TODA LA POBLACIÓN (sin separar por desenlace)
SELECT 'Q-A4 conditions in earlier admissions (7 days)' AS q, c.condition,
       COUNT(*) FILTER (WHERE c.present)                                                  AS n_admissions_with_condition,
       ROUND(100.0 * COUNT(*) FILTER (WHERE c.present) / (SELECT COUNT(*) FROM tmp_ai_base), 2) AS pct_of_population,
       ROUND(100.0 * COUNT(*) FILTER (WHERE c.present)
             / NULLIF((SELECT COUNT(*) FROM tmp_ai_avail WHERE buffer_days = 7 AND has_prior_admission), 0), 2) AS pct_of_admissions_with_history
FROM   tmp_ai_base b
LEFT JOIN tmp_ai_prior_dx x ON x.hadm_id = b.hadm_id
LEFT JOIN tmp_ai_prior_ob o ON o.hadm_id = b.hadm_id
CROSS JOIN LATERAL (VALUES
       ('01 earlier fetal death',                     COALESCE(o.hx_fetal_death, FALSE)),
       ('02 earlier cesarean',                        COALESCE(o.hx_cesarean, FALSE)),
       ('03 earlier preterm delivery',                COALESCE(x.hx_preterm_delivery, FALSE)),
       ('04 earlier hypertensive disorder of pregnancy', COALESCE(x.hx_hypertensive_pregnancy, FALSE)),
       ('05 earlier gestational diabetes',            COALESCE(x.hx_gestational_diabetes, FALSE)),
       ('06 chronic hypertension',                    COALESCE(x.hx_chronic_hypertension, FALSE)),
       ('07 pregestational diabetes',                 COALESCE(x.hx_pregestational_diabetes, FALSE)),
       ('08 obesity',                                 COALESCE(x.hx_obesity, FALSE)),
       ('09 chronic kidney disease',                  COALESCE(x.hx_chronic_kidney_disease, FALSE)),
       ('10 thyroid disease',                         COALESCE(x.hx_thyroid_disease, FALSE)),
       ('11 lupus, antiphospholipid or thrombophilia', COALESCE(x.hx_lupus_aps_thrombophilia, FALSE)),
       ('12 tobacco, alcohol or drug use',            COALESCE(x.hx_substance_use, FALSE)),
       ('13 HIV or syphilis',                         COALESCE(x.hx_hiv_syphilis, FALSE))
     ) AS c(condition, present)
GROUP  BY c.condition
ORDER  BY c.condition;

-- Q-A5. Mediciones ambulatorias (omr, 7 días): SOLO TODA LA POBLACIÓN, por medición
SELECT 'Q-A5 outpatient measurements (7 days)' AS q, o.result_name,
       COUNT(DISTINCT o.hadm_id)                                                              AS n_admissions_with_value,
       ROUND(100.0 * COUNT(DISTINCT o.hadm_id) / (SELECT COUNT(*) FROM tmp_ai_base), 1)        AS pct_of_population,
       COUNT(DISTINCT o.hadm_id) FILTER (WHERE b.t0::date - o.last_date <= 365)               AS n_last_value_within_1_year,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY b.t0::date - o.last_date)::numeric, 0) AS median_days_before_admission
FROM   tmp_ai_omr o
JOIN   tmp_ai_base b ON b.hadm_id = o.hadm_id
WHERE  o.buffer_days = 7
GROUP  BY o.result_name
ORDER  BY n_admissions_with_value DESC;

-- Q-A6. Valores de laboratorio ambulatorios (7 días): SOLO TODA LA POBLACIÓN, por examen
SELECT 'Q-A6 outpatient laboratory values (7 days)' AS q, x.lab_name,
       COUNT(DISTINCT x.hadm_id)                                                              AS n_admissions_with_value,
       ROUND(100.0 * COUNT(DISTINCT x.hadm_id) / (SELECT COUNT(*) FROM tmp_ai_base), 1)        AS pct_of_population,
       COUNT(DISTINCT x.hadm_id) FILTER (WHERE b.t0 - x.last_time <= INTERVAL '365 days')     AS n_last_value_within_1_year,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (b.t0 - x.last_time)) / 86400.0)::numeric, 0) AS median_days_before_admission
FROM   tmp_ai_lab x
JOIN   tmp_ai_base b ON b.hadm_id = x.hadm_id
WHERE  x.buffer_days = 7
GROUP  BY x.lab_name
ORDER  BY x.lab_name;

-- Q-A7. Variables de registro del ingreso para el parto: valores faltantes o desconocidos, SOLO TODA LA POBLACIÓN
SELECT 'Q-A7 registration variables' AS q,
       COUNT(*)                                                                                    AS n_admissions,
       COUNT(*) FILTER (WHERE a.marital_status IS NULL)                                           AS n_marital_status_missing,
       COUNT(*) FILTER (WHERE a.insurance IS NULL OR a.insurance = '' OR a.insurance = 'Other')   AS n_insurance_missing_or_other,
       COUNT(*) FILTER (WHERE a.language IS NULL OR a.language = '?')                             AS n_language_missing,
       COUNT(*) FILTER (WHERE a.ethnicity IS NULL OR a.ethnicity ILIKE 'UNKNOWN%' OR a.ethnicity ILIKE '%DECLINED%'
                          OR a.ethnicity ILIKE 'UNABLE%')                                         AS n_race_unknown_or_declined
FROM   tmp_ai_base b
JOIN   mimiciv.admissions a ON a.hadm_id = b.hadm_id;
