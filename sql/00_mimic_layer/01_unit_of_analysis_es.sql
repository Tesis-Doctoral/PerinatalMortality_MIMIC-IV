-- ============================================================================
-- 00_mimic_layer / 01_unit_of_analysis.sql
-- Adaptador de MIMIC-IV de la etapa E4 del framework (unidad de análisis y traslape) -- plan v2, tarea T17
-- ============================================================================
-- Propósito: construir mimiciv.unit_of_analysis_v2, UNA FILA POR ADMISIÓN del universo obstétrico
--   revisado (mimiciv.cohort_obstetric_v2), con todo lo que la capa de método necesita para definir la
--   unidad, la agrupación, el tiempo y el traslape entre registros, y NADA sobre el desenlace.
--   Este script es INDEPENDIENTE DEL DESENLACE: sin etiqueta, sin evento, sin códigos diagnósticos de un desenlace.
--   La misma tabla sirve al modelo de muerte fetal (perinatal) y a los modelos maternos; los módulos de
--   desenlace (por ejemplo 01_labels/02_fetal_death_label_by_admission.sql) se unen a ella por hadm_id.
--
-- Contrato de datos del framework (framework_es.md, sección 3.1) -> columnas de esta tabla:
--   unit_id    = hadm_id                      (un registro = una admisión hospitalaria)
--   group_id   = subject_id                   (todas las particiones de validación se agrupan por paciente)
--   t0         = admittime                    (tiempo cero, decisión D7)
--   t_pred     = admittime + 6 horas          (punto de predicción, decisión D6)
--   t_end      = dischtime                    (fin de la admisión; la etiqueta no tiene tiempo de evento)
--   period     = icd_era, anchor_year_group, approx_year_low
--   Traslape   = adm_rank, gap_days, chain_30 / chain_90 / chain_180 (cadenas de embarazo)
--   unit_id y group_id son alias duplicados de hadm_id y subject_id a propósito: la capa de método
--   lee los nombres del contrato, y los cruces con tablas de MIMIC leen los nombres nativos.
--
-- Decisiones aplicadas:
--   D4  un registro por hospitalización de parto, agrupado por paciente; la cadena de admisiones
--       unidas por un intervalo de hasta 90 días es un análisis de SENSIBILIDAD -> columnas chain_*.
--       La población (D3) NO se aplica aquí: depende de un código de mortinato, que es parte del
--       desenlace, por eso la marca in_pop_d3 se queda en la tabla de etiqueta. Aquí solo is_delivery_v2.
--   D6  punto de predicción = ingreso + 6 h (el 6 se escribe una sola vez, en la columna t_pred).
--   D8  las admisiones que terminan antes de ingreso + 6 h se marcan (ends_before_6h), no se borran.
--
-- Definiciones (las mismas de la auditoría de conteos, Q-C2 y Q-C4, para poder reproducir las cifras):
--   adm_rank   = orden de la admisión entre las del paciente en el universo
--                (por admittime, desempate por hadm_id).
--   gap_days   = días calendario entre la fecha de la admisión y la fecha de la admisión previa
--                del mismo paciente (NULL para la primera). Basado en fechas, como en la auditoría.
--   chain_G    = número de la cadena de embarazo del paciente: una cadena nueva empieza cuando el intervalo
--                con la admisión previa es NULL o mayor que G días (G = 30, 90, 180).
--   chainG_pos / chainG_n_adm / chainG_n_delivery / is_chainG_last (solo G = 90, la de D4).
--   Las fechas de MIMIC-IV están desplazadas por paciente: los intervalos y las estancias son válidos dentro
--   de un paciente, los años calendario no (de ahí anchor_year_group y approx_year_low).
--
-- Prerrequisitos: mimiciv.cohort_obstetric_v2 (proyecto materno, sql/04_labels), mimiciv.admissions,
--   mimiciv.patients. Las verificaciones Q-T17e también necesitan mimiciv.fetal_death_label_v2 (tarea T16), y
--   Q-T17c / Q-T17d usan su columna de evento fd_any solo para reproducir las cifras de la auditoría.
--
-- Ejecute el script completo en una sola conexión (DBeaver: Alt+X). La tabla es persistente, así que las
--   verificaciones se pueden volver a correr solas. Solo se producen resultados agregados: NO publique
--   filas con subject_id o hadm_id.
-- ============================================================================

SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS mimiciv.unit_of_analysis_v2;

