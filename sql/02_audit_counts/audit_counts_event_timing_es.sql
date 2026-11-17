-- ============================================================================
-- AUDITORÍA DE CONTEOS, grupo G (momento del evento de muerte fetal) -- modelos de muerte fetal (plan v2, tarea T45)
-- Framework: etapa E3 (definición del desenlace: momento del evento) y puerta P1; prepara los criterios C1 y C2 de la puerta P4
-- ============================================================================
-- Propósito: la etiqueta de muerte fetal es un código de egreso y NO tiene momento del evento. El criterio C1
-- (eventos ya presentes en el punto de predicción) necesita una población landmark sin las
-- muertes ya presentes en T, y el criterio C2 (desenlace con tiempo) necesita eventos fechados después de T.
-- Este script CUENTA los proxies que podrían ubicar cada evento en el tiempo, en eventos y
-- no eventos, para que la regla temporal se fije con números y antes de cualquier modelo
-- (ficha del desenlace, docs/outcome_card_fetal_death_es.md, sección 5).
--
-- Proxies contados (ninguno se usa como predictor):
--   P1 código de muerte intrauterina (CIE-10 O36.4, CIE-9 656.4): atención por una muerte fetal ya conocida
--      durante la estancia, es decir, muerte antes del trabajo de parto (anteparto); sin hora.
--   P2 código de muerte fetal como diagnóstico principal (seq_num = 1): la muerte fue el motivo de la
--      admisión; sin hora (se asigna después del egreso).
--   P3 estudio de laboratorio de una muerte fetal CON HORA: hemoglobina fetal / Kleihauer-Betke y
--      ítems afines buscados por nombre en d_labitems (Q-G2 los lista; revisar cada ítem antes de usarlo).
--   P4 medicamento CON HORA: mifepristona (se usa en muerte fetal o interrupción, rara vez para
--      inducir un embarazo con feto vivo) y misoprostol (también se usa para inducción y hemorragia,
--      así que NO es específico) en prescriptions.
--   P5 procedimiento de parto fechado el día del ingreso (solo fecha, sin hora).
-- Punto de predicción T = hora de ingreso + 6 h (decisión D6). Población de la decisión D3 sin
-- las admisiones que terminan antes de T (decisión D8).
--
-- SOLO LECTURA: solo crea tablas temporales y ejecuta SELECT. Los resultados son conteos agregados;
-- NO publicar filas con subject_id o hadm_id, y reemplazar los conteos menores de 5 por "<5" en todo
-- archivo publicado (decisión D13).
--
-- Requisitos: mimiciv.fetal_death_label_v2 (tarea T16, sql/01_labels/02_...), tablas hosp de MIMIC-IV
-- admissions, labevents, d_labitems, prescriptions, procedures_icd.
-- Q-G3 lee labevents y Q-G4 lee prescriptions solo para las admisiones de la
-- población (cada una puede tardar unos minutos).
--
-- Ejecutar el script completo en UNA conexión (DBeaver: Alt+X): las tablas temporales deben sobrevivir
-- entre sentencias. Cada resultado empieza con una columna de etiqueta q.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0. Tablas de trabajo
-- ----------------------------------------------------------------------------
-- Población de D3 aún hospitalizada en T (D8), con la etiqueta y los proxies sin hora P1 y P2
DROP TABLE IF EXISTS tmp_ft_base;
CREATE TEMP TABLE tmp_ft_base AS
SELECT l.subject_id, l.hadm_id, l.admittime, l.dischtime,
       l.admittime + INTERVAL '6 hours'                                   AS t_pred,
       a.edregtime,
       l.icd_era,
       l.fd_strict,
       l.fd_any,
       CASE WHEN l.fd_strict THEN '1 strict event'
            WHEN l.fd_any    THEN '2 partial-only event'
            ELSE                  '3 non-event' END                       AS ev_group,
       l.has_intrauterine_death_code                                      AS p1_intrauterine_code,
       (l.fd_strict AND l.min_strict_seq = 1)                             AS p2_principal_dx,
       l.has_stillbirth_outcome_code,
       l.has_early_loss_code,
       l.gest_band
