-- ============================================================================
-- 03_antenatal / 01_obstetric_universe_es.sql
-- Universo obstétrico y marca de parto del modelo prenatal (tarea A0)
-- Framework: etapa E2 (universo y población); sus conteos de referencia se verifican en la puerta P1
-- ============================================================================
-- Propósito: construir, solo con las tablas hosp de MIMIC-IV, la población del modelo:
--   1. mimiciv.antenatal_pregnancy_dx_codes (vista): todo código diagnóstico relacionado con el embarazo,
--      el parto o el puerperio, por texto del título y por rango CIE.
--   2. mimiciv.antenatal_delivery_drg (vista) y mimiciv.antenatal_delivery_flag (vista):
--      evidencia de parto por admisión a partir de diagnósticos, procedimientos y códigos DRG.
--   3. mimiciv.antenatal_obstetric_universe (tabla): una fila por admisión obstétrica, con la
--      marca de parto, la marca de código de mortinato y la era de codificación como columnas.
--
-- Universo obstétrico: mujeres de unos 12 a 55 años al ingreso (anchor_age + año de ingreso -
--   anchor_year) con al menos un diagnóstico de antenatal_pregnancy_dx_codes, en cualquier posición.
-- Población del modelo (columna in_population de la tabla de etiqueta, script 02): hospitalizaciones
--   de parto, más las admisiones con código de mortinato que la marca de parto deja fuera
--   porque también tienen un código de aborto.
--
-- Marca de parto, fuentes (verificadas el 23/10/2026):
--   * CIE-10: HCUP Statistical Brief #312 Appendices, Tabla A.1 (2024):
--       dx Z37, O80, O82, O75.82; proc 10D00Z0-10D00Z2, 10D07Z3-10D07Z8, 10E0XZZ;
--       MS-DRG 765-768, 774-775, 783-788, 796-798, 805-807. Exclusiones: O0x (resultado abortivo), 10A0.
--       https://hcup-us.ahrq.gov/reports/statbriefs/HCUP-SB-312-Appendices-508.pdf
--   * CIE-9: Berger et al., Obstet Gynecol 2023;142, Apéndice 1 (adaptado de Kuklina et al.,
--       Matern Child Health J 2008;12:469-77): dx V27.x, 650; proc 72x-74x procedimientos de parto;
--       CMS-DRG 370-375, MS-DRG 765-768, 774-775. Exclusiones: 630-639, 69.01, 69.51, 74.91, 75.0.
--   * Los mortinatos (Z37.1/.4/.7, V27.1/.4/.7) se mantienen como partos: un mortinato es un parto
--     y es el desenlace de este modelo. La columna has_stillbirth_code los marca.
--   * is_delivery = evidencia de parto Y ningún código de aborto, ectópico o mola.
--   * La evidencia DRG se usa solo si existe la tabla mimiciv.drgcodes (tipo HCFA).
--
-- El script solo crea objetos cuyo nombre empieza por antenatal_; no modifica ninguna otra tabla o vista de
-- la base. Ejecutar el script completo en una conexión (DBeaver: Alt+X). Solo se producen
-- resultados agregados: NO publicar filas con subject_id o hadm_id.
-- ============================================================================

SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS mimiciv.antenatal_obstetric_universe;
DROP VIEW  IF EXISTS mimiciv.antenatal_delivery_flag;
DROP VIEW  IF EXISTS mimiciv.antenatal_delivery_drg;
DROP VIEW  IF EXISTS mimiciv.antenatal_pregnancy_dx_codes;

-- ----------------------------------------------------------------------------
-- 1. Códigos diagnósticos relacionados con el embarazo, el parto o el puerperio
-- ----------------------------------------------------------------------------
CREATE VIEW mimiciv.antenatal_pregnancy_dx_codes AS
SELECT DISTINCT icd_code, icd_version, long_title
FROM   mimiciv.d_icd_diagnoses
WHERE  long_title ILIKE '%PREGNAN%'
   OR  long_title ILIKE '%OBSTETRIC%'
   OR  long_title ILIKE '%FETAL%'
   OR  long_title ILIKE '%DELIVERY%'
   OR  long_title ILIKE '%PUERPERIUM%'
   OR  long_title ILIKE '%POSTPARTUM%'
   OR  long_title ILIKE '%GESTATION%'
   -- CIE-9: 630-679 (embarazo, parto y puerperio) y V22-V24, V27, V28
   OR (icd_version = 9  AND icd_code ~ '^[0-9]' AND LEFT(icd_code, 3)::int BETWEEN 630 AND 679)
   OR (icd_version = 9  AND LEFT(icd_code, 3) IN ('V22', 'V23', 'V24', 'V27', 'V28'))
   -- CIE-10: capítulo O (O00-O9A) y Z33, Z34, Z37, Z39
   OR (icd_version = 10 AND LEFT(icd_code, 1) = 'O')
   OR (icd_version = 10 AND (icd_code LIKE 'Z33%' OR icd_code LIKE 'Z34%'
                          OR icd_code LIKE 'Z37%' OR icd_code LIKE 'Z39%'));

