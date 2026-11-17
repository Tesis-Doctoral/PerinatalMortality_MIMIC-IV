# Ficha del desenlace — muerte perinatal antes del nacimiento (muerte fetal), MIMIC-IV

Versión 1, 17/11/2026. Ficha de la segunda aplicación del framework por etapas ([`../framework_es.md`](../framework_es.md), versión 1.0). Llenada a partir de [`../analysis_plan_es.md`](../analysis_plan_es.md) (decisiones D1 a D14) y [`../count_audit_es.md`](../count_audit_es.md). Los campos marcados **pendiente** deben fijarse, y registrarse en el libro de decisiones, antes de la puerta que los necesita. Versión en inglés: [`outcome_card_fetal_death.md`](outcome_card_fetal_death.md).

## 1. Identidad

| Campo | Valor | Fuente |
|---|---|---|
| Desenlace | Muerte perinatal antes del nacimiento (muerte fetal o mortinato), siempre rotulada como proxy; no se capturan las muertes neonatales tempranas | D2 |
| Peldaño en la escalera de desenlaces | Desenlace ideal de la ranura perinatal (primer peldaño). Peldaños siguientes: **pendiente** (sección 6) | — |
| Fuente de datos y adaptador | MIMIC-IV v3.1; tablas del proyecto materno revisado más `unit_of_analysis_v2` | D1, T17 |
| Unidad de análisis | Hospitalización de parto; paciente como unidad de agrupación; cadena de embarazo de 90 días como sensibilidad | D4 |
| Población | Bandera de parto (v2) o código de mortinato: 19.440 admisiones; 19.437 en el punto de predicción | D3, D8 |

## 2. Evento (E3)

| Campo | Valor | Fuente |
|---|---|---|
| Definición principal | Código estricto a cualquier edad gestacional: CIE-10-CM O36.4, Z37.1, Z37.4, Z37.7; CIE-9-CM 656.4, V27.1, V27.4, V27.7 | D5, T15 |
| Eventos (conteo esperado) | 129 estrictos (0,66%); 142 con códigos parciales | T16 |
| Tabla de etiqueta | `mimiciv.fetal_death_label_v2` (una fila por admisión; definiciones de sensibilidad como columnas) | T16 |
| Momento del evento | **Ninguno**: códigos diagnósticos de egreso sin fecha. En 65 de 129 eventos (50%) un código de muerte fetal es el diagnóstico principal; los códigos de procedimiento sí tienen fecha | Q-T16, Q-E4 |
| Clases temporales | **Pendiente (tarea nueva, ver sección 5).** Necesarias para los criterios C1 y C2 y para la puerta P1 | — |
| Riesgos conocidos | Sin momento del evento; pérdidas previables dentro de la etiqueta (10 eventos estrictos con código de pérdida temprana); semanas de gestación solo en CIE-10; la tasa sube con el período (de 5,2 a 12,9 por 1.000) | auditoría de conteos |

## 3. Punto de predicción, ventana y predictores (E6, E7)

| Campo | Valor | Fuente |
|---|---|---|
| Tiempo cero | Hora de ingreso | D7 |
| Punto de predicción | Ingreso + 6 horas; 12 h, 24 h y clasificación retrospectiva como sensibilidad | D6 |
| Ventana | Desde 24 h antes del ingreso hasta el punto de predicción | D7 |
| Excluidos | Diagnósticos, procedimientos, códigos DRG y tratamientos de la misma admisión (modelo principal) | D9 (propuesta) |
| Predictores candidatos | **Pendiente (grupo F, tareas T23–T25; D10).** Bloques: variables de registro y edad, antecedentes de admisiones anteriores, hemograma y química en la ventana, mediciones ambulatorias (OMR), cada uno con su indicador de faltante | plan de análisis |
| Parámetros candidatos | **Pendiente.** Contar cada categoría y cada indicador de faltante | — |

## 4. Tamaño de muestra y modelo (P3, E8)