FROM   mimiciv.fetal_death_label_v2 l
JOIN   mimiciv.admissions a ON a.hadm_id = l.hadm_id
WHERE  l.in_pop_d3
  AND  NOT l.ends_before_6h;

-- Ítems de laboratorio candidatos del estudio de una muerte fetal, buscados por nombre (P3)
DROP TABLE IF EXISTS tmp_ft_labitems;
CREATE TEMP TABLE tmp_ft_labitems AS
SELECT itemid, label, fluid, category
FROM   mimiciv.d_labitems
WHERE  label ILIKE '%fetal hemoglobin%'
   OR  label ILIKE '%fetal hgb%'
   OR  label ILIKE '%kleihauer%'
   OR  label ILIKE '%fetal cell%'
   OR  label ILIKE '%fetal screen%'
   OR  label ILIKE '%fetal-maternal%'
   OR  label ILIKE '%fetomaternal%';

-- Primer valor de cada ítem candidato por admisión (ventana: 24 h antes del ingreso hasta el egreso)
DROP TABLE IF EXISTS tmp_ft_lab;
CREATE TEMP TABLE tmp_ft_lab AS
SELECT b.hadm_id, li.itemid, li.label, MIN(le.charttime) AS first_time
FROM   tmp_ft_base b
JOIN   mimiciv.labevents le
       ON  le.subject_id = b.subject_id
       AND le.charttime >= b.admittime - INTERVAL '24 hours'
       AND le.charttime <= b.dischtime
       AND (le.hadm_id = b.hadm_id OR le.hadm_id IS NULL)
JOIN   tmp_ft_labitems li ON li.itemid = le.itemid
GROUP  BY b.hadm_id, li.itemid, li.label;

-- Primer inicio de mifepristona y de misoprostol por admisión (P4)
DROP TABLE IF EXISTS tmp_ft_med;
CREATE TEMP TABLE tmp_ft_med AS
SELECT p.hadm_id,
       MIN(p.starttime) FILTER (WHERE p.drug ILIKE '%mifepris%' OR p.drug ILIKE '%mifeprex%') AS first_mifepristone,
       MIN(p.starttime) FILTER (WHERE p.drug ILIKE '%misopros%' OR p.drug ILIKE '%cytotec%')  AS first_misoprostol
FROM   mimiciv.prescriptions p
WHERE  p.hadm_id IN (SELECT hadm_id FROM tmp_ft_base)
GROUP  BY p.hadm_id;

-- Fecha del primer procedimiento de parto (P5; misma lista de parto que hadm_delivery_v2 y audit_counts_timing.sql)
DROP TABLE IF EXISTS tmp_ft_proc;
CREATE TEMP TABLE tmp_ft_proc AS
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
       ) AS first_delivery_proc_date
FROM   mimiciv.procedures_icd p
WHERE  p.hadm_id IN (SELECT hadm_id FROM tmp_ft_base)
GROUP  BY p.hadm_id;

-- Una fila por admisión con cada proxy como columna
DROP TABLE IF EXISTS tmp_ft_proxy;
CREATE TEMP TABLE tmp_ft_proxy AS
SELECT b.*,
       lb.first_lab_time,
       (lb.first_lab_time IS NOT NULL AND lb.first_lab_time <= b.t_pred)     AS p3_lab_by_t,
       (lb.first_lab_time IS NOT NULL AND lb.first_lab_time >  b.t_pred)     AS p3_lab_after_t,
       m.first_mifepristone,
       m.first_misoprostol,
       (m.first_mifepristone IS NOT NULL AND m.first_mifepristone <= b.t_pred) AS p4_mifepristone_by_t,
       (m.first_misoprostol  IS NOT NULL AND m.first_misoprostol  <= b.t_pred) AS p4_misoprostol_by_t,
       (pr.first_delivery_proc_date IS NOT NULL
        AND pr.first_delivery_proc_date - b.admittime::date = 0)             AS p5_delivery_day0
