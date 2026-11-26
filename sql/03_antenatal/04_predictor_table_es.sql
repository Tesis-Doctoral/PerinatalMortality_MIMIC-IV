-- ============================================================================
-- 03_antenatal / 04_predictor_table_es.sql
-- Tabla de predictores del modelo prenatal (tarea A2)
-- Framework: etapas E6 (punto de predicción y ventana) y E7 (predictores); es la tabla contrato que leen los modelos
-- ============================================================================
-- Propósito: construir mimiciv.antenatal_predictors_v1, UNA FILA POR ADMISIÓN Y MARGEN, con los 27
-- predictores fijados en la ficha del desenlace (docs/outcome_card_antenatal_es.md, sección 4), las etiquetas como
-- columnas y las columnas que definen los análisis de sensibilidad. Los modelos solo leen esta tabla.
--
-- Punto de predicción: hora de ingreso t0 de la hospitalización de parto. Ventana de información:
--   * admisiones anteriores con egreso hasta t0 - margen (diagnósticos y procedimientos);
--   * ventana del embarazo actual para mediciones y laboratorios: desde t0 - 280 días hasta
--     t0 - margen (omr solo tiene fecha, así que la comparación se hace sobre fechas);
--   * variables de registro del ingreso actual que no dependen de cómo llegó la paciente.
-- Márgenes: 7 días (principal, buffer_days = 7), 1 y 30 días (sensibilidad). Los modelos del análisis
-- principal filtran buffer_days = 7.
-- No entra nada del ingreso actual (diagnósticos, procedimientos, laboratorios, tipo de
-- admisión, lugar de admisión, datos de urgencias).
--
-- Las listas de códigos de los antecedentes son PROVISIONALES (las mismas de la auditoría, Q-A4) y deben
-- verificarse antes del primer modelo. Límites de plausibilidad (los valores por fuera quedan NULL):
--   sistólica 60-250 mmHg, diastólica 30-150 mmHg, índice de masa corporal 12-80 kg/m2, peso 70-600 lb,
--   talla 48-84 pulgadas, hemoglobina 3-20 g/dL.
--
-- Requisitos: tablas derivadas mimiciv.antenatal_fetal_death_label (etiqueta por admisión) y
-- mimiciv.antenatal_obstetric_universe (universo obstétrico), construidas por sql/03_antenatal/01_ and 02_, tablas hosp de MIMIC-IV
-- admissions, patients, diagnoses_icd, procedures_icd, omr, labevents, d_labitems.
-- En esta base la columna de raza se llama 'ethnicity' y omr.chartdate es fecha y hora (timestamp).
--
-- Ejecutar el script completo en una conexión (DBeaver: Alt+X). La tabla es persistente, así que las verificaciones
-- se pueden repetir solas. Solo se producen resultados agregados: NO publicar filas con subject_id
-- o hadm_id. Las verificaciones muestran frecuencias de predictores solo para toda la población, nunca separadas
-- por desenlace.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 1. Población, márgenes y variables de registro
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ap_base;
CREATE TEMP TABLE tmp_ap_base AS
SELECT l.subject_id, l.hadm_id, l.admittime AS t0, bf.buffer_days,
       (l.admittime - make_interval(days => bf.buffer_days))            AS t_info_end,
       (l.admittime - INTERVAL '280 days')                              AS t_preg_start
FROM   mimiciv.antenatal_fetal_death_label l
CROSS JOIN (VALUES (1), (7), (30)) AS bf(buffer_days)
WHERE  l.in_population;
CREATE INDEX ON tmp_ap_base (subject_id);
CREATE INDEX ON tmp_ap_base (hadm_id, buffer_days);

-- ----------------------------------------------------------------------------
-- 2. Admisiones anteriores y los antecedentes registrados en ellas
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ap_prior;
CREATE TEMP TABLE tmp_ap_prior AS
SELECT b.hadm_id, b.buffer_days, a2.hadm_id AS prior_hadm_id,
       (a2.dischtime >= b.t0 - INTERVAL '90 days')                      AS within_90_days
FROM   tmp_ap_base b
JOIN   mimiciv.admissions a2
       ON  a2.subject_id = b.subject_id
       AND a2.hadm_id   <> b.hadm_id
       AND a2.dischtime <= b.t_info_end;
