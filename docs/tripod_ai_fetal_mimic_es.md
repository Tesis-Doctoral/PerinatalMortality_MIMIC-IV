# Etapa E11 — lista TRIPOD+AI: muerte fetal en MIMIC-IV (M3), análisis de factibilidad

Versión en inglés: [`tripod_ai_fetal_mimic.md`](tripod_ai_fetal_mimic.md). Lista de TRIPOD+AI (Collins et al., BMJ 2024;385:e078378) para el modelo M3 (muerte fetal, identificada con los códigos CIE de la madre, en las hospitalizaciones de parto de MIMIC-IV v3.1). Versión del 26/11/2026.

**Lista reducida.** M3 se detuvo antes de ajustar cualquier modelo: en el ingreso + 6 horas, la etapa E6 encontró que 73 de las 129 muertes fetales (56,6%) ya estaban presentes (fallaría C1); tras el retorno R3 (predicción prenatal), la puerta P3 no pasó (R² de Cox-Snell con validación cruzada −0,00221). Se reporta como **análisis de factibilidad**. Aplican los ítems sobre los datos, el desenlace, los predictores y el tamaño de muestra; los ítems sobre el modelo ajustado, su desempeño y su uso no aplican y se marcan "—" con la razón.

**Estado:** ✅ reportado en el repositorio · 📝 por escribir en la monografía o el artículo · ⚠️ brecha · — no aplica (con la razón).