-- ----------------------------------------------------------------------------
-- 2. Evidencia de parto por admisión
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('mimiciv.drgcodes') IS NOT NULL THEN
        EXECUTE $v$
            CREATE VIEW mimiciv.antenatal_delivery_drg AS
            SELECT DISTINCT hadm_id
            FROM   mimiciv.drgcodes
            WHERE  drg_type = 'HCFA'
              AND  drg_code IN ('370','371','372','373','374','375',
                                '765','766','767','768','774','775',
                                '783','784','785','786','787','788',
                                '796','797','798','805','806','807')
        $v$;
    ELSE
        EXECUTE 'CREATE VIEW mimiciv.antenatal_delivery_drg AS SELECT NULL::int AS hadm_id WHERE FALSE';
        RAISE NOTICE 'mimiciv.drgcodes not found: DRG evidence disabled';
    END IF;
END $$;

CREATE VIEW mimiciv.antenatal_delivery_flag AS
WITH dx AS (
    SELECT d.hadm_id,
           BOOL_OR(
               (d.icd_version = 10 AND (d.icd_code LIKE 'Z37%' OR d.icd_code LIKE 'O80%'
                                         OR d.icd_code LIKE 'O82%' OR d.icd_code LIKE 'O7582%'))
            OR (d.icd_version = 9  AND (d.icd_code LIKE 'V27%' OR d.icd_code LIKE '650%'))
           ) AS by_dx,
           BOOL_OR(
               (d.icd_version = 10 AND (d.icd_code LIKE 'Z371%' OR d.icd_code LIKE 'Z374%' OR d.icd_code LIKE 'Z377%'))
            OR (d.icd_version = 9  AND (d.icd_code LIKE 'V271%' OR d.icd_code LIKE 'V274%' OR d.icd_code LIKE 'V277%'))
           ) AS has_stillbirth_code,
           BOOL_OR(
               (d.icd_version = 10 AND (d.icd_code LIKE 'O00%' OR d.icd_code LIKE 'O01%' OR d.icd_code LIKE 'O02%'
                                         OR d.icd_code LIKE 'O03%' OR d.icd_code LIKE 'O04%' OR d.icd_code LIKE 'O07%'
                                         OR d.icd_code LIKE 'O08%' OR d.icd_code LIKE 'Z332%'))
            OR (d.icd_version = 9  AND d.icd_code ~ '^63[0-9]')
           ) AS has_abortive_dx
    FROM   mimiciv.diagnoses_icd d
    GROUP  BY d.hadm_id
),
pr AS (
    SELECT p.hadm_id,
           BOOL_OR(
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
           ) AS by_proc,
           BOOL_OR(
               (p.icd_version = 10 AND p.icd_code LIKE '10A0%')
            OR (p.icd_version = 9  AND p.icd_code IN ('6901','6951','7491','750'))
           ) AS has_abortive_proc
    FROM   mimiciv.procedures_icd p
    GROUP  BY p.hadm_id
)
SELECT a.subject_id,
       a.hadm_id,
       COALESCE(dx.by_dx, FALSE)                 AS by_dx,
       COALESCE(pr.by_proc, FALSE)               AS by_proc,
       (drg.hadm_id IS NOT NULL)                 AS by_drg,
       COALESCE(dx.has_stillbirth_code, FALSE)   AS has_stillbirth_code,
       (COALESCE(dx.has_abortive_dx, FALSE) OR COALESCE(pr.has_abortive_proc, FALSE)) AS has_abortive_code,
       ( (COALESCE(dx.by_dx, FALSE) OR COALESCE(pr.by_proc, FALSE) OR drg.hadm_id IS NOT NULL)
         AND NOT (COALESCE(dx.has_abortive_dx, FALSE) OR COALESCE(pr.has_abortive_proc, FALSE)) ) AS is_delivery
