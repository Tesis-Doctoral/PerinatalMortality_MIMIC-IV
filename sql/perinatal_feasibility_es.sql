-- ============================================================================
-- VERIFICACIÓN DE FACTIBILIDAD: muerte perinatal (componente de muerte fetal)
-- ============================================================================
-- Objetivo: contar cuántas admisiones de la cohorte materna existente tienen un
-- código ICD de muerte fetal (mortinato), para decidir si un modelo de este
-- desenlace es factible ANTES de construir cualquier conjunto de datos.
--
-- Definición a probar (período perinatal OMS / ICD-10): muerte fetal desde las 22
-- semanas completas de gestación. Solo el componente fetal es identificable a partir de
-- la historia de la madre; las muertes neonatales tempranas están en la historia del recién nacido y
-- no se usan aquí.
--
-- Cohorte: mimiciv.cohort_smm_dataset (las 25,736 admisiones de la cohorte de SMM
-- del repositorio materno).
-- Este script solo lee datos (tabla temporal + SELECT). Ejecutar como script
-- completo (DBeaver: Alt+X) en UNA sola conexión, porque la tabla temporal debe
-- persistir entre sentencias, y compartir el resultado de cada consulta.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 0: patrones de códigos de muerte fetal
--   strict  = el código indica que el feto murió (mortinato / muerte intrauterina)
--   partial = embarazo múltiple en el que solo murieron algunos fetos; se mantienen aparte para
--             decidir si se incluyen
-- Las pérdidas previables (aborto, ectópico, aborto retenido O02.1, 630-639) NO se
-- incluyen: están por debajo de las 22 semanas.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS fd_patterns;
CREATE TEMP TABLE fd_patterns (
    icd_version INT,
    code_prefix VARCHAR(10),
    tier        VARCHAR(10),
    label       VARCHAR(80)
);

INSERT INTO fd_patterns VALUES
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

-- Admisiones de la cohorte que tienen al menos uno de esos códigos
DROP TABLE IF EXISTS fd_hits;
CREATE TEMP TABLE fd_hits AS
SELECT c.subject_id, c.hadm_id, d.icd_version, d.icd_code, d.seq_num,
       p.tier, p.label
FROM   mimiciv.cohort_smm_dataset c
JOIN   mimiciv.diagnoses_icd d
       ON d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
JOIN   fd_patterns p
       ON p.icd_version = d.icd_version
      AND d.icd_code LIKE p.code_prefix || '%';

-- ----------------------------------------------------------------------------
-- Consulta 1: tamaño de la cohorte (deben ser 25,736 admisiones, 15,084 pacientes)
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS admissions, COUNT(DISTINCT subject_id) AS patients
FROM   mimiciv.cohort_smm_dataset;

-- ----------------------------------------------------------------------------
-- Consulta 2: inventario de los códigos de muerte fetal realmente presentes en la cohorte
-- ----------------------------------------------------------------------------
SELECT h.icd_version, h.icd_code, h.tier, dd.long_title,
       COUNT(DISTINCT h.hadm_id) AS admissions
FROM   fd_hits h
LEFT JOIN mimiciv.d_icd_diagnoses dd
       ON dd.icd_code = h.icd_code AND dd.icd_version = h.icd_version
GROUP  BY h.icd_version, h.icd_code, h.tier, dd.long_title
ORDER  BY admissions DESC;

-- ----------------------------------------------------------------------------
-- Consulta 3: número de eventos (admisiones distintas) bajo cada definición,
-- por versión de ICD. Es la cifra clave para la factibilidad.
-- ----------------------------------------------------------------------------
SELECT icd_version,
       COUNT(DISTINCT hadm_id) FILTER (WHERE tier = 'strict')            AS strict_only_admissions,
       COUNT(DISTINCT hadm_id)                                           AS strict_or_partial_admissions,
       COUNT(DISTINCT subject_id) FILTER (WHERE tier = 'strict')         AS strict_patients
FROM   fd_hits
GROUP  BY icd_version
UNION ALL
SELECT NULL,
       COUNT(DISTINCT hadm_id) FILTER (WHERE tier = 'strict'),
       COUNT(DISTINCT hadm_id),
       COUNT(DISTINCT subject_id) FILTER (WHERE tier = 'strict')
FROM   fd_hits;

-- ----------------------------------------------------------------------------
-- Consulta 4: posición del código de muerte fetal en la lista de diagnósticos
-- (seq_num 1-4 significa que está entre los diagnósticos principales)
-- ----------------------------------------------------------------------------
SELECT CASE WHEN seq_num <= 4 THEN '1-4' WHEN seq_num <= 10 THEN '5-10' ELSE '>10' END AS position,
       COUNT(DISTINCT hadm_id) AS admissions
FROM   fd_hits
WHERE  tier = 'strict'
GROUP  BY 1
ORDER  BY 1;