CREATE INDEX ON tmp_ap_prior (prior_hadm_id);

DROP TABLE IF EXISTS tmp_ap_hist;
CREATE TEMP TABLE tmp_ap_hist AS
SELECT p.hadm_id, p.buffer_days,
       TRUE                                                                                     AS any_prior_admission,
       BOOL_OR(p.within_90_days)                                                                AS prior_admission_90d,
       BOOL_OR(COALESCE(pr.has_cesarean, FALSE))                                                AS hx_cesarean,
       BOOL_OR(COALESCE(dx.hx_hypertensive_pregnancy, FALSE))                                   AS hx_hypertensive_pregnancy,
       BOOL_OR(COALESCE(dx.hx_chronic_hypertension, FALSE))                                     AS hx_chronic_hypertension,
       BOOL_OR(COALESCE(dx.hx_pregestational_diabetes, FALSE))                                  AS hx_pregestational_diabetes,
       BOOL_OR(COALESCE(dx.hx_gestational_diabetes, FALSE))                                     AS hx_gestational_diabetes,
       BOOL_OR(COALESCE(dx.hx_substance_use, FALSE))                                            AS hx_substance_use,
       BOOL_OR(COALESCE(dx.hx_thyroid_disease, FALSE))                                          AS hx_thyroid_disease,
       BOOL_OR(COALESCE(l2.label_main, FALSE) OR COALESCE(dx.hx_preterm_delivery, FALSE))       AS hx_adverse_pregnancy_outcome,
       BOOL_OR(COALESCE(dx.hx_other_high_risk_chronic, FALSE))                                  AS hx_other_high_risk_chronic
FROM   tmp_ap_prior p
LEFT JOIN mimiciv.antenatal_fetal_death_label l2 ON l2.hadm_id = p.prior_hadm_id
LEFT JOIN (
    SELECT d.hadm_id,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^O601')
                OR (d.icd_version = 9  AND d.icd_code ~ '^6442'))                               AS hx_preterm_delivery,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(O11|O13|O14|O15|O16)')
                OR (d.icd_version = 9  AND d.icd_code ~ '^642[3-7]'))                           AS hx_hypertensive_pregnancy,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^O244')
                OR (d.icd_version = 9  AND d.icd_code ~ '^6488'))                               AS hx_gestational_diabetes,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(I1[0-5]|O10)')
                OR (d.icd_version = 9  AND d.icd_code ~ '^(40[1-5]|642[0-2])'))                 AS hx_chronic_hypertension,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(E0[89]|E1[013]|O240|O241|O243)')
                OR (d.icd_version = 9  AND d.icd_code ~ '^(250|6480)'))                         AS hx_pregestational_diabetes,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^E0[0-7]')
                OR (d.icd_version = 9  AND d.icd_code ~ '^(24[0-6]|6481)'))                     AS hx_thyroid_disease,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(F1[0-9]|Z720|O993[1-3])')
                OR (d.icd_version = 9  AND d.icd_code ~ '^(30[345]|6483|V1582)'))               AS hx_substance_use,
           BOOL_OR((d.icd_version = 10 AND d.icd_code ~ '^(M32|D68[56]|B20|Z21|O987|A5[0-3]|O981|N18)')
                OR (d.icd_version = 9  AND d.icd_code ~ '^(7100|2898[12]|042|V08|09[0-7]|6470|585)')) AS hx_other_high_risk_chronic
    FROM   mimiciv.diagnoses_icd d
    WHERE  d.hadm_id IN (SELECT prior_hadm_id FROM tmp_ap_prior)
    GROUP  BY d.hadm_id
) dx ON dx.hadm_id = p.prior_hadm_id
LEFT JOIN (
    SELECT pc.hadm_id, TRUE AS has_cesarean
    FROM   mimiciv.procedures_icd pc
    WHERE  pc.hadm_id IN (SELECT prior_hadm_id FROM tmp_ap_prior)
      AND ((pc.icd_version = 10 AND pc.icd_code IN ('10D00Z0','10D00Z1','10D00Z2'))
        OR (pc.icd_version = 9  AND pc.icd_code ~ '^(740|741|742|744|7499)'))
    GROUP  BY pc.hadm_id
) pr ON pr.hadm_id = p.prior_hadm_id
GROUP  BY p.hadm_id, p.buffer_days;

