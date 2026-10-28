-- ============================================================================
-- Muerte perinatal (componente fetal): tabla ampliada de variables
--   mimiciv.cohort_fetal_death_dataset_ext = cohort_fetal_death_dataset + variables nuevas
-- ============================================================================
-- Agregada después de las consultas de descubrimiento de variables (perinatal_feature_discovery.sql).
-- REQUISITOS: fetal_death_dataset.sql (cohort_fetal_death_dataset,
-- fetal_death_code_patterns) y solo tablas de MIMIC-IV independientes del embarazo.
--
-- REGLA TEMPORAL (control de fuga): cada variable se conoce en o antes de la llegada, o
-- se mide en las primeras 24 h desde la llegada (registro en urgencias o hora de ingreso,
-- la que sea anterior). Los diagnósticos, procedimientos, DRG, tratamientos y
-- microbiología de la MISMA admisión NO se usan (los produce el evento:
-- p. ej., la serología de CMV / toxoplasma y las muestras de tejido siguen a una muerte fetal).
-- Tampoco se usan la coagulación (PT, INR, PTT, fibrinógeno) ni la LDH: eran
-- 5-10 veces más frecuentes entre los eventos (estudio posterior al diagnóstico).
--
-- Bloques:
--   history  hx_hypertension, hx_diabetes, hx_obesity, hx_renal_disease
--            (a partir de diagnósticos de admisiones ANTERIORES de la misma paciente)
--            hx_prior_fetal_death_1y: código previo de muerte fetal con al menos 365 días de antelación
--            (uno más cercano suele ser el MISMO embarazo: 5 de 6 de esos eventos ocurrieron en menos de 90 días)
--   cbc      primera hemoglobina, hematocrito, plaquetas, leucocitos, VCM, RDW (nivel 1)
--   panel    primera creatinina, ALT, AST, ácido úrico, nitrógeno ureico, proteína/creatinina en orina
--            (nivel 2: estudio de preeclampsia; se solicita de forma selectiva)
--   omr      mediciones ambulatorias en los 365 días ANTERIORES a la fecha de ingreso (tabla OMR):
--            última y máxima presión arterial, último peso (kg) e IMC, número de fechas
--            ambulatorias con signos vitales, días desde la última. Cobertura: PA 61 % de las admisiones,
--            peso 57 %, IMC 41 %; no enriquecidas entre los eventos (sin huella de solicitud).
--            Los valores fuera de rangos plausibles se asignan a NULL. Estos registros son anteriores al
--            ingreso, por lo que el evento no pudo producirlos; son mediciones ambulatorias en
--            general, no necesariamente controles prenatales.
--   days_since_prior_fd  días desde la admisión anterior más cercana con un código de muerte
--            fetal (CUALQUIER intervalo). NO es un predictor: el notebook la usa para excluir admisiones
--            que pertenecen al mismo embarazo que un evento previo (<= 180 días).
--
-- Ejecutar como script completo (DBeaver: Alt+X). Puede tardar varios minutos (labevents).
-- ============================================================================

