# Auditoría de conteos — modelos de muerte fetal, MIMIC-IV

Documento vivo. Primera versión escrita el 28/10/2026, después de ejecutar los grupos A–E y de verificar el catálogo de códigos. Reporta qué midió la auditoría, qué resolvió cada resultado y qué sigue abierto. El plan está en [`analysis_plan_es.md`](analysis_plan_es.md) (la sección 4 lista cada conteo), las cifras por conteo están en la hoja *Conteos* del libro de seguimiento `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (archivo local, sin versionar) y la versión en inglés de este documento es [`count_audit.md`](count_audit.md).

**Estado.** Grupos A–E ejecutados (22 de 29 conteos). Pendientes: Q-C5 (cuaderno, tarea T13), el grupo F (predictores, tareas T22–T25) y las verificaciones de la tabla de etiqueta por admisión (Q-T16a a Q-T16g, script escrito, aún sin ejecutar). Todas las cifras de abajo son conteos agregados; no se produce ni se publica ninguna salida a nivel de fila con `subject_id` o `hadm_id`.

## 1. Propósito y principio

La auditoría mide, antes de construir cualquier modelo, los números que deciden el diseño: qué admisiones forman la población, cuál es la unidad de análisis, cómo se define el desenlace, cuándo se predice y cuántos eventos quedan. Sigue el proyecto materno: **sin solapamiento y sin selección por desenlace**. Cada regla de la cohorte se mide primero como columna y solo después se aplica, de modo que cada elección se toma con números y se reporta junto con su análisis de sensibilidad.

El desenlace es un **sustituto**: un código diagnóstico de muerte fetal en la admisión de la madre. MIMIC-IV no tiene revisión de historias clínicas ni vínculo madre–recién nacido, así que no captura las muertes neonatales tempranas y todo documento dice *muerte fetal*, no *muerte perinatal*.

## 2. Datos y scripts

| Elemento | Detalle |
|---|---|
| Base de datos | MIMIC-IV, PostgreSQL local, esquema `mimiciv` |
| Universo | `cohort_obstetric_v2` del proyecto materno revisado (25,736 admisiones, 15,084 pacientes); tablas acompañantes `hadm_delivery_v2`, `obstetric_dx_v2`, `predictors_24h_v2` |
| Etiqueta usada por los conteos | Provisional: 13 patrones de código heredados de los scripts anteriores (estricto y parcial). La reemplaza el catálogo verificado (T15), que da los mismos eventos |
| Grupos A–D | `sql/02_audit_counts/audit_counts.sql` (tarea T08), ejecutado el 28/10/2026 |
| Grupo E | `sql/02_audit_counts/audit_counts_timing.sql` (tarea T20), ejecutado el 28/10/2026 |
| Códigos verificados | `sql/01_labels/01_fetal_death_codes_official.sql` (tarea T15), ejecutado el 28/10/2026 |
| Tabla de etiqueta por admisión | `sql/01_labels/02_fetal_death_label_by_admission.sql` (tarea T16), escrito, aún sin ejecutar |

Cada script tiene una versión `_es` con código idéntico (solo cambian los comentarios), comprobada con `scripts/check_sql_pair.py`.

**Definición del evento.** *Estricto*: la admisión tiene un código de muerte fetal de todo el embarazo en una etapa obstétrica (CIE-10-CM O36.4, Z37.1, Z37.4, Z37.7; CIE-9-CM 656.4, V27.1, V27.4, V27.7). *Parcial*: uno o más fetos murieron mientras otros nacieron vivos o el embarazo continuó (Z37.3, Z37.6, O31.2; V27.3, V27.6). Se excluyen la muerte fetal temprana (O02.1, 632) y los códigos del registro del recién nacido (P95, 768.0, 768.1). La etiqueta **no tiene momento del evento**: es un código de egreso.

## 3. Resultados

### 3.1 Grupo A — base

La etiqueta provisional reproduce exactamente el conjunto de datos anterior (154 eventos, 154 en ambos, 0 admisiones discordantes) y los conteos base coinciden con la auditoría materna.

| Conteo | Resultado |
|---|---|
| Q-A1 base | 25,736 admisiones; 15,084 pacientes; 19,425 hospitalizaciones de parto (13,729 pacientes con parto); 19,383 elegibles a 24 h |
| Q-A2 reconciliación | Las 25,736 admisiones están en la tabla heredada y en la revisada; 154 eventos en cada una; 0 discordantes |
| Q-A3 admisiones por paciente | 1: 8,291 · 2: 4,418 · 3: 1,558 · 4: 491 · 5 o más: 326 pacientes; 6,793 de 15,084 (45.0 %) tienen más de una admisión; máximo 27 |

### 3.2 Grupo B — eventos y definición

**Eventos por nivel y versión de CIE (Q-B1).** 154 admisiones en 148 pacientes: 136 estrictos y 18 solo parciales. CIE-10: 86 (72 estrictos, 14 parciales); CIE-9: 68 (64, 4).

**Eventos por alcance (Q-B2).** Todos los eventos tienen un código obstétrico estructurado (por construcción).

| Alcance | Eventos | Estrictos | Eventos por 1,000 |
|---|---|---|---|
| Cualquier admisión obstétrica | 154 | 136 | 5.98 (por 1,000 admisiones) |
| Marca de parto v2 | 127 | 114 | 6.54 (por 1,000 partos) |
| Sin parto | 27 | 22 | — |

**Concordancia con la marca de código de mortinato (Q-B3, Q-B3b).** Los 109 partos con código de mortinato (Z37.1/.4/.7, V27.1/.4/.7) son todos eventos estrictos. De los 136 estrictos: 109 tienen código de mortinato y marca de parto; 15 tienen código de mortinato pero no marca de parto; 12 no tienen código de mortinato (vienen de O36.4 o 656.4), 5 de ellos dentro de la marca de parto. Las 15 admisiones con código de mortinato y sin marca de parto tienen también un código de aborto, ectópico o molar (la marca de parto las excluye por esa razón). Eventos solo parciales: 18 (13 en un parto).

**Edad gestacional (Q-B4, Q-B4b).** Las semanas de gestación (códigos Z3A) existen solo en CIE-10.

| Grupo | Menos de 22 semanas | 22–27 | 28 o más | Sin código Z3A |
|---|---|---|---|---|
| Estrictos, CIE-10 (72) | 13 | 19 | 37 | 3 |
| Solo parciales, CIE-10 (14) | 3 | 0 | 11 | 0 |

Los eventos CIE-9 (68) no tienen semanas. De 69 estrictos con semanas, 13 (19 %) tienen menos de 22 semanas, y 7 de esos 13 están dentro de la marca de parto: la marca no elimina las pérdidas previables. Bandas más finas para los 83 eventos CIE-10 con semanas: menos de 20 semanas 10 (7 fuera de un parto con código de aborto, 3 en un parto); 20–21 semanas 6 (5 en un parto); 22–27 semanas 19 (17); 28–36 semanas 25 (21); 37 o más 23 (todos en un parto).

**Posición del código (Q-B5).** Posición 1–4 en la lista de diagnósticos: 118 eventos; 5–10: 30; más allá de 10: 6. Solo 1 evento no tiene otro código obstétrico.

**Fuera del universo (Q-B6).** Vacío: ningún código estricto queda fuera del universo obstétrico.

**Otros desenlaces (Q-B7).** Morbilidad materna grave (definición revisada) en 15 de 136 eventos estrictos y 0 de 18 parciales; ninguna muerte materna en la misma admisión.

**Códigos de aborto, ectópico o molar (Q-B8).** 20 eventos tienen uno (19 estrictos), ninguno dentro de la marca de parto; 134 no lo tienen (127 en un parto, 7 fuera).

### 3.3 Grupo C — solapamiento de pacientes

**Eventos por paciente (Q-C1).** 143 pacientes con una admisión con evento, 4 con dos, 1 con tres (148 pacientes, 154 admisiones con evento).

**Intervalo con la admisión previa de la misma paciente (Q-C2).**

| Intervalo | Admisiones | Eventos |
|---|---|---|
| Primera admisión | 15,084 | 93 |
| Menos de 90 días | 3,649 | 21 |
| 90–179 días | 595 | 1 |
| 180–364 días | 415 | 2 |
| 365 días o más | 5,993 | 37 |

**Eventos tras una admisión con evento previa (Q-C3).** Menos de 90 días: 17 admisiones (5 eventos, 12 no eventos); 90–179 días: ninguna; 180–364 días: 15 (0 eventos); 365 días o más: 78 (1 evento). Las 17 son las mismas admisiones que los scripts anteriores describían como "menos de 90 días" (SQL) y "dentro de 180 días" (cuaderno): no hay ninguna admisión entre 90 y 179 días, así que la contradicción queda resuelta. Eventos en una primera admisión: 93 (86 estrictos); en una admisión posterior: 61 (50 estrictos), es decir, el 40 % de los eventos.

**Eventos bajo cada unidad candidata (Q-C4).**

| Unidad | Unidades | Eventos | Estrictos | Pacientes con evento |
|---|---|---|---|---|
| Admisión | 25,736 | 154 | 136 | 148 |
| Hospitalización de parto | 19,425 | 127 | 114 | 126 |
| Primera admisión por paciente | 15,084 | 93 | 86 | 93 |
| Cadena de embarazo, 30 días | 23,257 | 150 | 135 | 148 |
| Cadena de embarazo, 90 días | 22,080 | 149 | 134 | 148 |
| Cadena de embarazo, 180 días | 21,485 | 149 | 134 | 148 |

**Pendiente.** Q-C5 (pacientes y pacientes con evento en ambos lados de una partición por admisión, hold-out 80/20 y 5 pliegues), que se calculará en el cuaderno `01_patient_overlap` (tarea T13). En el proyecto materno, el 58–59 % de los pacientes de prueba también estaban en el entrenamiento.

### 3.4 Grupo D — era y codificación

CIE-9 cubre cerca de 2008–2014 (mediana 2011) y CIE-10 cerca de 2014–2021 (mediana 2017): **la versión de codificación y el período calendario están casi confundidos**.

| Tasa de eventos en partos (Q-D1) | Eventos / partos | Por 1,000 |
|---|---|---|
| CIE-10 | 70 / 8,883 | 7.88 |
| CIE-9 | 57 / 10,542 | 5.41 |
| Total | 127 / 19,425 | 6.54 (IC 95 % 5.5–7.8) |

Por grupo de año ancla: 2008–10 5.23 · 2011–13 6.69 · 2014–16 6.43 · 2017–19 8.51 · 2020–22 12.85 (12 / 934). La tendencia es significativa (p = 0.007, calculada por el asistente, por reproducir en el código de análisis).

**Semanas de gestación (Q-D2).** Disponibles en 83 de 86 eventos CIE-10 y 8,844 de 8,883 partos CIE-10; en ningún evento ni parto CIE-9. En total 8,844 de 19,425 partos (45.5 %) tienen semanas, todos de la época CIE-10.

**Plausibilidad (Q-D3).** Por 1,000 hospitalizaciones de parto: A, solo código de mortinato 109 / 19,425 = 5.61; B, estricto 114 = 5.87; C, estricto o parcial 127 = 6.54; D, solo CIE-10, estricto y 28 semanas o más, 36 / 8,883 = 4.05. Referencia nacional (NCHS, por 1,000 nacidos vivos más muertes fetales): 20 semanas o más 5.48 (2022) y 5.44 (2024); 28 semanas o más 2.71 (2022) y 2.57 (2024). Las tasas a cualquier edad gestacional están cerca de la cifra nacional; la de 28 semanas la supera (4.05 frente a 2.57), lo que puede reflejar una población de referencia (no se probó). Los denominadores difieren (partos hospitalarios, no todos los nacimientos), así que la comparación es una verificación de plausibilidad, no una validación.

### 3.5 Grupo E — elegibilidad y tiempo

La población de la decisión D3 (marca de parto o código de mortinato) tiene 19,440 admisiones, 142 eventos y 129 eventos estrictos (control Q-E0).

**Duración de la estancia (Q-E1), horas: mediana [p25–p75]; p05–p95.**

| Grupo | n | Mediana [p25–p75] | p05–p95 |
|---|---|---|---|
| Eventos estrictos | 129 | 54.4 [36.7–87.8] | 18.6–226.1 |
| Solo parciales | 13 | 77.1 [61.3–98.9] | — |
| No eventos | 19,298 | 71.0 [58.1–100.5] | 44.7–159.4 |

Estancia de menos de 24 h: 17 de 129 eventos estrictos (13.2 %) frente a 28 de 19,298 no eventos (0.15 %); menos de 12 h: 5 frente a 7. Ninguna estancia ausente o no positiva.

**Elegibilidad y eventos conservados (Q-E2, Q-E2b).** A 24 h, 19,395 admisiones de la población son elegibles (1 murió y 44 salieron antes de las 24 h); se pierden 17 de 129 eventos estrictos (13.2 %) y 0 de 13 parciales. Solo con la marca de parto, 19,383 son elegibles (como en el proyecto materno) y se pierden 14 de 114 estrictos (12.3 %).

| Horas desde el ingreso | Eventos estrictos aún hospitalizados (de 129) | Admisiones restantes |
|---|---|---|
| 0 | 129 | 19,440 |
| 6 | 129 | 19,437 |
| 12 | 124 (96.1 %) | 19,428 |
| 24 | 112 (86.8 %) | 19,395 |
| 36 | 97 (75.2 %) | 19,144 |
| 48 | 75 (58.1 %) | 17,858 |

**Primer laboratorio, UCI, urgencias (Q-E3).** Existe registro de urgencias en 20 de 129 eventos estrictos (15.5 %) y 427 de 19,298 no eventos (2.2 %), con una mediana de 3.4 y 2.6 horas antes del ingreso, ninguno a más de 24 horas. El primer laboratorio se toma alrededor del ingreso: mediana 0.0 h en eventos estrictos (p05 −7.5, p95 3.3) y 0.1 h en no eventos (−7.8, 5.0); cerca de la mitad se toma antes de la hora de ingreso (52 de 104 eventos estrictos con laboratorio, 7,544 de 15,880 no eventos); 25 de 129 eventos estrictos y 3,418 de 19,298 no eventos no tienen laboratorio. Estancia en UCI: 8 de 129 eventos estrictos (6.2 %; 5 en las primeras 24 h; mediana 11.1 h) frente a 197 de 19,298 no eventos (1.0 %; 110 en 24 h; mediana 20.6 h).

**Fechas de procedimientos (Q-E4).** Los códigos de procedimiento tienen fecha; los de diagnóstico, no. Fecha del primer procedimiento de parto respecto de la fecha de ingreso:

| Grupo | Sin procedimiento | Antes | Día 0 | Día 1 | Día 2 o después |
|---|---|---|---|---|---|
| Estrictos (129) | 21 | 0 | 36 | 51 | 21 |
| Solo parciales (13) | 1 | 0 | 5 | 5 | 2 |
| No eventos (19,298) | 4,293 | 21 | 8,551 | 4,733 | 1,700 |

Entre las admisiones con procedimiento, el día 0, el día 1 y el día 2 o después son 33 %, 47 % y 19 % en eventos estrictos frente a 57 %, 32 % y 11 % en no eventos: los eventos llegan al procedimiento de parto más tarde que los no eventos. Inducción (lista de códigos provisional): 43 eventos estrictos con procedimiento (14 el día 0, 29 el día 1 o después), 4 parciales y 6,770 no eventos (4,602 el día 0, 2,113 después).

### 3.6 Verificación de códigos (T15)

La tabla verificada reproduce exactamente la etiqueta provisional: 154 eventos, 136 estrictos, 18 solo parciales; 142 y 129 en la población de D3. Toda admisión con alguno de estos códigos en la base completa está dentro del universo obstétrico. Ninguna admisión tiene P95, 768.0, 768.1 (códigos del registro del recién nacido), Z37.6, Z37.7 ni V27.6. Siete eventos estrictos quedan fuera de la población de D3 (6 con CIE-9 656.4, 1 con CIE-10 O36.4); los seis igualan el número de códigos 656.43 (anteparto), una coincidencia que la tabla de etiqueta comprueba en Q-T16b. Los códigos de pérdida temprana (O02.1, 632) aparecen en 113 admisiones: 102 sin código de evento (correctamente excluidas) y 11 con uno, que la tabla de etiqueta marca como `has_early_loss_code`.

### 3.7 Pendiente y aún sin ejecutar

| Elemento | Qué mostrará | Dónde |
|---|---|---|
| Q-T16a–g | Integridad de la tabla de etiqueta, los 7 eventos estrictos fuera de D3, familias de código y posición, eventos con códigos de pérdida temprana, tamaños de etiqueta, admisiones de menos de 6 h | `02_fetal_death_label_by_admission.sql` |
| Q-C5 | Fuga de pacientes de una partición por admisión | cuaderno `01_patient_overlap` (T13) |
| Q-F1–F6 | Disponibilidad de predictores, regla de cobertura, visibilidad de antecedentes, registros ambulatorios, unidades, códigos relacionados con el desenlace entre los primeros diagnósticos | grupo F (T22–T25) |

## 4. Qué resolvió la auditoría

| Decisión | Elección (28/10/2026) | Evidencia |
|---|---|---|
| D1 base de datos | Tablas revisadas del proyecto materno | Los conteos base coinciden con la auditoría materna; la etiqueta reproduce el conjunto de datos anterior (Q-A1, Q-A2) |
| D3 población | Marca de parto v2 **o** código de mortinato (19,440 admisiones; 142 eventos, 129 estrictos) | La marca sola deja fuera 15 admisiones con código de mortinato, todas con código de aborto (Q-B3b); ningún código estricto fuera del universo (Q-B6) |
| D4 unidad | Un registro por hospitalización de parto, validación agrupada por paciente; cadena de embarazo de 90 días como sensibilidad | Las cadenas cambian el número de eventos en 5 como máximo (Q-C4); solo la primera admisión perdería el 40 % de los eventos (Q-C3); 5 pacientes tienen más de una admisión con evento (Q-C1) |
| D5 desenlace | Código estricto a cualquier edad gestacional como principal; sensibilidades: estricto + parcial, 22 semanas o más, 28 semanas o más (solo CIE-10), excluir eventos con código de pérdida temprana | Las semanas existen solo en CIE-10 y el 19 % de los estrictos con semanas tiene menos de 22 (Q-B4, Q-D2); las definiciones de 20/22/28 semanas difieren según la fuente |
| D6 punto de predicción | Ingreso + 6 h (12 h, 24 h y retrospectivo como sensibilidades) | A 24 h se pierde el 13.2 % de los eventos estrictos frente al 0.15 % de los no eventos; a 6 h se conservan los 129 (Q-E1, Q-E2) |
| D7 tiempo cero y ventana | Hora de ingreso; ventana desde 24 h antes del ingreso hasta el punto de predicción | Primer laboratorio alrededor del ingreso y la mitad antes de él; registro de urgencias una mediana de 3 h antes (Q-E3) |
| D8 admisiones cortas | Excluir las 3 admisiones que terminan antes de 6 h (0 eventos) y reportarlas aparte | Q-E2b: 19,440 − 19,437 admisiones a las 6 h |

Decisiones abiertas: D2 (nombre del desenlace) y D9–D14 (bloques de predictores, regla de cobertura, modelos, tamaño de muestra, reporte).

## 5. Interpretación y límites

- **Modelo de riesgo temprano o de detección, no pronóstico de un evento posterior.** La etiqueta es un código de egreso sin momento y la muerte fetal suele estar ya presente a la llegada; el modelo estima el riesgo de un código de muerte fetal con la información disponible hasta el punto de predicción.
- **Confusión de época.** La versión de CIE, la disponibilidad de la edad gestacional y el período calendario se mueven juntos; el aumento de 5.2 a 12.9 por 1,000 puede reflejar la práctica de codificación además de la composición de casos. Ningún análisis de sensibilidad por versión puede separarlos.
- **Pérdidas previables.** La marca de parto no las elimina (7 de 13 eventos estrictos de menos de 22 semanas están dentro de ella); solo las admisiones CIE-10 permiten un corte por semanas, y 3 eventos estrictos CIE-10 no tienen semanas.
- **Denominadores.** Las tasas usan partos hospitalarios de un centro terciario; la comparación con cifras nacionales es solo una verificación de plausibilidad.
- **Elementos provisionales.** La lista de procedimientos de inducción (CIE-9 73.0, 73.1, 73.4; CIE-10-PCS 10907ZC) es provisional. No se descargaron los archivos de códigos de CDC y CMS; el catálogo se apoya en páginas de AAPC, Kodex, findacode e icd9data y en el navegador CIE-10 2019 de la OMS, y debe cotejarse antes del envío. No se verificaron uno por uno el séptimo carácter de O31.2 ni los códigos Z3A; la OMS no tiene CIE-9.
- **Prueba de tendencia.** El p = 0.007 lo calculó el asistente y debe reproducirse en el código de análisis antes de citarlo.
- **Celdas pequeñas.** Varias celdas son pequeñas (eventos parciales, 5 pacientes con varias admisiones con evento); reportarlas con cuidado y nunca a nivel de fila.

## 6. Fuentes

- NCHS, National Vital Statistics Reports, vol. 73, n.º 9 (datos de 2022) y vol. 75, n.º 6 (datos de 2024): tasas de mortalidad fetal de EE. UU. a 20 semanas o más y a 28 semanas o más. Completar la cita y la URL desde la hoja *Conteos* (Q-D3).
- OMS CIE-10 (navegador 2019): O36.4, Z37, P95 (capturas aportadas por el autor el 28/10/2026).
- CIE-10-CM (AAPC, Kodex, findacode.com) y CIE-9-CM (icd9data.com): títulos de códigos y términos de inclusión, como se listan en el encabezado de `sql/01_labels/01_fetal_death_codes_official.sql`.
- Umbrales de mortinato: OMS y CIE-11, 22 semanas; NCHS, 20 semanas.
- Tablas de MIMIC-IV y cohorte materna revisada: `MaternalMortality_MIMIC-IV` (manuscrito healthcare-4661619).

*Confidencial: uso interno del proyecto de investigación; solo resultados agregados.*