-- ----------------------------------------------------------------------------
-- 3. Mediciones ambulatorias (omr) del embarazo actual
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_ap_omr;
CREATE TEMP TABLE tmp_ap_omr AS
SELECT b.hadm_id, b.buffer_days, o.chartdate::date AS chartdate, o.seq_num,
       CASE WHEN o.result_name ILIKE 'Blood Pressure%' THEN 'bp'
            WHEN o.result_name ILIKE 'BMI%'            THEN 'bmi'
            WHEN o.result_name =     'Weight (Lbs)'    THEN 'weight_lb'
            WHEN o.result_name =     'Height (Inches)' THEN 'height_in' END AS kind,
       o.result_value,
       (o.chartdate::date >= b.t_preg_start::date)                     AS in_pregnancy_window
FROM   tmp_ap_base b
JOIN   mimiciv.omr o
       ON  o.subject_id = b.subject_id
       AND o.chartdate::date <= b.t_info_end::date
WHERE  o.result_name ILIKE 'Blood Pressure%' OR o.result_name ILIKE 'BMI%'
   OR  o.result_name IN ('Weight (Lbs)', 'Height (Inches)');

-- Separar los valores y aplicar los límites de plausibilidad
DROP TABLE IF EXISTS tmp_ap_omr_val;
CREATE TEMP TABLE tmp_ap_omr_val AS
SELECT hadm_id, buffer_days, chartdate, seq_num, kind, in_pregnancy_window,
       CASE WHEN kind = 'bp' AND result_value ~ '^\s*[0-9]+(\.[0-9]+)?\s*/\s*[0-9]+(\.[0-9]+)?\s*$'
            THEN NULLIF(split_part(result_value, '/', 1), '')::numeric END AS sbp_raw,
       CASE WHEN kind = 'bp' AND result_value ~ '^\s*[0-9]+(\.[0-9]+)?\s*/\s*[0-9]+(\.[0-9]+)?\s*$'
            THEN NULLIF(split_part(result_value, '/', 2), '')::numeric END AS dbp_raw,
       CASE WHEN kind <> 'bp' AND result_value ~ '^\s*[0-9]+(\.[0-9]+)?\s*$'
            THEN result_value::numeric END                                  AS num_raw
FROM   tmp_ap_omr
WHERE  kind IS NOT NULL;

DROP TABLE IF EXISTS tmp_ap_omr_clean;
CREATE TEMP TABLE tmp_ap_omr_clean AS
SELECT hadm_id, buffer_days, chartdate, seq_num, kind, in_pregnancy_window,
       CASE WHEN sbp_raw BETWEEN 60 AND 250 AND dbp_raw BETWEEN 30 AND 150 THEN sbp_raw END AS sbp,
       CASE WHEN sbp_raw BETWEEN 60 AND 250 AND dbp_raw BETWEEN 30 AND 150 THEN dbp_raw END AS dbp,
       CASE WHEN kind = 'bmi'       AND num_raw BETWEEN 12 AND 80  THEN num_raw END            AS bmi,
       CASE WHEN kind = 'weight_lb' AND num_raw BETWEEN 70 AND 600 THEN num_raw END            AS weight_lb,
       CASE WHEN kind = 'height_in' AND num_raw BETWEEN 48 AND 84  THEN num_raw END            AS height_in
FROM   tmp_ap_omr_val;