DROP TABLE IF EXISTS mimiciv.cohort_fetal_death_features;
CREATE TABLE mimiciv.cohort_fetal_death_features AS
WITH base AS (
    SELECT c.subject_id, c.hadm_id, a.admittime,
           LEAST(a.admittime, COALESCE(a.edregtime, a.admittime)) AS t0
    FROM   mimiciv.cohort_fetal_death_dataset c
    JOIN   mimiciv.admissions a ON a.hadm_id = c.hadm_id
),
-- primer valor de cada examen de laboratorio dentro de [t0, t0 + 24 h]
first_lab AS (
    SELECT DISTINCT ON (b.hadm_id, l.itemid)
           b.hadm_id, l.itemid, l.valuenum
    FROM   base b
    JOIN   mimiciv.labevents l
           ON l.hadm_id = b.hadm_id
          AND l.valuenum IS NOT NULL
          AND l.charttime BETWEEN b.t0 AND b.t0 + INTERVAL '24 hours'
          AND l.itemid IN (51222, 51221, 51265, 51301, 51250, 51277,        -- hemograma
                           50912, 50861, 50878, 51007, 51006, 51099)        -- panel
    ORDER  BY b.hadm_id, l.itemid, l.charttime
),
labs AS (
    SELECT hadm_id,
           MAX(valuenum) FILTER (WHERE itemid = 51222) AS lab_hemoglobin,
           MAX(valuenum) FILTER (WHERE itemid = 51221) AS lab_hematocrit,
           MAX(valuenum) FILTER (WHERE itemid = 51265) AS lab_platelets,
           MAX(valuenum) FILTER (WHERE itemid = 51301) AS lab_wbc,
           MAX(valuenum) FILTER (WHERE itemid = 51250) AS lab_mcv,
           MAX(valuenum) FILTER (WHERE itemid = 51277) AS lab_rdw,
           MAX(valuenum) FILTER (WHERE itemid = 50912) AS lab_creatinine,
           MAX(valuenum) FILTER (WHERE itemid = 50861) AS lab_alt,
           MAX(valuenum) FILTER (WHERE itemid = 50878) AS lab_ast,
           MAX(valuenum) FILTER (WHERE itemid = 51007) AS lab_uric_acid,
           MAX(valuenum) FILTER (WHERE itemid = 51006) AS lab_urea_nitrogen,
           MAX(valuenum) FILTER (WHERE itemid = 51099) AS lab_urine_prot_creat
    FROM   first_lab
    GROUP  BY hadm_id
),
-- diagnósticos de admisiones ANTERIORES de la misma paciente
prior_dx AS (
    SELECT b.hadm_id,
           (b.admittime::date - a2.admittime::date) AS gap_days,
           d.icd_version, d.icd_code,
           EXISTS (SELECT 1 FROM mimiciv.fetal_death_code_patterns fp
                   WHERE fp.icd_version = d.icd_version
                     AND d.icd_code LIKE fp.code_prefix || '%') AS is_fd
    FROM   base b
    JOIN   mimiciv.admissions a2
           ON a2.subject_id = b.subject_id AND a2.admittime < b.admittime
    JOIN   mimiciv.diagnoses_icd d ON d.hadm_id = a2.hadm_id
),
hist AS (
    SELECT hadm_id,
           MAX(CASE WHEN (icd_version = 10 AND icd_code ~ '^(I1[0-6]|O1[0-6])')
                      OR (icd_version = 9  AND icd_code ~ '^(40[1-5]|642)') THEN 1 ELSE 0 END) AS hx_hypertension,
           MAX(CASE WHEN (icd_version = 10 AND icd_code ~ '^(E08|E09|E10|E11|E13|O24)')
                      OR (icd_version = 9  AND icd_code ~ '^(250|6480|6488)') THEN 1 ELSE 0 END) AS hx_diabetes,
           MAX(CASE WHEN (icd_version = 10 AND icd_code ~ '^(E66|O9921)')
                      OR (icd_version = 9  AND icd_code ~ '^(2780|6491)') THEN 1 ELSE 0 END)     AS hx_obesity,
           MAX(CASE WHEN (icd_version = 10 AND icd_code ~ '^N1[7-9]')
                      OR (icd_version = 9  AND icd_code ~ '^58[4-6]') THEN 1 ELSE 0 END)         AS hx_renal_disease,
           MAX(CASE WHEN is_fd AND gap_days >= 365 THEN 1 ELSE 0 END)                            AS hx_prior_fetal_death_1y,
           MIN(CASE WHEN is_fd THEN gap_days END)                                                AS days_since_prior_fd
    FROM   prior_dx
    GROUP  BY hadm_id
),
-- OMR: mediciones ambulatorias en los 365 días anteriores a la fecha de ingreso
omr_raw AS (
    SELECT b.hadm_id, o.chartdate, o.seq_num, o.result_name, o.result_value,
           (b.admittime::date - o.chartdate) AS days_before
    FROM   base b
    JOIN   mimiciv.omr o
           ON o.subject_id = b.subject_id
          AND o.chartdate <  b.admittime::date
          AND o.chartdate >= b.admittime::date - 365
    WHERE  o.result_name IN ('Blood Pressure', 'Weight (Lbs)', 'BMI (kg/m2)')
),
omr_bp_ok AS (
    SELECT hadm_id, chartdate, seq_num, sbp, dbp
    FROM (
        SELECT hadm_id, chartdate, seq_num,
               CASE WHEN result_value ~ '^\s*[0-9]{2,3}\s*/\s*[0-9]{2,3}\s*$'
                    THEN split_part(result_value, '/', 1)::numeric END AS sbp,
               CASE WHEN result_value ~ '^\s*[0-9]{2,3}\s*/\s*[0-9]{2,3}\s*$'
                    THEN split_part(result_value, '/', 2)::numeric END AS dbp
        FROM   omr_raw
        WHERE  result_name = 'Blood Pressure'
    ) t
    WHERE sbp BETWEEN 60 AND 260 AND dbp BETWEEN 30 AND 160 AND sbp > dbp
),
omr_bp_last AS (
    SELECT DISTINCT ON (hadm_id) hadm_id, sbp, dbp
    FROM   omr_bp_ok
    ORDER  BY hadm_id, chartdate DESC, seq_num DESC
),
omr_bp_max AS (
    SELECT hadm_id, MAX(sbp) AS sbp_max, MAX(dbp) AS dbp_max
    FROM   omr_bp_ok
    GROUP  BY hadm_id
),
omr_wt AS (
    SELECT DISTINCT ON (hadm_id) hadm_id, ROUND(w * 0.45359237, 1) AS weight_kg
    FROM (
        SELECT hadm_id, chartdate, seq_num,
               CASE WHEN result_value ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' THEN result_value::numeric END AS w
        FROM   omr_raw
        WHERE  result_name = 'Weight (Lbs)'
    ) t
    WHERE w BETWEEN 70 AND 600
    ORDER  BY hadm_id, chartdate DESC, seq_num DESC
),
omr_bmi AS (
    SELECT DISTINCT ON (hadm_id) hadm_id, v AS bmi
    FROM (
        SELECT hadm_id, chartdate, seq_num,
               CASE WHEN result_value ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' THEN result_value::numeric END AS v
        FROM   omr_raw
        WHERE  result_name = 'BMI (kg/m2)'
    ) t
    WHERE v BETWEEN 12 AND 80
    ORDER  BY hadm_id, chartdate DESC, seq_num DESC
),
omr_n AS (
    SELECT hadm_id, COUNT(DISTINCT chartdate) AS n_visits, MIN(days_before) AS days_since_last
    FROM   omr_raw
    GROUP  BY hadm_id
)
SELECT b.hadm_id,
       COALESCE(h.hx_hypertension, 0)          AS hx_hypertension,
       COALESCE(h.hx_diabetes, 0)              AS hx_diabetes,
       COALESCE(h.hx_obesity, 0)               AS hx_obesity,
       COALESCE(h.hx_renal_disease, 0)         AS hx_renal_disease,
       COALESCE(h.hx_prior_fetal_death_1y, 0)  AS hx_prior_fetal_death_1y,
       h.days_since_prior_fd,
       l.lab_hemoglobin, l.lab_hematocrit, l.lab_platelets, l.lab_wbc, l.lab_mcv, l.lab_rdw,
       l.lab_creatinine, l.lab_alt, l.lab_ast, l.lab_uric_acid, l.lab_urea_nitrogen, l.lab_urine_prot_creat,
       bl.sbp AS omr_sbp_last, bl.dbp AS omr_dbp_last, bm.sbp_max AS omr_sbp_max, bm.dbp_max AS omr_dbp_max,
       wt.weight_kg AS omr_weight_kg_last, bmi.bmi AS omr_bmi_last,
       COALESCE(n.n_visits, 0) AS omr_n_visits_365, n.days_since_last AS omr_days_since_last
