-- ============================================================================
-- Muerte perinatal (componente fetal): construye mimiciv.cohort_fetal_death_dataset
-- ============================================================================
-- Desenlace : muerte fetal identificada a partir de los códigos ICD de la MADRE (estricta + parcial,
--            154 admisiones en la verificación de factibilidad; 136 solo estrictas).
-- Población : las mismas 25,736 admisiones de la cohorte de SMM del repositorio materno
--            (mimiciv.cohort_smm_dataset), de modo que los modelos comparten la cohorte.
-- Período perinatal (OMS / ICD-10): desde las 22 semanas completas. MIMIC-IV no tiene
-- un vínculo madre-recién nacido validado, por lo que las muertes neonatales tempranas NO se capturan.
--
-- REQUISITO: existe mimiciv.cohort_smm_dataset (construida por
-- sql/03_cohort_smm/smm_dataset.sql del repositorio MaternalMortality_MIMIC-IV).
-- Este script solo AGREGA columnas de desenlace y de sensibilidad a una copia de ella; no
-- modifica la tabla de origen. Ejecutar como script completo (DBeaver: Alt+X).
--
-- Columnas agregadas (NINGUNA es un predictor; el notebook las excluye de X):
--   outcome_fetal_death   1 = código de muerte fetal estricto o parcial (desenlace principal)
--   fd_strict             1 = solo código estricto (análisis de sensibilidad)
--   admission_icd_version 9 o 10 (época de codificación)
--   gest_weeks            semanas de gestación según Z3A.xx (solo ICD-10; NULL en los demás casos)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 1: patrones de códigos (tabla persistente; misma lista que perinatal_feasibility.sql)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.fetal_death_code_patterns CASCADE;
CREATE TABLE mimiciv.fetal_death_code_patterns (
    icd_version INT,
    code_prefix VARCHAR(10),
    tier        VARCHAR(10),
    label       VARCHAR(80)
);

INSERT INTO mimiciv.fetal_death_code_patterns VALUES
 (10, 'O364', 'strict',  'Maternal care for intrauterine death'),
 (10, 'Z371', 'strict',  'Outcome of delivery: single stillborn'),
 (10, 'Z374', 'strict',  'Outcome of delivery: twins, both stillborn'),
 (10, 'Z377', 'strict',  'Outcome of delivery: other multiple, all stillborn'),
 (10, 'Z373', 'partial', 'Outcome of delivery: twins, one liveborn one stillborn'),
 (10, 'Z376', 'partial', 'Outcome of delivery: other multiple, some liveborn'),
 (10, 'O312', 'partial', 'Continuing pregnancy after intrauterine death of one fetus'),
 (9,  '6564', 'strict',  'Intrauterine death (656.4x)'),
 (9,  'V271', 'strict',  'Outcome of delivery: single stillborn'),
 (9,  'V274', 'strict',  'Outcome of delivery: twins, both stillborn'),
 (9,  'V277', 'strict',  'Outcome of delivery: other multiple, all stillborn'),
 (9,  'V273', 'partial', 'Outcome of delivery: twins, one liveborn one stillborn'),
 (9,  'V276', 'partial', 'Outcome of delivery: other multiple, some liveborn');

-- ----------------------------------------------------------------------------
-- Paso 2: admisiones con un código de muerte fetal (cualquier posición en la lista de diagnósticos)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.hadm_with_fetal_death;
CREATE VIEW mimiciv.hadm_with_fetal_death AS
SELECT d.subject_id, d.hadm_id,
       MAX(CASE WHEN p.tier = 'strict' THEN 1 ELSE 0 END) AS has_strict
FROM   mimiciv.diagnoses_icd d
JOIN   mimiciv.fetal_death_code_patterns p
       ON p.icd_version = d.icd_version
      AND d.icd_code LIKE p.code_prefix || '%'
GROUP  BY d.subject_id, d.hadm_id;

-- ----------------------------------------------------------------------------
-- Paso 3: conjunto de datos final = cohort_smm_dataset + desenlace + columnas de sensibilidad
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.cohort_fetal_death_dataset;
CREATE TABLE mimiciv.cohort_fetal_death_dataset AS
SELECT c.*,
       CASE WHEN fd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS outcome_fetal_death,
       COALESCE(fd.has_strict, 0)                         AS fd_strict,
       v.icd_version                                      AS admission_icd_version,
       gw.gest_weeks
FROM   mimiciv.cohort_smm_dataset c
LEFT JOIN mimiciv.hadm_with_fetal_death fd
       ON fd.subject_id = c.subject_id AND fd.hadm_id = c.hadm_id
LEFT JOIN (SELECT hadm_id, MAX(icd_version) AS icd_version
           FROM   mimiciv.diagnoses_icd
           GROUP  BY hadm_id) v
       ON v.hadm_id = c.hadm_id
LEFT JOIN (SELECT hadm_id,
                  MAX(substring(icd_code FROM 4 FOR 2)::INT) AS gest_weeks
           FROM   mimiciv.diagnoses_icd
           WHERE  icd_version = 10
             AND  icd_code ~ '^Z3A[0-9]{2}'
             AND  substring(icd_code FROM 4 FOR 2)::INT >= 8   -- Z3A.00 / Z3A.01 = no especificado / <8 semanas
           GROUP  BY hadm_id) gw
       ON gw.hadm_id = c.hadm_id;

-- ----------------------------------------------------------------------------
-- Paso 4: verificaciones (esperado: 25,736 filas; 154 eventos; 136 estrictos; 2 con SMM
-- entre los eventos estrictos; 0 muertes maternas entre los eventos estrictos)
-- ----------------------------------------------------------------------------
SELECT COUNT(*)                                   AS admissions,
       COUNT(DISTINCT hadm_id)                    AS distinct_admissions,
       COUNT(DISTINCT subject_id)                 AS patients,
       SUM(outcome_fetal_death)                   AS events_strict_or_partial,
       SUM(fd_strict)                             AS events_strict,
       ROUND(100.0 * AVG(outcome_fetal_death), 3) AS prevalence_pct
FROM   mimiciv.cohort_fetal_death_dataset;

SELECT admission_icd_version, outcome_fetal_death, fd_strict, COUNT(*) AS admissions
FROM   mimiciv.cohort_fetal_death_dataset
GROUP  BY 1, 2, 3
ORDER  BY 1, 2, 3;