| Campo | Valor | Fuente |
|---|---|---|
| Estimación previa de parámetros soportados | Con 19.437 admisiones y 129 eventos (prevalencia 0,0066; R² de Cox-Snell máximo 0,077), el criterio de encogimiento soporta unos **17 parámetros** si el R² es el 10% de su máximo y unos **25** si es el 15%. Como referencia, el modelo de SMM alcanzó el 16% y el de escalamiento el 12%. Cálculo del asistente; la puerta usa el R² observado | Riley et al. |
| Modelo principal | Regresión logística penalizada, porque los eventos por parámetro candidato quedarán por debajo de 20 (129 eventos / 17–25 parámetros ≈ 5–8). Bosque aleatorio, árboles extra, XGBoost y el ensamble apilado son comparaciones. Coherente con D11 | D11; regla del framework del 11/11/2026 (pendiente de validación) |
| Conjunto reducido de predictores | **Por fijar antes de P3** (reducción por tamaño de muestra). Regla propuesta, como en el estudio de SMM: conservar la edad y los laboratorios centrales con sus indicadores de faltante; colapsar seguro, idioma, tipo de admisión y lugar de admisión en indicadores binarios; agrupar raza y etnia en cinco categorías; retirar primero los bloques de baja cobertura. Nunca elegido por asociación con el desenlace | framework, sección 4 |
| Si falla P3 | Análisis de factibilidad (D12) y retorno R1 al siguiente peldaño | D12 |

## 5. Criterios de clasificación (P4)

Se fijan antes de cualquier modelo. Los umbrales son los del framework (sección 4).

| Criterio | Cómo se aplica a este desenlace | Estado |
|---|---|---|
| C1, eventos ya presentes | Población landmark = admisiones sin una muerte fetal ya presente en el punto de predicción. Como la etiqueta no tiene momento, la presencia debe venir de proxies. Candidatos a medir: un código de muerte intrauterina (O36.4, 656.4: atención por una muerte fetal conocida); un código de muerte fetal como diagnóstico principal (motivo de la admisión); ingreso a UCI antes del punto de predicción; procedimiento de parto o inducción fechado el día del ingreso. Cada proxy se cuenta primero y luego se fija la regla | **Pendiente: tarea de conteo nueva** |
| C2, desenlace con tiempo | Necesita eventos fechados después del punto de predicción. Los códigos CIE no separan una muerte anteparto de una intraparto, y los registros del recién nacido no están vinculados. Salvo que la tarea de clases temporales encuentre un subconjunto fechado, C2 no puede probarse | **Probablemente no evaluable** |
| C3, sesgo de detección | El desenlace no se define con un examen de laboratorio, así que su detección no depende de a quién se le hizo un examen en los datos | No aplica (propuesta) |
| C4, estabilidad en el tiempo | Desarrollo antes de 2017 y una sola prueba de 2017 en adelante, como en el estudio de SMM; corte en 2015 (transición CIE) como sensibilidad. La tasa creciente (de 5,2 a 12,9 por 1.000) hace probable la deriva de la calibración | Aplica; eventos por período **pendientes** |

**Lo que cabe esperar, dicho antes de los resultados.** La auditoría de conteos ya encontró que la muerte fetal suele estar presente al ingreso y que la etiqueta no tiene momento. Si C2 no puede probarse, la mejor clase posible es identificador temprano, sea cual sea la AUROC. Es un resultado legítimo del framework: evitaría afirmar que el modelo predice la muerte fetal.

## 6. Retornos disponibles

| Retorno | Opción para este desenlace | Estado |
|---|---|---|
| R1 | Siguiente peldaño si falla P3: un sustituto más frecuente en la misma ruta (por ejemplo restricción del crecimiento fetal o un compuesto de códigos de desenlace fetal adverso) | **Pendiente**: candidatos por contar |
| R2 | Un desenlace fechado después del punto de predicción: ninguno identificado aún (la muerte intraparto no puede separarse) | **Pendiente** |
| R3 | Otro punto de predicción: llegada (solo datos de registro) o 12–24 h | Posible (sensibilidades de D6) |
| R4 | Más predictores o predictores distintos: registros ambulatorios (OMR) o bloques de antecedentes | Posible (grupo F) |

Como máximo dos retornos.

## 7. Set de sensibilidad (E9)

SA1 a SA11 de [`../analysis_plan_es.md`](../analysis_plan_es.md), sección 7 (renombrados de S1–S11 el 17/11/2026 para que no choquen con las etapas en inglés). A ellos se suman los criterios C1 a C4.

## 8. Próximas tareas, en el orden en que las piden las puertas

1. Ejecutar T17 (`unit_of_analysis_v2`) y Q-C5 (T13). → E5.
2. Tarea T45 (`sql/02_audit_counts/audit_counts_event_timing_es.sql`, grupo G): clases temporales de los eventos de muerte fetal a partir de los proxies de la sección 5, y decisión sobre C1 y C2. → E3, P1.
3. Grupo F de la auditoría de conteos (T23–T25) y decisiones D9, D10. → E7.
4. Contar los parámetros candidatos, fijar el conjunto reducido de predictores y registrar el modelo principal. → antes de P3.
5. Verificación del tamaño de muestra con el R² de Cox-Snell observado (D12). → P3.

*Confidencial: uso interno del proyecto de investigación.*