CREATE TABLE mimiciv.unit_of_analysis_v2 AS
WITH base AS (
    -- una fila por admisión del universo, con orden, intervalo y periodo
    SELECT c.subject_id,
           c.hadm_id,
           c.admittime,
           a.dischtime,
           COALESCE(c.is_delivery_v2, FALSE)                                         AS is_delivery_v2,
           CASE WHEN c.has_icd10_dx AND NOT c.has_icd9_dx THEN 'ICD-10 only'
                WHEN c.has_icd9_dx AND NOT c.has_icd10_dx THEN 'ICD-9 only'
                WHEN c.has_icd9_dx AND c.has_icd10_dx     THEN 'both'
                ELSE 'no diagnoses' END                                              AS icd_era,
           pt.anchor_year_group,
           CAST(LEFT(pt.anchor_year_group, 4) AS int)
             + (EXTRACT(YEAR FROM c.admittime)::int - pt.anchor_year)                AS approx_year_low,
           ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.admittime, c.hadm_id) AS adm_rank,
           COUNT(*)     OVER (PARTITION BY c.subject_id)                             AS n_adm_patient,
           (c.admittime::date - LAG(c.admittime::date)
                OVER (PARTITION BY c.subject_id ORDER BY c.admittime, c.hadm_id))    AS gap_days
    FROM   mimiciv.cohort_obstetric_v2 c
    JOIN   mimiciv.admissions a  ON a.hadm_id    = c.hadm_id
    JOIN   mimiciv.patients   pt ON pt.subject_id = c.subject_id
),
chains AS (
    -- número de cadena para cada límite de intervalo: una cadena nueva empieza tras un intervalo superior al límite
    SELECT b.*,
           SUM(CASE WHEN b.gap_days IS NULL OR b.gap_days >  30 THEN 1 ELSE 0 END)
               OVER (PARTITION BY b.subject_id ORDER BY b.admittime, b.hadm_id) AS chain_30,
           SUM(CASE WHEN b.gap_days IS NULL OR b.gap_days >  90 THEN 1 ELSE 0 END)
               OVER (PARTITION BY b.subject_id ORDER BY b.admittime, b.hadm_id) AS chain_90,
           SUM(CASE WHEN b.gap_days IS NULL OR b.gap_days > 180 THEN 1 ELSE 0 END)
               OVER (PARTITION BY b.subject_id ORDER BY b.admittime, b.hadm_id) AS chain_180
    FROM   base b
),
chain90 AS (
    -- posición y tamaño de la cadena de 90 días (la de la decisión D4)
    SELECT k.*,
           ROW_NUMBER() OVER (PARTITION BY k.subject_id, k.chain_90 ORDER BY k.admittime, k.hadm_id) AS chain90_pos,
           COUNT(*)     OVER (PARTITION BY k.subject_id, k.chain_90)                                 AS chain90_n_adm,
           COUNT(*) FILTER (WHERE k.is_delivery_v2)
                        OVER (PARTITION BY k.subject_id, k.chain_90)                                 AS chain90_n_delivery
    FROM   chains k
)
SELECT h.hadm_id                                                   AS unit_id,
       h.subject_id                                                AS group_id,
       h.hadm_id,
       h.subject_id,
       -- tiempos del contrato (D6, D7); la etiqueta no tiene tiempo de evento
       h.admittime                                                 AS t0,
       h.admittime + INTERVAL '6 hours'                            AS t_pred,
       h.dischtime                                                 AS t_end,
       h.admittime,
       h.dischtime,
       EXTRACT(EPOCH FROM (h.dischtime - h.admittime)) / 3600.0    AS los_hours,
       COALESCE(h.dischtime < h.admittime + INTERVAL '6 hours', FALSE) AS ends_before_6h,
       -- periodo
       h.icd_era,
       h.anchor_year_group,
       h.approx_year_low,
       -- unidad y traslape
       h.is_delivery_v2,
       h.adm_rank,
       (h.adm_rank = 1)                                            AS is_first_admission,
       h.n_adm_patient,
       h.gap_days,
       h.chain_30,
       h.chain_90,
       h.chain_180,
       h.chain90_pos,
       h.chain90_n_adm,
       h.chain90_n_delivery,
       (h.chain90_pos = h.chain90_n_adm)                           AS is_chain90_last
FROM   chain90 h;

ALTER TABLE mimiciv.unit_of_analysis_v2 ADD PRIMARY KEY (hadm_id);
CREATE INDEX idx_unit_of_analysis_v2_subject ON mimiciv.unit_of_analysis_v2 (subject_id);