-- Último valor de cada medición en la ventana del embarazo actual (talla: cualquier momento antes del cierre de la ventana)
DROP TABLE IF EXISTS tmp_ap_omr_last;
CREATE TEMP TABLE tmp_ap_omr_last AS
WITH preg AS (
    SELECT * FROM tmp_ap_omr_clean WHERE in_pregnancy_window
),
bp AS (
    SELECT DISTINCT ON (hadm_id, buffer_days) hadm_id, buffer_days, sbp, dbp
    FROM   preg WHERE sbp IS NOT NULL
    ORDER  BY hadm_id, buffer_days, chartdate DESC, seq_num DESC
),
el AS (
    SELECT hadm_id, buffer_days, BOOL_OR(sbp >= 140 OR dbp >= 90) AS any_elevated_bp
    FROM   preg WHERE sbp IS NOT NULL
    GROUP  BY hadm_id, buffer_days
),
bm AS (
    SELECT DISTINCT ON (hadm_id, buffer_days) hadm_id, buffer_days, bmi
    FROM   preg WHERE bmi IS NOT NULL
    ORDER  BY hadm_id, buffer_days, chartdate DESC, seq_num DESC
),
w AS (
    SELECT DISTINCT ON (hadm_id, buffer_days) hadm_id, buffer_days, weight_lb
    FROM   preg WHERE weight_lb IS NOT NULL
    ORDER  BY hadm_id, buffer_days, chartdate DESC, seq_num DESC
),
h AS (
    SELECT DISTINCT ON (hadm_id, buffer_days) hadm_id, buffer_days, height_in
    FROM   tmp_ap_omr_clean WHERE height_in IS NOT NULL
    ORDER  BY hadm_id, buffer_days, chartdate DESC, seq_num DESC
),
pc AS (
    SELECT DISTINCT hadm_id, buffer_days FROM preg
)
SELECT b.hadm_id, b.buffer_days,
       bp.sbp AS last_sbp, bp.dbp AS last_dbp,
       COALESCE(el.any_elevated_bp, FALSE)                              AS any_elevated_bp,
       bm.bmi AS last_bmi_recorded,
       w.weight_lb AS last_weight_lb,
       h.height_in AS last_height_in,
       (pc.hadm_id IS NOT NULL)                                         AS any_pregnancy_measurement
FROM   (SELECT DISTINCT hadm_id, buffer_days FROM tmp_ap_base) b
LEFT JOIN bp ON bp.hadm_id = b.hadm_id AND bp.buffer_days = b.buffer_days
LEFT JOIN el ON el.hadm_id = b.hadm_id AND el.buffer_days = b.buffer_days
LEFT JOIN bm ON bm.hadm_id = b.hadm_id AND bm.buffer_days = b.buffer_days
LEFT JOIN w  ON w.hadm_id  = b.hadm_id AND w.buffer_days  = b.buffer_days
LEFT JOIN h  ON h.hadm_id  = b.hadm_id AND h.buffer_days  = b.buffer_days
LEFT JOIN pc ON pc.hadm_id = b.hadm_id AND pc.buffer_days = b.buffer_days;

-- ----------------------------------------------------------------------------
-- 4. Laboratorios ambulatorios (labevents sin hadm_id) del embarazo actual
-- ----------------------------------------------------------------------------
-- Valores ambulatorios de las pacientes de la población, leídos una sola vez (el paso lento: recorre labevents)
DROP TABLE IF EXISTS tmp_ap_labraw;
CREATE TEMP TABLE tmp_ap_labraw AS
SELECT le.subject_id, le.charttime, le.valuenum,
       (le.itemid IN (SELECT itemid FROM mimiciv.d_labitems
                      WHERE label = 'Hemoglobin' AND fluid = 'Blood'))   AS is_hemoglobin
FROM   mimiciv.labevents le
WHERE  le.hadm_id IS NULL
  AND  le.subject_id IN (SELECT DISTINCT subject_id FROM tmp_ap_base);
CREATE INDEX ON tmp_ap_labraw (subject_id, charttime);

DROP TABLE IF EXISTS tmp_ap_lab;
CREATE TEMP TABLE tmp_ap_lab AS
SELECT b.hadm_id, b.buffer_days, r.charttime, r.valuenum, r.is_hemoglobin
FROM   tmp_ap_base b
JOIN   tmp_ap_labraw r
       ON  r.subject_id = b.subject_id
       AND r.charttime >= b.t_preg_start
       AND r.charttime <= b.t_info_end;

DROP TABLE IF EXISTS tmp_ap_lab_last;
CREATE TEMP TABLE tmp_ap_lab_last AS
WITH hb AS (
    SELECT DISTINCT ON (hadm_id, buffer_days) hadm_id, buffer_days, valuenum
    FROM   tmp_ap_lab
    WHERE  is_hemoglobin AND valuenum BETWEEN 3 AND 20
    ORDER  BY hadm_id, buffer_days, charttime DESC
),
anylab AS (
    SELECT DISTINCT hadm_id, buffer_days FROM tmp_ap_lab
)
SELECT b.hadm_id, b.buffer_days,
       hb.valuenum                                                      AS last_hemoglobin,
       (al.hadm_id IS NOT NULL)                                         AS any_pregnancy_lab