FROM   base b
LEFT JOIN hist h         ON h.hadm_id  = b.hadm_id
LEFT JOIN labs l         ON l.hadm_id  = b.hadm_id
LEFT JOIN omr_bp_last bl ON bl.hadm_id = b.hadm_id
LEFT JOIN omr_bp_max bm  ON bm.hadm_id = b.hadm_id
LEFT JOIN omr_wt wt      ON wt.hadm_id = b.hadm_id
LEFT JOIN omr_bmi bmi    ON bmi.hadm_id = b.hadm_id
LEFT JOIN omr_n n        ON n.hadm_id  = b.hadm_id;

-- ----------------------------------------------------------------------------
-- Tabla final: conjunto de datos de muerte fetal + las nuevas columnas de variables
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.cohort_fetal_death_dataset_ext;
CREATE TABLE mimiciv.cohort_fetal_death_dataset_ext AS
SELECT c.*,
       f.hx_hypertension, f.hx_diabetes, f.hx_obesity, f.hx_renal_disease,
       f.hx_prior_fetal_death_1y, f.days_since_prior_fd,
       f.lab_hemoglobin, f.lab_hematocrit, f.lab_platelets, f.lab_wbc, f.lab_mcv, f.lab_rdw,
       f.lab_creatinine, f.lab_alt, f.lab_ast, f.lab_uric_acid, f.lab_urea_nitrogen, f.lab_urine_prot_creat,
       f.omr_sbp_last, f.omr_dbp_last, f.omr_sbp_max, f.omr_dbp_max,
       f.omr_weight_kg_last, f.omr_bmi_last, f.omr_n_visits_365, f.omr_days_since_last