FROM   tmp_ft_base b
LEFT JOIN (SELECT hadm_id, MIN(first_time) AS first_lab_time FROM tmp_ft_lab GROUP BY hadm_id) lb
       ON lb.hadm_id = b.hadm_id
LEFT JOIN tmp_ft_med  m  ON m.hadm_id  = b.hadm_id
LEFT JOIN tmp_ft_proc pr ON pr.hadm_id = b.hadm_id;

-- ============================================================================
-- GRUPO G -- momento del evento de muerte fetal
-- ============================================================================

-- Q-G0. Verificación de la población (esperado: 19.437 admisiones; 129 eventos estrictos; 142 eventos con códigos parciales)
SELECT 'Q-G0 population check' AS q,
       COUNT(*)                          AS n_admissions,
       COUNT(*) FILTER (WHERE fd_strict) AS n_strict,
       COUNT(*) FILTER (WHERE fd_any)    AS n_events_any
FROM   tmp_ft_base;

-- Q-G1. Proxies sin hora P1 y P2 en los eventos estrictos, por familia de código y era CIE
SELECT 'Q-G1 untimed proxies (strict events)' AS q, icd_era, code_family,
       COUNT(*)                                        AS n_events,
       COUNT(*) FILTER (WHERE p2_principal_dx)         AS n_principal_dx,
       COUNT(*) FILTER (WHERE edregtime IS NOT NULL)   AS n_with_ed_registration
FROM  (SELECT b.*,
              CASE WHEN p1_intrauterine_code AND has_stillbirth_outcome_code THEN '3 both families'
                   WHEN p1_intrauterine_code                                  THEN '1 intrauterine death code only'
                   ELSE                                                            '2 stillbirth outcome code only' END AS code_family
       FROM   tmp_ft_base b
       WHERE  b.fd_strict) s
GROUP  BY ROLLUP (icd_era, code_family)
ORDER  BY icd_era NULLS LAST, code_family NULLS LAST;

-- Q-G2. Ítems de laboratorio candidatos del estudio (P3): cuántas admisiones tienen cada ítem, por grupo de evento.
--       Revisar la lista: un ítem de tamizaje Rh negativo (fetal cell screen, roseta) se pide después de
--       muchos partos normales y NO es específico de una muerte fetal.
SELECT 'Q-G2 candidate work-up laboratory items' AS q, li.itemid, li.label, li.fluid, li.category,
       COUNT(DISTINCT lb.hadm_id) FILTER (WHERE b.fd_strict)            AS n_strict_events_with_item,
       COUNT(DISTINCT lb.hadm_id) FILTER (WHERE b.ev_group = '3 non-event') AS n_non_events_with_item
FROM   tmp_ft_labitems li
LEFT JOIN tmp_ft_lab  lb ON lb.itemid = li.itemid
LEFT JOIN tmp_ft_base b  ON b.hadm_id = lb.hadm_id
GROUP  BY li.itemid, li.label, li.fluid, li.category
ORDER  BY li.label;

-- Q-G3. Momento del primer valor de laboratorio del estudio respecto de T (horas), por ítem y grupo de evento
SELECT 'Q-G3 first work-up laboratory value relative to T' AS q, lb.itemid, lb.label, b.ev_group,
       COUNT(*)                                                                         AS n_admissions_with_value,
       COUNT(*) FILTER (WHERE lb.first_time <= b.t_pred)                                AS n_by_t,
       COUNT(*) FILTER (WHERE lb.first_time >  b.t_pred
                          AND lb.first_time <= b.admittime + INTERVAL '24 hours')       AS n_t_to_24h,
       COUNT(*) FILTER (WHERE lb.first_time >  b.admittime + INTERVAL '24 hours')       AS n_after_24h,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (lb.first_time - b.admittime)) / 3600.0)::numeric, 1) AS median_hours_from_admission
FROM   tmp_ft_lab lb
JOIN   tmp_ft_base b ON b.hadm_id = lb.hadm_id
GROUP  BY lb.itemid, lb.label, b.ev_group
ORDER  BY lb.label, lb.itemid, b.ev_group;