FROM   (SELECT DISTINCT hadm_id, buffer_days FROM tmp_ap_base) b
LEFT JOIN hb        ON hb.hadm_id = b.hadm_id AND hb.buffer_days = b.buffer_days
LEFT JOIN anylab al ON al.hadm_id = b.hadm_id AND al.buffer_days = b.buffer_days;

-- Alguna información previa (en cualquier momento antes del cierre de la ventana), para el análisis de sensibilidad
DROP TABLE IF EXISTS tmp_ap_anyinfo;
CREATE TEMP TABLE tmp_ap_anyinfo AS
WITH pa AS (
    SELECT DISTINCT hadm_id, buffer_days FROM tmp_ap_prior
),
po AS (
    SELECT DISTINCT hadm_id, buffer_days FROM tmp_ap_omr
),
fl AS (
    SELECT subject_id, MIN(charttime) AS first_lab_time FROM tmp_ap_labraw GROUP BY subject_id
)
SELECT b.hadm_id, b.buffer_days,
       (pa.hadm_id IS NOT NULL
     OR po.hadm_id IS NOT NULL
     OR COALESCE(fl.first_lab_time <= b.t_info_end, FALSE))             AS has_any_prior_information
FROM   tmp_ap_base b
LEFT JOIN pa ON pa.hadm_id = b.hadm_id AND pa.buffer_days = b.buffer_days
LEFT JOIN po ON po.hadm_id = b.hadm_id AND po.buffer_days = b.buffer_days
LEFT JOIN fl ON fl.subject_id = b.subject_id;

-- Índices y estadísticas de las tablas temporales antes de la unión final.
-- Las tablas temporales no se analizan solas; sin estadísticas el planificador
-- puede elegir uniones anidadas sin índice y la consulta final tarda horas.
CREATE INDEX ON tmp_ap_hist     (hadm_id, buffer_days);
CREATE INDEX ON tmp_ap_omr_last (hadm_id, buffer_days);
CREATE INDEX ON tmp_ap_lab_last (hadm_id, buffer_days);
CREATE INDEX ON tmp_ap_anyinfo  (hadm_id, buffer_days);
ANALYZE tmp_ap_base;
ANALYZE tmp_ap_hist;
ANALYZE tmp_ap_omr_last;
ANALYZE tmp_ap_lab_last;
ANALYZE tmp_ap_anyinfo;