-- ============================================================================
-- VERIFICACIONES (solo agregados) -- corra cada una y pegue el resultado
-- ============================================================================

-- Q-T17a. Integridad: una fila por admisión del universo y las cifras de la auditoría de conteos
--         (esperado: 25,736 unidades, 15,084 pacientes, 19,425 hospitalizaciones de parto, 15,084 primeras admisiones)
SELECT 'Q-T17a integrity' AS q,
       COUNT(*)                                       AS n_rows,
       COUNT(DISTINCT hadm_id)                        AS n_units,
       COUNT(DISTINCT subject_id)                     AS n_patients,
       COUNT(*) FILTER (WHERE is_delivery_v2)         AS n_delivery_hosp,
       COUNT(*) FILTER (WHERE is_first_admission)     AS n_first_admission,
       (SELECT COUNT(*) FROM mimiciv.cohort_obstetric_v2) AS n_universe,
       COUNT(*) FILTER (WHERE t0 IS NULL OR t_end IS NULL)   AS n_time_missing,
       COUNT(*) FILTER (WHERE los_hours < 0)          AS n_negative_los,
       COUNT(*) FILTER (WHERE ends_before_6h)         AS n_end_before_6h
FROM   mimiciv.unit_of_analysis_v2;

-- Q-T17b. Cadenas de embarazo para cada límite de intervalo (cadenas esperadas: 23,257 / 22,080 / 21,485)
--         y cadenas con más de una hospitalización de parto (lo que cambia la sensibilidad de 90 días de D4)
SELECT 'Q-T17b pregnancy chains' AS q, g.gap_limit,
       COUNT(*)                                                      AS n_chains,
       COUNT(*) FILTER (WHERE c.n_adm > 1)                           AS n_chains_with_2plus_adm,
       MAX(c.n_adm)                                                  AS max_adm_in_chain,
       COUNT(*) FILTER (WHERE c.n_delivery >= 2)                     AS n_chains_with_2plus_deliveries
FROM  (VALUES (30), (90), (180)) AS g(gap_limit)
JOIN  LATERAL (
        SELECT u.subject_id,
               CASE g.gap_limit WHEN 30 THEN u.chain_30 WHEN 90 THEN u.chain_90 ELSE u.chain_180 END AS chain_id,
               COUNT(*)                                  AS n_adm,
               COUNT(*) FILTER (WHERE u.is_delivery_v2)  AS n_delivery
        FROM   mimiciv.unit_of_analysis_v2 u
        GROUP  BY 1, 2
      ) c ON TRUE
GROUP  BY g.gap_limit
ORDER  BY g.gap_limit;

-- Q-T17c. Intervalo con la admisión previa del mismo paciente, con los eventos de la tabla de etiqueta
--         (reproduce la Q-C2 de la auditoría; la columna de evento viene de T16 y se usa solo para contar)
SELECT 'Q-T17c gap to the previous admission' AS q,
       CASE WHEN u.gap_days IS NULL THEN '0 first admission of the patient'
            WHEN u.gap_days <  90   THEN '1 under 90 days'
            WHEN u.gap_days < 180   THEN '2 90-179 days'
            WHEN u.gap_days < 365   THEN '3 180-364 days'
            ELSE                         '4 365 days or more' END AS gap_to_previous_admission,
       COUNT(*)                         AS n_admissions,
       COUNT(*) FILTER (WHERE l.fd_any) AS n_events
FROM   mimiciv.unit_of_analysis_v2 u
LEFT JOIN mimiciv.fetal_death_label_v2 l ON l.hadm_id = u.hadm_id
GROUP  BY 2 ORDER BY 2;

-- Q-T17d. Intervalo con una admisión ANTERIOR del mismo paciente que ya tiene un evento
--         (reproduce la Q-C3 de la auditoría: 17 admisiones y 5 eventos por debajo de 90 días)
WITH prior AS (
    SELECT u.hadm_id, MIN(u.admittime::date - e.admittime::date) AS days_since_prior_event
    FROM   mimiciv.unit_of_analysis_v2 u
    JOIN   mimiciv.unit_of_analysis_v2 e   ON e.subject_id = u.subject_id AND e.admittime < u.admittime
    JOIN   mimiciv.fetal_death_label_v2 le ON le.hadm_id = e.hadm_id AND le.fd_any
    GROUP  BY u.hadm_id
)
SELECT 'Q-T17d gap to an earlier event admission' AS q,
       CASE WHEN p.days_since_prior_event IS NULL THEN '0 no earlier event admission'
            WHEN p.days_since_prior_event <  90   THEN '1 under 90 days'
            WHEN p.days_since_prior_event < 180   THEN '2 90-179 days'
            WHEN p.days_since_prior_event < 365   THEN '3 180-364 days'
            ELSE                                       '4 365 days or more' END AS gap_to_earlier_event,
       COUNT(*)                          AS n_admissions,
       COUNT(*) FILTER (WHERE l.fd_any)  AS n_events