FROM   mimiciv.cohort_fetal_death_dataset c
LEFT JOIN mimiciv.cohort_fetal_death_features f ON f.hadm_id = c.hadm_id;

-- ----------------------------------------------------------------------------
-- Verificaciones (esperado: 25,736 filas, 154 eventos; hemograma en cerca del 45 % de las filas y del
-- 58 % de los eventos; presión arterial OMR en cerca del 61 % de las filas y 56 % de los eventos, peso 57 %, IMC 41 %;
-- 17 admisiones con days_since_prior_fd < 90, 5 de ellas eventos)
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS admissions, COUNT(DISTINCT hadm_id) AS distinct_admissions,
       SUM(outcome_fetal_death) AS events,
       COUNT(lab_hemoglobin)  AS with_cbc,
       COUNT(lab_hemoglobin) FILTER (WHERE outcome_fetal_death = 1) AS events_with_cbc,
       COUNT(lab_creatinine)  AS with_creatinine,
       COUNT(lab_uric_acid)   AS with_uric_acid,
       SUM(hx_hypertension) AS hx_htn, SUM(hx_diabetes) AS hx_dm, SUM(hx_obesity) AS hx_obes,
       SUM(hx_renal_disease) AS hx_renal, SUM(hx_prior_fetal_death_1y) AS hx_fd_1y,
       COUNT(omr_sbp_last) AS with_omr_bp, COUNT(omr_weight_kg_last) AS with_omr_weight,
       COUNT(omr_bmi_last) AS with_omr_bmi,
       COUNT(omr_sbp_last) FILTER (WHERE outcome_fetal_death = 1) AS events_with_omr_bp,
       COUNT(*) FILTER (WHERE days_since_prior_fd <= 180) AS in_post_event_window,
       COUNT(*) FILTER (WHERE days_since_prior_fd <= 180 AND outcome_fetal_death = 1) AS events_in_window
FROM   mimiciv.cohort_fetal_death_dataset_ext;