-- ----------------------------------------------------------------------------
-- 5. Tabla de predictores (tabla contrato del modelo prenatal)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.antenatal_predictors_v1;
CREATE TABLE mimiciv.antenatal_predictors_v1 AS
SELECT
    -- columnas del contrato
    b.hadm_id                                                           AS unit_id,
    b.subject_id                                                        AS group_id,
    b.hadm_id, b.subject_id, b.buffer_days,
    b.t0, b.t_info_end,
    -- etiquetas (definición principal y de sensibilidad) y período
    l.label_main, l.label_strict_partial, l.label_ge22, l.label_ge28, l.has_early_loss_code,
    l.icd_era, l.anchor_year_group,
    -- registro
    (pt.anchor_age + EXTRACT(YEAR FROM a.admittime)::int - pt.anchor_year) AS age,
    CASE WHEN a.ethnicity ILIKE 'WHITE%'                                    THEN 'White'
         WHEN a.ethnicity ILIKE 'BLACK%'                                    THEN 'Black'
         WHEN a.ethnicity ILIKE 'HISPANIC%' OR a.ethnicity ILIKE '%LATIN%'  THEN 'Hispanic'
         WHEN a.ethnicity ILIKE 'ASIAN%'                                    THEN 'Asian'
         ELSE 'Other or unknown' END                                    AS race_group,
    CASE WHEN a.insurance = 'Medicaid'                                  THEN 'Medicaid'
         WHEN a.insurance = 'Private'                                   THEN 'Private'
         ELSE 'Medicare, other or missing' END                          AS insurance_group,
    COALESCE(UPPER(a.language) = 'ENGLISH', FALSE)                      AS english,
    CASE WHEN a.marital_status IS NULL                                  THEN 'Missing'
         WHEN UPPER(a.marital_status) = 'MARRIED'                       THEN 'Married'
         ELSE 'Not married' END                                         AS marital_group,
    -- historia de atenciones y antecedentes
    COALESCE(h.any_prior_admission, FALSE)                              AS any_prior_admission,
    COALESCE(h.prior_admission_90d, FALSE)                              AS prior_admission_90d,
    COALESCE(h.hx_cesarean, FALSE)                                      AS hx_cesarean,
    COALESCE(h.hx_hypertensive_pregnancy, FALSE)                        AS hx_hypertensive_pregnancy,
    COALESCE(h.hx_chronic_hypertension, FALSE)                          AS hx_chronic_hypertension,
    COALESCE(h.hx_pregestational_diabetes, FALSE)                       AS hx_pregestational_diabetes,
    COALESCE(h.hx_gestational_diabetes, FALSE)                          AS hx_gestational_diabetes,
    COALESCE(h.hx_substance_use, FALSE)                                 AS hx_substance_use,
    COALESCE(h.hx_thyroid_disease, FALSE)                               AS hx_thyroid_disease,
    COALESCE(h.hx_adverse_pregnancy_outcome, FALSE)                     AS hx_adverse_pregnancy_outcome,
    COALESCE(h.hx_other_high_risk_chronic, FALSE)                       AS hx_other_high_risk_chronic,
    -- mediciones del embarazo actual (NULL = sin valor en la ventana)
    o.last_sbp, o.last_dbp,
    COALESCE(o.any_elevated_bp, FALSE)                                  AS any_elevated_bp,
    COALESCE(o.last_bmi_recorded,
             CASE WHEN o.last_weight_lb IS NOT NULL AND o.last_height_in IS NOT NULL
                  THEN ROUND(703.0 * o.last_weight_lb / (o.last_height_in * o.last_height_in), 1) END) AS last_bmi,
    (o.last_bmi_recorded IS NULL AND o.last_weight_lb IS NOT NULL AND o.last_height_in IS NOT NULL) AS bmi_computed,
    lb.last_hemoglobin,
    -- indicadores
    (COALESCE(o.any_pregnancy_measurement, FALSE) OR COALESCE(lb.any_pregnancy_lab, FALSE)) AS had_prenatal_care_here,
    ai.has_any_prior_information,
    -- columnas derivadas del conjunto reducido
    (COALESCE(h.hx_chronic_hypertension, FALSE) OR COALESCE(h.hx_hypertensive_pregnancy, FALSE)) AS hx_hypertension_any,
    (COALESCE(h.hx_pregestational_diabetes, FALSE) OR COALESCE(h.hx_gestational_diabetes, FALSE)) AS hx_diabetes_any
FROM   tmp_ap_base b
JOIN   mimiciv.antenatal_fetal_death_label l ON l.hadm_id     = b.hadm_id
JOIN   mimiciv.admissions          a  ON a.hadm_id     = b.hadm_id
JOIN   mimiciv.patients            pt ON pt.subject_id = b.subject_id
LEFT JOIN tmp_ap_hist     h  ON h.hadm_id  = b.hadm_id AND h.buffer_days  = b.buffer_days
LEFT JOIN tmp_ap_omr_last o  ON o.hadm_id  = b.hadm_id AND o.buffer_days  = b.buffer_days
LEFT JOIN tmp_ap_lab_last lb ON lb.hadm_id = b.hadm_id AND lb.buffer_days = b.buffer_days
LEFT JOIN tmp_ap_anyinfo  ai ON ai.hadm_id = b.hadm_id AND ai.buffer_days = b.buffer_days;

ALTER TABLE mimiciv.antenatal_predictors_v1 ADD PRIMARY KEY (hadm_id, buffer_days);

-- ============================================================================
-- VERIFICACIONES (solo agregadas; frecuencias de predictores para toda la población, nunca separadas por desenlace)
-- ============================================================================

-- Q-P1. Integridad (esperado en cada margen: 19.440 filas, 19.440 admisiones distintas, 13.735 pacientes, 129 eventos estrictos)
SELECT 'Q-P1 integrity' AS q, buffer_days,
       COUNT(*)                                 AS n_rows,
       COUNT(DISTINCT hadm_id)                  AS n_admissions,
       COUNT(DISTINCT subject_id)               AS n_patients,
       COUNT(*) FILTER (WHERE label_main)       AS n_strict_events,
       COUNT(*) FILTER (WHERE has_any_prior_information) AS n_with_any_prior_information