FROM   mimiciv.admissions a
LEFT JOIN dx  ON dx.hadm_id  = a.hadm_id
LEFT JOIN pr  ON pr.hadm_id  = a.hadm_id
LEFT JOIN mimiciv.antenatal_delivery_drg drg ON drg.hadm_id = a.hadm_id;

-- ----------------------------------------------------------------------------
-- 3. Universo obstétrico: una fila por admisión
-- ----------------------------------------------------------------------------
CREATE TABLE mimiciv.antenatal_obstetric_universe AS
WITH universe AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
           p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) AS approx_age
    FROM   mimiciv.admissions a
    JOIN   mimiciv.patients p ON p.subject_id = a.subject_id
    WHERE  p.gender = 'F'
      AND  p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
      AND  a.hadm_id IN (SELECT d.hadm_id
                         FROM   mimiciv.diagnoses_icd d
                         JOIN   mimiciv.antenatal_pregnancy_dx_codes c
                                ON c.icd_code = d.icd_code AND c.icd_version = d.icd_version)
),
era AS (
    SELECT hadm_id,
           BOOL_OR(icd_version = 9)  AS has_icd9_dx,
           BOOL_OR(icd_version = 10) AS has_icd10_dx
    FROM   mimiciv.diagnoses_icd
    WHERE  hadm_id IN (SELECT hadm_id FROM universe)
    GROUP  BY hadm_id
)
SELECT u.subject_id,
       u.hadm_id,
       u.admittime,
       u.dischtime,
       u.approx_age,
       COALESCE(f.is_delivery, FALSE)          AS is_delivery,
       COALESCE(f.has_stillbirth_code, FALSE)  AS has_stillbirth_code,
       COALESCE(f.has_abortive_code, FALSE)    AS has_abortive_code,
       COALESCE(e.has_icd9_dx, FALSE)          AS has_icd9_dx,
       COALESCE(e.has_icd10_dx, FALSE)         AS has_icd10_dx
FROM   universe u
LEFT JOIN mimiciv.antenatal_delivery_flag f ON f.hadm_id = u.hadm_id
LEFT JOIN era                             e ON e.hadm_id = u.hadm_id;

ALTER TABLE mimiciv.antenatal_obstetric_universe ADD PRIMARY KEY (hadm_id);
CREATE INDEX ON mimiciv.antenatal_obstetric_universe (subject_id);

-- ============================================================================
-- VERIFICACIONES (solo agregadas)
-- ============================================================================

-- Q-U1. Conteos de referencia (esperado: 25.736 admisiones obstétricas de 15.084 pacientes; 19.425 hospitalizaciones
--       de parto; 19.440 admisiones en la población del modelo)
SELECT 'Q-U1 reference counts' AS q,
       COUNT(*)                                                    AS n_obstetric_admissions,
       COUNT(DISTINCT subject_id)                                  AS n_patients,
       COUNT(*) FILTER (WHERE is_delivery)                         AS n_delivery_hospitalizations,
       COUNT(*) FILTER (WHERE has_stillbirth_code)                 AS n_with_stillbirth_code,
       COUNT(*) FILTER (WHERE is_delivery OR has_stillbirth_code)  AS n_population
FROM   mimiciv.antenatal_obstetric_universe;

-- Q-U2. Población por evidencia de parto y era de codificación
SELECT 'Q-U2 population by evidence and era' AS q,
       CASE WHEN has_icd10_dx AND NOT has_icd9_dx THEN 'ICD-10 only'
            WHEN has_icd9_dx AND NOT has_icd10_dx THEN 'ICD-9 only'
            WHEN has_icd9_dx AND has_icd10_dx     THEN 'both'
            ELSE 'no diagnoses' END                                AS icd_era,
       COUNT(*) FILTER (WHERE is_delivery)                         AS n_delivery,
       COUNT(*) FILTER (WHERE has_stillbirth_code AND NOT is_delivery) AS n_stillbirth_code_without_delivery_flag
FROM   mimiciv.antenatal_obstetric_universe
WHERE  is_delivery OR has_stillbirth_code
GROUP  BY 2 ORDER BY 2;