-- Q-G4. Mifepristona y misoprostol (P4): admisiones con prescripción, y con inicio en T o antes, por grupo de evento
SELECT 'Q-G4 mifepristone and misoprostol' AS q, ev_group,
       COUNT(*)                                                       AS n_admissions,
       COUNT(*) FILTER (WHERE first_mifepristone IS NOT NULL)         AS n_mifepristone,
       COUNT(*) FILTER (WHERE p4_mifepristone_by_t)                   AS n_mifepristone_by_t,
       COUNT(*) FILTER (WHERE first_misoprostol IS NOT NULL)          AS n_misoprostol,
       COUNT(*) FILTER (WHERE p4_misoprostol_by_t)                    AS n_misoprostol_by_t,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (first_mifepristone - admittime)) / 3600.0)::numeric, 1) AS median_hours_to_mifepristone
FROM   tmp_ft_proxy
GROUP  BY ROLLUP (ev_group)
ORDER  BY ev_group NULLS LAST;

-- Q-G5. Frecuencia de cada proxy, eventos frente a no eventos (verificación de especificidad: un proxy
--       frecuente en los no eventos no puede marcar una muerte fetal ya presente)
SELECT 'Q-G5 proxies in events and non-events' AS q, ev_group,
       COUNT(*)                                          AS n_admissions,
       COUNT(*) FILTER (WHERE p1_intrauterine_code)      AS n_p1_intrauterine_code,
       COUNT(*) FILTER (WHERE p2_principal_dx)           AS n_p2_principal_dx,
       COUNT(*) FILTER (WHERE p3_lab_by_t)               AS n_p3_lab_by_t,
       COUNT(*) FILTER (WHERE p3_lab_after_t)            AS n_p3_lab_after_t,
       COUNT(*) FILTER (WHERE p4_mifepristone_by_t)      AS n_p4_mifepristone_by_t,
       COUNT(*) FILTER (WHERE p4_misoprostol_by_t)       AS n_p4_misoprostol_by_t,
       COUNT(*) FILTER (WHERE p5_delivery_day0)          AS n_p5_delivery_day0
FROM   tmp_ft_proxy
GROUP  BY ev_group
ORDER  BY ev_group;

-- Q-G6. Clases temporales candidatas de los eventos estrictos (PROPUESTA, por confirmar con Q-G2 a Q-G5).
--   1 present at T, timed     : un valor de laboratorio del estudio o mifepristona en T o antes
--   2 present at T, by code   : código de muerte intrauterina como diagnóstico principal (sin evidencia con hora)
--   3 antepartum, time unknown: código de muerte intrauterina no principal (sin evidencia con hora)
--   4 indeterminate           : solo código de mortinato como resultado del parto, sin evidencia con hora en T o antes
--   No se propone una clase "documentada después de T": ninguna fuente de estas tablas puede fechar una muerte después de T.
--   La clase 1 usa todos los ítems de Q-G2: retirar los ítems no específicos de tmp_ft_labitems antes de interpretarla.
SELECT 'Q-G6 candidate timing classes (strict events)' AS q, timing_class,
       COUNT(*)                                                AS n_events,
       COUNT(*) FILTER (WHERE icd_era = 'ICD-10 only')         AS n_icd10,
       COUNT(*) FILTER (WHERE has_early_loss_code)             AS n_with_early_loss_code,
       COUNT(*) FILTER (WHERE gest_band IN ('22 to 27', '28 or more')) AS n_22_weeks_or_more,
       COUNT(*) FILTER (WHERE p3_lab_after_t)                  AS n_work_up_only_after_t
FROM  (SELECT p.*,
              CASE WHEN p3_lab_by_t OR p4_mifepristone_by_t           THEN '1 present at T, timed'
                   WHEN p1_intrauterine_code AND p2_principal_dx      THEN '2 present at T, by code'
                   WHEN p1_intrauterine_code                          THEN '3 antepartum, time unknown'
                   ELSE                                                    '4 indeterminate' END AS timing_class
       FROM   tmp_ft_proxy p
       WHERE  p.fd_strict) s
GROUP  BY ROLLUP (timing_class)
ORDER  BY timing_class NULLS LAST;