FROM   mimiciv.antenatal_predictors_v1
GROUP  BY buffer_days ORDER BY buffer_days;

-- Q-P2. Predictores categóricos y binarios (margen de 7 días): admisiones y porcentaje de la población
SELECT 'Q-P2 categorical and binary predictors (7 days)' AS q, v.predictor, v.category,
       COUNT(*)                                                  AS n_admissions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY v.predictor), 1) AS pct
FROM   mimiciv.antenatal_predictors_v1 t
CROSS JOIN LATERAL (VALUES
       ('01 race_group',                   t.race_group),
       ('02 insurance_group',              t.insurance_group),
       ('03 english',                      t.english::text),
       ('04 marital_group',                t.marital_group),
       ('05 any_prior_admission',          t.any_prior_admission::text),
       ('06 prior_admission_90d',          t.prior_admission_90d::text),
       ('07 hx_cesarean',                  t.hx_cesarean::text),
       ('08 hx_hypertensive_pregnancy',    t.hx_hypertensive_pregnancy::text),
       ('09 hx_chronic_hypertension',      t.hx_chronic_hypertension::text),
       ('10 hx_pregestational_diabetes',   t.hx_pregestational_diabetes::text),
       ('11 hx_gestational_diabetes',      t.hx_gestational_diabetes::text),
       ('12 hx_substance_use',             t.hx_substance_use::text),
       ('13 hx_thyroid_disease',           t.hx_thyroid_disease::text),
       ('14 hx_adverse_pregnancy_outcome', t.hx_adverse_pregnancy_outcome::text),
       ('15 hx_other_high_risk_chronic',   t.hx_other_high_risk_chronic::text),
       ('16 any_elevated_bp',              t.any_elevated_bp::text),
       ('17 had_prenatal_care_here',       t.had_prenatal_care_here::text),
       ('18 hx_hypertension_any',          t.hx_hypertension_any::text),
       ('19 hx_diabetes_any',              t.hx_diabetes_any::text)
     ) AS v(predictor, category)
WHERE  t.buffer_days = 7
GROUP  BY v.predictor, v.category
ORDER  BY v.predictor, v.category;

-- Q-P3. Predictores continuos (margen de 7 días): cobertura y distribución
SELECT 'Q-P3 continuous predictors (7 days)' AS q, v.predictor,
       COUNT(*) FILTER (WHERE v.val IS NOT NULL)                                               AS n_with_value,
       ROUND(100.0 * COUNT(*) FILTER (WHERE v.val IS NOT NULL) / COUNT(*), 1)                  AS pct_with_value,
       ROUND(PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY v.val)::numeric, 1)                  AS p05,
       ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY v.val)::numeric, 1)                  AS p25,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY v.val)::numeric, 1)                  AS median,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY v.val)::numeric, 1)                  AS p75,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY v.val)::numeric, 1)                  AS p95
FROM   mimiciv.antenatal_predictors_v1 t
CROSS JOIN LATERAL (VALUES
       ('1 age',             t.age::numeric),
       ('2 last_sbp',        t.last_sbp),
       ('3 last_dbp',        t.last_dbp),
       ('4 last_bmi',        t.last_bmi),
       ('5 last_hemoglobin', t.last_hemoglobin)
     ) AS v(predictor, val)
WHERE  t.buffer_days = 7
GROUP  BY v.predictor
ORDER  BY v.predictor;

-- Q-P4. Cómo se obtuvo el índice de masa corporal (margen de 7 días)
SELECT 'Q-P4 body mass index source (7 days)' AS q,
       COUNT(*) FILTER (WHERE last_bmi IS NOT NULL AND NOT bmi_computed) AS n_recorded,
       COUNT(*) FILTER (WHERE bmi_computed)                              AS n_computed_from_weight_and_height,
       COUNT(*) FILTER (WHERE last_bmi IS NULL)                          AS n_missing
FROM   mimiciv.antenatal_predictors_v1
WHERE  buffer_days = 7;
