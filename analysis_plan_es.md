# Plan de análisis — modelos de muerte fetal, MIMIC-IV (versión 2)

Documento de trabajo, escrito el 28/10/2026 después de migrar el material anterior. Sigue el diseño del proyecto materno revisado (`MaternalMortality_MIMIC-IV_Cureus`): una **auditoría de conteos antes de cualquier modelo**, una cohorte sin solapamiento de pacientes entre entrenamiento y evaluación, un punto de predicción fijo, validación anidada agrupada por paciente y análisis de sensibilidad que incluyen la pregunta de si pueden usarse los diagnósticos de la misma admisión.

Los puntos marcados **[decisión]** están abiertos; se listan en la sección 5 y en la hoja *Decisiones* del Excel de seguimiento `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (archivo local, no versionado). Las cifras marcadas *legacy* vienen de los scripts exploratorios migrados desde `legacy/` y **deben verificarse de nuevo** con la auditoría antes de citarse en cualquier lugar. Versión en inglés: [`analysis_plan.md`](analysis_plan.md). La primera versión de este plan se conserva en `docs/backup_plan_v1/`.

## 1. Propósito y enfoque

- Evaluar si el marco del proyecto materno (auditoría de conteos, validación agrupada por paciente, recalibración, reporte TRIPOD+AI) se traslada a un desenlace nuevo sin fuga de información: **muerte fetal identificada a partir de los códigos ICD de la madre**.
- El desenlace es un **proxy**: no hay revisión de historias ni vínculo madre–recién nacido en MIMIC-IV, así que las muertes neonatales tempranas no se capturan. El desenlace se nombra **muerte perinatal antes del nacimiento** (la parte anteparto de la muerte perinatal: muerte fetal o mortinato), siempre señalada como proxy (**D2**, decidida el 28/10/2026).
- El notebook anterior (`notebooks/01_fetal_death_models.ipynb`) es **exploratorio**: un solo hold-out 80/20, validación cruzada sin ajuste anidado y un conjunto de predictores elegido después de mirar todo el conjunto de datos. Se conserva como referencia y lo reemplazan los notebooks de la sección 6.
- El alcance del trabajo (modelo completo o solo análisis de factibilidad) se decide después de la auditoría y del cálculo de tamaño de muestra (**D12**), como se hizo con la mortalidad materna.

## 2. Punto de partida

**D1 (decidida el 28/10/2026): la cohorte se construye sobre las tablas revisadas del proyecto materno**, no sobre el antiguo `cohort_smm_dataset`. Las tablas revisadas corrigen problemas que heredaron los scripts anteriores: la bandera de parto original solo reconocía códigos ICD-10, de modo que los partos ICD-9 nunca podían marcarse (la bandera revisada añadió 10,584 partos en la auditoría materna; el script anterior de factibilidad, Consulta 9, se escribió para comprobar el mismo problema en los eventos de muerte fetal), y la ventana de predictores no tenía un punto de predicción fijo.

Requisitos previos (construidos por `MaternalMortality_MIMIC-IV/sql/04_labels` y `sql/05_predictors`): `mimiciv.cohort_obstetric_v2` (universo), `mimiciv.hadm_delivery_v2` (bandera de parto con `has_stillbirth_code` y `has_abortive_code`), `mimiciv.label_admission_v2`, `mimiciv.predictors_24h_v2`, `mimiciv.pregnancy_diagnoses_expanded`.

Cifras de referencia de la auditoría materna (por confirmar en Q-A1): 25,736 admisiones obstétricas, 15,084 pacientes, 6,793 pacientes (45.0 %) con más de una admisión, 19,425 hospitalizaciones de parto (109 con código de mortinato), 19,383 hospitalizaciones de parto que seguían hospitalizadas 24 horas después del ingreso.

Equivalencia de las piezas del proyecto materno con este proyecto (los scripts por escribir se nombran en la sección 6; ninguno está escrito todavía):

| Proyecto materno | Este proyecto |
|---|---|
| `04_labels/01_smm_codes_official.sql` (tabla de códigos verificada) | tabla verificada de códigos de muerte fetal con fuentes (reemplaza `fetal_death_code_patterns`) |
| `04_labels/02_delivery_flag.sql`, `03_labels_same_admission.sql` | etiqueta de muerte fetal por admisión sobre `cohort_obstetric_v2`, con estricta/parcial, semanas de gestación y versión de ICD como columnas, nunca como filtros |
| `04_labels/04_cohort_obstetric_flags.sql` (reglas como columnas) | columnas de unidad de análisis y mismo embarazo (admisión, parto, cadena de embarazo, primera admisión) |
| `05_predictors/01_predictors_24h.sql`, `02_dictionary_missingness.sql` | predictores ampliados (antecedentes, hemograma, panel, OMR) en la ventana decidida, más un diccionario de predictores con regla de cobertura |
| `06_audit_counts/*` | `sql/02_audit_counts/` grupos A–F (sección 4) |
| Notebooks 01–07 | notebooks de la sección 6 |

## 3. Fases

| Fase | Contenido | Cierra con |
|---|---|---|
| F0 · Base y decisiones | proyecto, migración, requisitos verificados, plan aprobado | D1–D3 resueltas, commit de línea base |
| F1 · Cohorte y auditoría de conteos | conteos A–D (base, eventos, solapamiento de pacientes, era), notebook 01 | D3, D4, D5 resueltas con números |
| F2 · Desenlace y etiquetas | tabla de códigos verificada, etiqueta y columnas de unidad sobre la cohorte revisada | script de etiquetas + conteos |
| F3 · Predictores y temporalidad | conteos E–F, punto de predicción, ventana, diccionario de predictores | D6–D10 resueltas |
| F4 · Marco de validación | tamaño de muestra, modelos, validación anidada agrupada por paciente, calibración | D11, D12 resueltas |
| F5 · Análisis de sensibilidad | SA1–SA11 (sección 7) | un archivo de salida por análisis |
| F6 · Reporte | salidas agregadas, TRIPOD+AI, tablas suplementarias, manuscrito o capítulo | D13, D14 resueltas |

## 4. Auditoría de conteos (antes de cualquier modelo)

Solo lectura y salida agregada; nunca se publican filas con `subject_id` o `hadm_id`. Cada conteo tiene un identificador (Q-…) que se usa en el Excel de seguimiento (hoja *Conteos*) y nombra la decisión que informa.

**Principio: sin solapamiento y sin selección por el desenlace.** Las reglas de cohorte se miden primero como columnas y se aplican después, de modo que cada elección (unidad, alcance, definición) se haga con números y se reporte con su análisis de sensibilidad.

| Grupo | Conteos | Informa |
|---|---|---|
| **A · Base** | Q-A1 admisiones, pacientes, partos, partos elegibles; Q-A2 reconciliación del conjunto de datos anterior con `cohort_obstetric_v2`; Q-A3 admisiones por paciente | D1, D4 |
| **B · Eventos y definición** | Q-B1 eventos por nivel (estricto, parcial) y versión de ICD; Q-B2 eventos por alcance (parto, código obstétrico estructurado, cualquiera); Q-B3 concordancia con `has_stillbirth_code` y con partos ICD-9; Q-B4 semanas de gestación por códigos Z3A (menos de 22, 22–27, 28 o más, sin código); Q-B5 posición del código en la lista de diagnósticos y eventos donde es el único código obstétrico; Q-B6 códigos de muerte fetal fuera del universo obstétrico; Q-B7 solapamiento con morbilidad materna grave y con muerte materna en la misma admisión; Q-B8 coexistencia con códigos de aborto o ectópico | D3, D5 |
| **C · Solapamiento de pacientes** | Q-C1 eventos por paciente; Q-C2 intervalo entre admisiones consecutivas de la misma paciente, según el estado del evento (menos de 90, 90–179, 180–364, 365 o más días); Q-C3 admisiones con evento que no son la primera de la paciente, e intervalo hasta un evento previo; Q-C4 eventos bajo cada unidad candidata (admisión, parto, cadena de embarazo, primera admisión por paciente); Q-C5 simulación de la partición por admisión: pacientes y pacientes con evento en ambos lados de un hold-out y de una validación cruzada de 5 pliegues | D4, D11 |
| **D · Era y codificación** | Q-D1 eventos y tasa por 1,000 partos según versión de ICD y grupo de año ancla; Q-D2 disponibilidad de semanas de gestación por versión; Q-D3 plausibilidad de la tasa frente a tasas publicadas de mortinatos (NCHS, Gregory et al.; cita completa en `count_audit_es.md`) | D3, D5 |
| **E · Elegibilidad y tiempo** | Q-E1 duración de la estancia en eventos y no eventos; Q-E2 elegibilidad a las 24 horas por alcance y eventos perdidos; Q-E3 momento del primer laboratorio, del primer ingreso a UCI y de la llegada a urgencias; Q-E4 fechas de los procedimientos de parto o inducción respecto de ingreso + 24 h (los códigos de procedimiento tienen fecha; los de diagnóstico no) | D6, D7, D8 |
| **F · Predictores** | Q-F1 disponibilidad por bloque (antecedentes, hemograma, panel, ambulatorio) según evento, versión de ICD y alcance; Q-F2 regla de cobertura (10 % de la población principal); Q-F3 pacientes sin admisión previa y su efecto en las marcas de antecedentes; Q-F4 registros ambulatorios (OMR), cobertura y momento; Q-F5 unidades y límites de plausibilidad de los laboratorios; Q-F6 cuántos eventos tienen un código relacionado con el desenlace entre los cuatro primeros diagnósticos (por qué se excluyen los diagnósticos de la misma admisión) | D9, D10 |

Valores *legacy* por verificar (en un caso se contradicen): 154 eventos (136 solo estrictos); 2 eventos con morbilidad materna grave y 0 muertes maternas entre los eventos estrictos; las admisiones posteriores a una admisión previa con muerte fetal (17, de ellas 5 eventos) se describen como **menos de 90 días** en `fetal_death_features.sql` y como **dentro de 180 días** en el notebook; muerte fetal previa con al menos 365 días de antelación, 1 evento en 78 admisiones.

### Resultados de la auditoría de conteos, grupos A–D (ejecutada el 28/10/2026)

El informe completo, con tablas, está en [`count_audit_es.md`](count_audit_es.md) (inglés: [`count_audit.md`](count_audit.md)).

Las cifras completas están en la hoja *Conteos* del Excel de seguimiento. La etiqueta provisional reproduce exactamente el conjunto heredado (154 eventos, 136 estrictos, 0 admisiones discordantes) y los conteos base coinciden con la auditoría materna (25,736 admisiones, 15,084 pacientes, 19,425 partos, 19,383 elegibles a 24 h).

- **Eventos.** 154 admisiones (148 pacientes): 127 en hospitalizaciones de parto (114 estrictos), 27 fuera de la marca de parto, 20 de ellas con un código de aborto, ectópico o molar. Quince admisiones tienen código de mortinato pero no la marca de parto, y las 15 tienen también un código de aborto. Ningún código estricto queda fuera del universo obstétrico (Q-B6 vacía). Tasa: 5.87 estrictos por 1,000 hospitalizaciones de parto (referencia nacional, NCHS, 20 semanas o más: 5.44 en 2024), pero 4.05 para 28 semanas o más en admisiones CIE-10 frente a 2.57 a nivel nacional.
- **Edad gestacional.** Los códigos Z3A existen solo en CIE-10 (8,844 de 19,425 partos). Entre los 69 eventos estrictos CIE-10 con semanas, 13 (19 %) tienen menos de 22 semanas, y 7 de esos 13 están dentro de la marca de parto, así que la marca no elimina las pérdidas pre-viables.
- **Pacientes.** El 45.0 % de las pacientes tiene más de una admisión; solo 5 tienen más de una admisión con evento. De los 154 eventos, 61 (40 %) no son la primera admisión de la paciente. Las reglas de cadena de embarazo cambian el número de eventos en 5 como máximo (150, 149 y 149 eventos con 30, 90 y 180 días). Las 17 admisiones posteriores a una admisión con evento son todas de menos de 90 días (ninguna entre 90 y 179), lo que resuelve la contradicción del material heredado.
- **Época.** CIE-9 cubre aproximadamente 2008–2014 y CIE-10 2014–2021, así que versión y año calendario están casi confundidos. La tasa sube de 5.2 (2008–10) a 12.9 (2020–22) por 1,000 partos (tendencia p = 0.007, calculada por el asistente), y es 5.41 en CIE-9 frente a 7.88 en CIE-10.
- **Solapamiento con otros desenlaces.** 15 de los 136 eventos estrictos tienen morbilidad materna grave (definición revisada) y ninguno tiene muerte materna.
- **Verificación de códigos (T15).** La tabla verificada reproduce exactamente la etiqueta provisional (154 eventos, 136 estrictos, 18 solo parciales; 142 y 129 en la población de D3). Toda admisión con alguno de estos códigos en la base completa está dentro del universo obstétrico, y ninguna admisión tiene P95, 768.0 ni 768.1 (códigos del registro del recién nacido), ni Z37.6, Z37.7 o V27.6. De los 136 eventos estrictos, 7 quedan fuera de la población de D3: 6 admisiones con CIE-9 656.4 y 1 con CIE-10 O36.4; los 6 eventos CIE-9 tienen 656.43 (anteparto) (T16). Los códigos de pérdida temprana (O02.1, 632) aparecen en 113 admisiones, 102 sin código de evento (bien excluidas) y 11 con uno, que el script de etiqueta marcará.
- **Tabla de etiqueta por admisión (T16, ejecutada el 29/10/2026).** Integridad confirmada (25,736 filas; 154 eventos; población de D3 19,440 con 142 eventos, 129 estrictos). Los 7 eventos estrictos fuera de D3 tienen solo un código de muerte intrauterina (6 CIE-9 656.43 anteparto, 1 CIE-10 O36.4); un parto en una admisión posterior explica como máximo 2 de ellos. En 65 de 129 eventos estrictos (50 %) un código de muerte fetal es el diagnóstico principal. Diez eventos estrictos de D3 tienen un código de pérdida temprana (todos dentro de las 15 admisiones con código de mortinato sin marca de parto, de las cuales al menos 6 tienen menos de 22 semanas). Tamaños de etiqueta en D3: 129 estrictos, 142 con parciales, 119 sin código de pérdida temprana, 55 con 22 semanas o más (61 con semanas desconocidas), 37 con 28 semanas o más. Las 3 admisiones de menos de 6 horas son no eventos (D8).
- **Conteos para el tamaño de muestra (D12).** 129 eventos estrictos entre 19,440 admisiones; en el punto de predicción de D6 (ingreso + 6 h) se conservan los 129.
- **Elegibilidad y tiempos (grupo E).** A las 24 horas se pierden 17 de 129 eventos estrictos (13.2 %), frente a 28 de 19,298 no eventos (0.15 %), porque los eventos tienen estancias más cortas (mediana de 54 h frente a 71 h). Eventos estrictos aún hospitalizados: 12 h 124, 24 h 112 (86.8 %), 36 h 97, 48 h 75 (58.1 %). El primer laboratorio se toma alrededor del ingreso (mediana 0.0 h, percentil 95 de 3 a 5 h) y cerca de la mitad se toma antes de la hora de ingreso. Hay registro en urgencias en el 15.5 % de los eventos estrictos y en el 2.2 % de los no eventos. Paso por UCI: 8 eventos estrictos (5 en las primeras 24 h). El procedimiento de parto está fechado el día del ingreso o el siguiente en cerca de dos tercios de ambos grupos; en los eventos es más tardío (47 % el día 1 y 19 % el día 2 o después entre los estrictos con procedimiento, frente a 32 % y 11 % en los no eventos). La etiqueta no tiene hora y la muerte fetal suele estar presente ya a la llegada: el modelo es por tanto de riesgo o detección temprana y no una predicción de un evento posterior.

## 5. Decisiones

Las recomendaciones son mías; son propuestas hasta que las registres en el Excel.

| ID | Decisión | Opciones | Recomendación | Cuándo |
|---|---|---|---|---|
| D1 | Base de datos | Tablas revisadas del proyecto materno; cohorte antigua; ambas | **Decidida:** tablas revisadas del proyecto materno | 28/10/2026 |
| D2 | Nombre y estatus del desenlace | *Muerte fetal* (proxy); *muerte perinatal*; *muerte perinatal antes del nacimiento* | **Decidida el 28/10/2026:** *muerte perinatal antes del nacimiento* (parte anteparto de la muerte perinatal: muerte fetal o mortinato), siempre señalada como proxy; no se capturan las muertes neonatales tempranas | Antes de redactar |
| D3 | Población principal | Hospitalizaciones de parto; cualquier admisión obstétrica; admisiones con código obstétrico estructurado | **Decidida el 28/10/2026:** hospitalizaciones de parto (marca v2) más las admisiones con código de mortinato (Z37.1/.4/.7, V27.1/.4/.7), que la marca no ve cuando también hay un código de aborto: 19,440 admisiones, 142 eventos (129 estrictos). Solo la marca de parto y cualquier admisión obstétrica como sensibilidad | 28/10/2026 |
| D4 | Unidad de análisis y mismo embarazo | Admisión; parto; cadena de embarazo (admisiones unidas por una regla de intervalo); primera admisión por paciente | **Decidida el 28/10/2026:** un registro por hospitalización de parto, con validación agrupada por paciente; cadena de embarazo (intervalo de 90 días) como sensibilidad; primera admisión por paciente descartada (pierde el 40 % de los eventos) | 28/10/2026 |
| D5 | Definición del desenlace | Estricta; estricta más parcial; con o sin verificación de edad gestacional | **Decidida el 28/10/2026:** código estricto a cualquier edad gestacional como definición principal; estricta más parcial y las franjas de 22 o más y 28 o más semanas (solo CIE-10) como sensibilidad; **añadida el 29/10/2026:** excluir los 10 eventos estrictos con código de pérdida temprana (SA11). La lista de códigos se verifica en T15 | 28/10/2026 |
| D6 | Punto de predicción | Llegada; 24 h después del ingreso (como SMM); clasificación retrospectiva | **Decidida el 28/10/2026:** hora de ingreso + 6 h. Conserva los 129 eventos estrictos y 19,437 de las 19,440 admisiones. Sensibilidad: 12 h (124 eventos), 24 h como el proyecto materno (112 eventos) y clasificación retrospectiva | 28/10/2026 |
| D7 | Tiempo cero y ventana | Hora de ingreso; el más temprano entre registro en urgencias e ingreso; ventana de 24 h antes a 24 h después (D10 materna) | **Decidida el 28/10/2026:** tiempo cero = hora de ingreso; ventana desde 24 h antes del ingreso hasta el punto de predicción de D6 (la ventana materna con el final acortado). Se descarta lo más temprano entre urgencias e ingreso (solo el 2.3 % de las admisiones tiene registro en urgencias) | 28/10/2026 |
| D8 | Admisiones que terminan antes del punto de predicción | Excluir y reportar sus eventos aparte; incluir con predictores faltantes | **Decidido el 28/10/2026:** excluir las 3 admisiones que terminan antes de ingreso + 6 h (0 eventos) y reportarlas aparte (columna `ends_before_6h` de la tabla de etiqueta) | Después de D6 |
| D9 | Diagnósticos de la misma admisión | Fuera de todo modelo; fuera del principal con sensibilidad retrospectiva; dentro | Fuera del modelo principal; sensibilidad SA7 | Después de Q-F6 |
| D10 | Selección de predictores | Prespecificada por regla temporal, justificación clínica y cobertura; o elegida por contraste con el desenlace | Prespecificada. El contraste con el desenlace solo puede usarse para **excluir** pruebas que filtran información (como coagulación y LDH), nunca para incluir variables, salvo dentro de cada pliegue de entrenamiento | Después de Q-F |
| D11 | Modelos y desbalance | Ensamble apilado más regresión logística; solo regresión logística regularizada; remuestreo | Regresión logística penalizada como referencia y candidata principal; ensamble comparado en los mismos pliegues; sin SMOTE; pesos de clase solo como opción de la grilla | Después del cálculo de tamaño de muestra |
| D12 | Modelo o análisis de factibilidad | Modelo completo; análisis descriptivo más un modelo simple prespecificado | Decidir con los criterios de Riley et al. y el número final de eventos | Después de Q-C4 y tamaño de muestra |
| D13 | Salidas agregadas y celdas pequeñas | Publicar las salidas; regla para conteos pequeños | Publicar agregados; reemplazar conteos menores de 5 por «<5» en los archivos publicados | Antes del primer commit de salidas |
| D14 | Destino | Capítulo de tesis; artículo; ambos | Decidir con el tutor; fija el formato de reporte | Antes de F6 |

## 6. Validación, notebooks y scripts

**Validación (como en el notebook 02 del proyecto materno).** Particiones agrupadas por paciente (`StratifiedGroupKFold`), 5 pliegues externos repetidos 3 veces, pliegues internos agrupados para ajuste, y imputación, escalado, apilamiento y recalibración ajustados dentro de la parte de entrenamiento. Métricas: AUROC, AUPRC con la prevalencia, puntaje de Brier, pendiente e intercepto de calibración, observado/esperado, curva de decisión; intervalos bootstrap por conglomerados (a nivel de paciente). Tamaño de muestra con los criterios de Riley et al. antes de modelar; se reporta cuántos parámetros pueden sostener los eventos.

**Notebooks (nombres propuestos, ninguno escrito todavía).**

| Notebook | Contenido | Análogo materno |
|---|---|---|
| `01_patient_overlap` | partición por admisión: pacientes y pacientes con evento en ambos lados | 01 |
| `02_grouped_validation_fetal_death` | modelo principal, validación anidada agrupada por paciente, calibración, curva de decisión | 02 |
| `03_resampling_comparison` | sin corrección, pesos de clase, SMOTENC (solo si D11 lo permite) | 03 |
| `04_availability_indicators` | con y sin los indicadores de disponibilidad de hemograma, panel y OMR | 04 |
| `05_era_temporal_validation` | era calendario, versión de ICD, validación temporal | 05 |
| `06_same_admission_diagnoses` | sensibilidad retrospectiva con grupos de diagnósticos sin los códigos del desenlace (SA7) | nuevo |
| `07_timing_vs_prediction_point` | eventos ubicados en el tiempo con fechas de procedimientos | 07 |

El `01_fetal_death_models.ipynb` actual se renombra `00_exploratory_fetal_death_models.ipynb` cuando existan los notebooks nuevos.

**Scripts SQL (propuestos, cada uno con su versión `_es`).** `sql/01_labels/` (`01_fetal_death_codes_official.sql`, la tabla verificada de códigos, se ejecutó el 28/10/2026, tarea T15; `02_fetal_death_label_by_admission.sql`, la tabla de etiqueta por admisión `fetal_death_label_v2`, se ejecutó el 29/10/2026, tarea T16; `sql/00_mimic_layer/` (`01_unit_of_analysis.sql`, el adaptador de MIMIC-IV de la etapa E5 del framework, independiente del desenlace, tabla `unit_of_analysis_v2`: unidad, grupo por paciente, tiempo cero y punto de predicción, intervalo con la admisión previa y cadenas de embarazo de 30, 90 y 180 días; escrito el 29/10/2026, tarea T17, aún sin ejecutar), `sql/02_audit_counts/` (grupos A–F; `audit_counts.sql` para A–D se ejecutó el 28/10/2026, `audit_counts_timing.sql` para E se ejecutó el 28/10/2026, tarea T20; F es un script aparte), `sql/03_predictors/` (ventana, bloques, diccionario, faltantes). Los cuatro scripts migrados permanecen en `sql/` hasta reemplazarse: el de factibilidad lo reemplaza la auditoría, los de conjunto de datos y variables se reconstruyen sobre la cohorte revisada, y el de descubrimiento de variables queda como evidencia exploratoria.

## 7. Análisis de sensibilidad

| ID | Análisis | Pregunta |
|---|---|---|
| SA1 | Desenlace solo estricto | ¿Los códigos parciales (embarazo múltiple) cambian el resultado? |
| SA2 | Solo admisiones ICD-10; edad gestacional de al menos 22 semanas donde se conoce | ¿Se sostiene la definición de 22 semanas? |
| SA3 | Un registro por paciente o por embarazo | ¿El solapamiento de pacientes o el embarazo repetido inflan el rendimiento? |
| SA4 | Alcance: parto, código obstétrico estructurado, cualquier admisión obstétrica | ¿La población cambia el resultado? |
| SA5 | Con y sin variables ambulatorias (OMR); con y sin indicadores de disponibilidad | ¿El modelo aprende quién se evaluó y no la fisiología? |
| SA6 | Era calendario, versión de ICD, validación temporal | ¿El modelo aprende el período? |
| SA7 | **Diagnósticos de la misma admisión usados o no** | ¿Cuánto del rendimiento aparente viene de información que produce el evento? Se reporta como clasificación retrospectiva, nunca como predicción |
| SA8 | Excluir eventos que también tienen morbilidad materna grave o muerte materna | ¿Importa el solapamiento con los desenlaces maternos? |
| SA9 | Comparación de remuestreo (opcional) | ¿Ayuda el remuestreo? |
| SA10 | Mortinato tardío: edad gestacional de 28 semanas o más, solo admisiones ICD-10 | ¿Se sostiene el resultado con el umbral de la OMS para comparación internacional? |
| SA11 | Excluir los 10 eventos estrictos con código de pérdida temprana (O02.1, 632); quedan 119 estrictos | ¿Las pérdidas previables codificadas con códigos de desenlace de parto determinan el resultado? (confirmada el 29/10/2026, tras Q-T16e) |

**SA7 en detalle.** Modelo principal: ningún diagnóstico de la misma admisión (el desenlace se define con diagnósticos). Sensibilidad: agregar indicadores de grupos de diagnóstico de la misma admisión sin los códigos del desenlace ni sus acompañantes directos, y reportar el cambio en AUROC y AUPRC como la parte del rendimiento que viene de información producida por el evento. Los diagnósticos de admisiones **anteriores** (antecedentes) se mantienen en el modelo principal.

## 8. Reporte

Lista TRIPOD+AI en `docs/` (con `_es`); solo salidas agregadas en `data/outputs_*.txt` bajo D13; diccionario de predictores, tablas de faltantes y listas de códigos como documentos suplementarios; cada script SQL con su versión `_es` y `python scripts/check_sql_pair.py sql` en verde.

## 9. Riesgos declarados desde ahora

- **Pocos eventos** (unos 150 antes de cualquier regla): intervalos anchos; la validación anidada es la evidencia principal y la opción de factibilidad (D12) sigue abierta.
- **Sesgo de visibilidad en los antecedentes:** el antecedente existe solo para pacientes con una admisión previa en el mismo hospital; la ausencia no es un negativo (Q-F3).
- **Selección por el desenlace en la fase exploratoria:** el script de descubrimiento de variables comparó tasas de eventos por variable en todo el conjunto; D10 limita cómo puede usarse esa evidencia.
- **Era y codificación:** las semanas de gestación existen solo en ICD-10; los eventos ICD-9 no pueden compararse con el umbral de 22 semanas.
- **Temporalidad:** el diagnóstico puede conocerse al llegar; los laboratorios de la ventana ya pueden reflejar el evento (por eso se excluyeron coagulación y LDH).
- **Desenlace proxy y centro único:** sin validación externa; código de investigación, no una herramienta clínica.

## 10. Orden de trabajo

Se sigue tarea por tarea en la hoja *Plan de trabajo* (44 tareas, fases F0–F6). Puertas: ningún modelo antes de resolver D3–D5 con la auditoría; ninguna tabla de predictores antes de D6–D8; ninguna validación antes de la verificación del tamaño de muestra (D12).