-- ----------------------------------------------------------------------------
-- Consulta 5: edad gestacional (solo ICD-10, códigos Z3A.xx = semanas de gestación)
-- entre las admisiones con un código estricto de muerte fetal
-- ----------------------------------------------------------------------------
WITH fd_adm AS (
    SELECT DISTINCT subject_id, hadm_id FROM fd_hits
    WHERE tier = 'strict' AND icd_version = 10
),
weeks AS (
    SELECT f.hadm_id,
           MAX(substring(d.icd_code FROM 4 FOR 2)::INT) AS gest_weeks
    FROM   fd_adm f
    JOIN   mimiciv.diagnoses_icd d
           ON d.subject_id = f.subject_id AND d.hadm_id = f.hadm_id
    WHERE  d.icd_version = 10
      AND  d.icd_code ~ '^Z3A[0-9]{2}'
      AND  substring(d.icd_code FROM 4 FOR 2)::INT >= 8   -- Z3A.00 / Z3A.01 = no especificado / <8 semanas
    GROUP  BY f.hadm_id
)
SELECT CASE WHEN w.gest_weeks IS NULL THEN 'no Z3A code'
            WHEN w.gest_weeks <  22 THEN '< 22 weeks'
            WHEN w.gest_weeks <  28 THEN '22-27 weeks'
            ELSE '>= 28 weeks' END AS gestational_age,
       COUNT(*) AS admissions
FROM   fd_adm f
LEFT JOIN weeks w ON w.hadm_id = f.hadm_id
GROUP  BY 1
ORDER  BY 1;

-- ----------------------------------------------------------------------------
-- Consulta 6: tasa de eventos según los posibles denominadores
--   (a) toda la cohorte, (b) hospitalizaciones de parto de la cohorte
-- ----------------------------------------------------------------------------
SELECT 'whole cohort' AS denominator,
       COUNT(*) AS admissions,
       COUNT(*) FILTER (WHERE c.hadm_id IN (SELECT hadm_id FROM fd_hits WHERE tier = 'strict')) AS strict_events
FROM   mimiciv.cohort_smm_dataset c
UNION ALL
SELECT 'delivery hospitalizations',
       COUNT(*),
       COUNT(*) FILTER (WHERE c.hadm_id IN (SELECT hadm_id FROM fd_hits WHERE tier = 'strict'))
FROM   mimiciv.cohort_smm_dataset c
WHERE  c.is_delivery_hospitalization = 1;

-- ----------------------------------------------------------------------------
-- Consulta 7: solapamiento con los desenlaces existentes (SMM y muerte materna)
-- ----------------------------------------------------------------------------
SELECT COUNT(DISTINCT c.hadm_id)                                        AS fetal_death_admissions,
       COUNT(DISTINCT c.hadm_id) FILTER (WHERE c.outcome_smm = 1)       AS also_smm,
       COUNT(DISTINCT c.hadm_id) FILTER (WHERE a.hospital_expire_flag = 1) AS maternal_died_same_admission
FROM   mimiciv.cohort_smm_dataset c
JOIN   mimiciv.admissions a ON a.hadm_id = c.hadm_id
WHERE  c.hadm_id IN (SELECT hadm_id FROM fd_hits WHERE tier = 'strict');

-- ----------------------------------------------------------------------------
-- Consulta 8: ¿hay códigos de muerte fetal en admisiones de mujeres que la
-- cohorte actual deja fuera? (la cohorte exige un diagnóstico obstétrico en la
-- posición <= 4; la muerte fetal puede estar codificada más abajo.)
-- ----------------------------------------------------------------------------
SELECT COUNT(DISTINCT d.hadm_id) AS strict_admissions_outside_cohort
FROM   mimiciv.diagnoses_icd d
JOIN   fd_patterns p
       ON p.icd_version = d.icd_version
      AND d.icd_code LIKE p.code_prefix || '%'
      AND p.tier = 'strict'
JOIN   mimiciv.patients pt ON pt.subject_id = d.subject_id AND pt.gender = 'F'
WHERE  d.hadm_id NOT IN (SELECT hadm_id FROM mimiciv.cohort_smm_dataset);

-- ----------------------------------------------------------------------------
-- Consulta 9: eventos estrictos de muerte fetal por versión de ICD y marca de parto.
-- La marca (vista hadm_delivery_hospitalization) solo busca códigos ICD-10
-- (Z37, O80, O82), por lo que las admisiones ICD-9 nunca pueden marcarse como partos.
-- Esperado si esa es la explicación: eventos ICD-9 todos con marca = 0.
-- Ejecutar en la misma conexión que el script (usa la tabla temporal fd_hits).
-- ----------------------------------------------------------------------------
SELECT h.icd_version,
       c.is_delivery_hospitalization AS delivery_flag,
       COUNT(DISTINCT c.hadm_id)     AS strict_events
FROM   fd_hits h
JOIN   mimiciv.cohort_smm_dataset c ON c.hadm_id = h.hadm_id
WHERE  h.tier = 'strict'
GROUP  BY 1, 2
ORDER  BY 1, 2;