FROM   mimiciv.unit_of_analysis_v2 u
LEFT JOIN prior p ON p.hadm_id = u.hadm_id
LEFT JOIN mimiciv.fetal_death_label_v2 l ON l.hadm_id = u.hadm_id
GROUP  BY 2 ORDER BY 2;

-- Q-T17e. Consistencia con la tabla de etiqueta (T16): mismas unidades, misma marca de D8, misma era y mismo grupo de ancla
--         (esperado: todos los desajustes = 0)
SELECT 'Q-T17e consistency with the label table' AS q,
       COUNT(*) FILTER (WHERE l.hadm_id IS NULL)                              AS n_unit_only,
       (SELECT COUNT(*) FROM mimiciv.fetal_death_label_v2 x
         WHERE NOT EXISTS (SELECT 1 FROM mimiciv.unit_of_analysis_v2 y WHERE y.hadm_id = x.hadm_id)) AS n_label_only,
       COUNT(*) FILTER (WHERE u.ends_before_6h IS DISTINCT FROM l.ends_before_6h) AS n_mismatch_d8_flag,
       COUNT(*) FILTER (WHERE u.icd_era IS DISTINCT FROM l.icd_era)           AS n_mismatch_icd_era,
       COUNT(*) FILTER (WHERE u.anchor_year_group IS DISTINCT FROM l.anchor_year_group) AS n_mismatch_anchor,
       COUNT(*) FILTER (WHERE u.is_delivery_v2 IS DISTINCT FROM l.is_delivery_v2) AS n_mismatch_delivery,
       COUNT(*) FILTER (WHERE ABS(u.los_hours - l.los_hours) > 0.01)          AS n_mismatch_los_hours
FROM   mimiciv.unit_of_analysis_v2 u
LEFT JOIN mimiciv.fetal_death_label_v2 l ON l.hadm_id = u.hadm_id;

-- Q-T17f. Admisiones traslapadas o empatadas del mismo paciente (una admisión que empieza antes de que termine
--         la previa, o en el mismo minuto): afectan el orden y la cadena, por eso se reportan
WITH o AS (
    SELECT u.hadm_id, u.admittime,
           LAG(u.dischtime) OVER (PARTITION BY u.subject_id ORDER BY u.admittime, u.hadm_id) AS prev_dischtime,
           LAG(u.admittime) OVER (PARTITION BY u.subject_id ORDER BY u.admittime, u.hadm_id) AS prev_admittime
    FROM   mimiciv.unit_of_analysis_v2 u
)
SELECT 'Q-T17f overlaps and ties' AS q,
       COUNT(*) FILTER (WHERE prev_admittime IS NOT NULL)                          AS n_with_previous,
       COUNT(*) FILTER (WHERE admittime < prev_dischtime)                          AS n_starts_before_previous_ends,
       COUNT(*) FILTER (WHERE admittime = prev_admittime)                          AS n_same_admittime_as_previous
FROM   o;

-- Q-T17g. Admisiones por paciente y estancia por marca de parto: ¿el punto de predicción (ingreso + 6 h)
--         cae dentro de la admisión? (la marca de D8 para todo el universo, no solo para la población de D3)
SELECT 'Q-T17g prediction point inside the admission' AS q, is_delivery_v2,
       COUNT(*)                                                   AS n_admissions,
       COUNT(*) FILTER (WHERE ends_before_6h)                     AS n_end_before_6h,
       ROUND(AVG(los_hours)::numeric, 1)                          AS mean_los_hours,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_hours))::numeric, 1) AS median_los_hours,
       ROUND(AVG(n_adm_patient)::numeric, 2)                      AS mean_adm_per_patient
FROM   mimiciv.unit_of_analysis_v2
GROUP  BY ROLLUP (is_delivery_v2)
ORDER  BY is_delivery_v2 NULLS LAST;