Abreviaturas: **FD-P** = ficha del desenlace del modelo prenatal [`outcome_card_antenatal_es.md`](outcome_card_antenatal_es.md); **FD-6h** = ficha en el ingreso + 6 h [`outcome_card_fetal_death_es.md`](outcome_card_fetal_death_es.md); **AC** = [`../count_audit_es.md`](../count_audit_es.md); **AC-P** = [`../count_audit_antenatal_es.md`](../count_audit_antenatal_es.md); **NB0x** = `notebooks/0x_*_es.ipynb`; **OUT0x** = `data/outputs_0x_*.txt`; **FW** = framework ([StagedFramework_ClinicalPrediction](https://github.com/Tesis-Doctoral/StagedFramework_ClinicalPrediction/blob/main/README_es.md)).

## Título y resumen

| Ítem | Contenido | Dónde | Estado |
|---|---|---|---|
| 1 | Título: desarrollo no completado, población, desenlace | Capítulo 7 de la monografía: "muerte fetal en MIMIC-IV… factibilidad" | 📝 |
| 2 | Resumen | Monografía | 📝 |

## Introducción

| Ítem | Contenido | Dónde | Estado |
|---|---|---|---|
| 3a | Contexto en salud y justificación; modelos existentes | FD-P §1, §6 (los modelos prenatales de mortinato suelen alcanzar un AUROC de 0,60 a 0,75); monografía | 📝 |
| 3b | Población objetivo, punto de predicción, usuarios | FD-P §2–§3 (hospitalizaciones de parto; información de al menos 7 días antes del ingreso) | ✅ |
| 3c | Desigualdades en salud conocidas | Monografía | 📝 |
| 4 | Objetivos | README; FD-P §1 | ✅ |

## Métodos

| Ítem | Contenido | Dónde | Estado |
|---|---|---|---|
| 5a | Fuente de datos, representatividad | README (acceso a los datos); FD-P §2, §7: MIMIC-IV v3.1, un hospital académico (Beth Israel Deaconess Medical Center, Boston) | ✅ |
| 5b | Fechas de los datos | MIMIC-IV 2008–2022, fechas desplazadas por paciente (grupos de año ancla); NB01 (E1) | ✅ |
| 6a | Entorno y centros | Un centro, hospitalizaciones y registros ambulatorios (FD-P §3) | ✅ |
| 6b | Criterios de elegibilidad | FD-P §2: hospitalizaciones de parto más admisiones con código de mortinato (19.440 admisiones, 13.735 pacientes); NB01, NB04 (puerta P1) | ✅ |
| 6c | Tratamientos y cómo se manejaron | FD-P §3: no entra nada de la admisión actual; solo la historia previa | ✅ |
| 7 | Preparación de los datos y control de calidad | Scripts de `sql/` con verificaciones; NB01 y NB04 (puerta P1: conteos de referencia reproducidos); límites de plausibilidad (FD-P §4) | ✅ |
| 8a | Desenlace, cómo y cuándo se evaluó | FD-P §2: código estricto de muerte fetal de la madre (129 eventos, 0,66%), siempre marcado como aproximación; AC (catálogo de códigos) | ✅ |
| 8b | Evaluación subjetiva del desenlace | Códigos de diagnóstico registrados por el hospital; los códigos no tienen fecha (AC, grupo G) | ✅ |
| 8c | Cegamiento | — No se ajustó ningún modelo | — |
| 9a | Elección inicial de predictores | FD-P §4 (27 parámetros fijados con la auditoría de conteos, nunca separados por desenlace; variables retiradas con la razón) | ✅ |
| 9b | Definición de cada predictor | FD-P §4; [`../predictor_table_antenatal_es.md`](../predictor_table_antenatal_es.md); NB05 | ✅ |
| 9c | Evaluación subjetiva de predictores | Presión arterial, IMC y laboratorios son mediciones; los antecedentes son códigos de diagnóstico | ✅ |
| 10 | Tamaño de muestra | Puerta P3 del NB06 (Riley et al. con el R² de Cox-Snell observado con validación cruzada: −0,00221, −2,9% del máximo; R² mínimo 0,0124 para 27 parámetros y 0,0078 para el conjunto reducido de 17); OUT06 | ✅ |
| 11 | Datos faltantes | FD-P §5 (imputación múltiple planeada; presión faltante en 38,7%, hemoglobina 41,2%, IMC 57,3%); NB05 | ✅ |
| 12a–12g | Uso de los datos, predictores, tipo de modelo, ajuste, medidas, actualización, predicciones | — No se ajustó ningún modelo: el análisis se detuvo en E6 (ingreso + 6 h) y en P3 (prenatal). La partición agrupada por paciente usada para estimar el R² de la puerta P3 está en el NB06 | — |
| 13 | Desbalance de clases | — No se ajustó ningún modelo | — |
| 14 | Equidad | — No se ajustó ningún modelo | — |
| 15 | Salida del modelo y umbrales | — No se ajustó ningún modelo | — |
| 16 | Diferencias entre datos de desarrollo y de evaluación | — Sin evaluación | — |
| 17 | Aprobación ética y consentimiento | MIMIC-IV: datos anonimizados, aprobación original del comité de ética con exención de consentimiento; acceso bajo el acuerdo de uso de datos acreditado de PhysioNet con formación CITI (README, acceso a los datos); solo salidas agregadas, conteos de 1 a 4 como "<5". Falta el concepto del comité de ética de Uninorte | 📝 |

## Ciencia abierta

| Ítem | Contenido | Dónde | Estado |
|---|---|---|---|
| 18a | Financiación | Monografía | 📝 |
| 18b | Conflictos de interés | Monografía | 📝 |
| 18c | Protocolo y desviaciones | [`../analysis_plan_es.md`](../analysis_plan_es.md) (decisiones D1 a D14); FD-P y FD-6h (decisiones fechadas); FW | ✅ |
| 18d | Registro | No registrado; declararlo | 📝 |
| 18e | Disponibilidad de los datos | MIMIC-IV en PhysioNet para usuarios acreditados; no se redistribuye (README) | ✅ |
| 18f | Disponibilidad del código, software y versiones | GitHub (Tesis-Doctoral/PerinatalMortality_MIMIC-IV); `requirements.txt`; versiones de las librerías impresas en el NB01 (E1) | ✅ |
| 19 | Participación de pacientes y público | No hubo; declararlo | 📝 |

## Resultados

| Ítem | Contenido | Dónde | Estado |
|---|---|---|---|
| 20a | Flujo de participantes, con y sin el desenlace | NB01 y NB04 (universo de 25.736 admisiones obstétricas → población de 19.440 → 129 eventos estrictos; 99 eventos con información 7 días antes del ingreso, OUT04 Q-A1) | ✅ |
| 20b | Características de los datos, predictores, faltantes | OUT05 (Q-P2, Q-P3: predictores categóricos y continuos; faltantes de la matriz de diseño) | ✅ |
| 20c | Desarrollo frente a evaluación | — Sin evaluación | — |
| 21 | Participantes y eventos en cada análisis | OUT03 (73 de 129 eventos presentes en el ingreso + 6 h); OUT06 (19.440 admisiones, 129 eventos, particiones de la puerta P3) | ✅ |
| 22–24 | Especificación del modelo, desempeño, actualización | — No se ajustó ningún modelo | — |

## Discusión

| Ítem | Contenido | Dónde | Estado |
|---|---|---|---|
| 25 | Interpretación general | OUT06 (clase: factibilidad; con la información que MIMIC-IV registra antes del ingreso, la muerte fetal no se puede predecir); capítulo 7 de la monografía | 📝 |
| 26 | Limitaciones | FD-P §3 (una muerte anterior al margen de 7 días no se puede excluir con códigos), AC (códigos sin fecha, sin enlace madre–recién nacido) | ✅ |
| 27a–27b | Datos de entrada y usuarios en el uso | — Sin uso | — |
| 27c | Investigación futura | FD-6h y FD-P (datos que harían falta: eventos obstétricos fechados, enlace con el registro del recién nacido); monografía | 📝 |

No quedan brechas del repositorio: lo que falta son textos de la monografía (📝) y el concepto del comité de ética de Uninorte.

*Confidencial: uso interno del proyecto de investigación.*
