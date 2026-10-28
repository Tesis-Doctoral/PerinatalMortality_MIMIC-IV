# Plan de análisis — modelos de muerte perinatal (componente fetal), MIMIC-IV

Documento de trabajo. Los puntos marcados **[decisión]** están abiertos y deben resolverse antes de la primera ejecución. Las cifras citadas vienen de los scripts exploratorios anteriores en `legacy/` y deben verificarse de nuevo cuando esos scripts se migren.

## 1. Propósito

Construir y evaluar modelos de predicción de la muerte perinatal con las admisiones obstétricas de MIMIC-IV, empezando por el componente de muerte fetal (el tercer modelo de la tesis, después de la mortalidad materna y de la morbilidad materna grave). El primer objetivo es comprobar si el marco de modelado del proyecto materno (validación agrupada por paciente, recalibración, reporte según TRIPOD+AI) se traslada a un desenlace nuevo sin fuga de información.

## 2. Población

- Punto de partida: las 25,736 admisiones obstétricas de la cohorte materna (`mimiciv.cohort_smm_dataset`), de modo que todos los modelos comparten una sola cohorte.
- **[decisión]** Población final: todas las admisiones obstétricas, o solo las hospitalizaciones de parto (como en el modelo de SMM).
- **[decisión]** Regla del mismo embarazo: se descartan las admisiones ocurridas dentro de un número de días tras una admisión previa con muerte fetal de la misma paciente (el notebook usa el parámetro `POST_EVENT_WINDOW_DAYS`).

## 3. Desenlace

- Muerte fetal desde las 22 semanas completas, a partir de los códigos ICD-9-CM e ICD-10-CM de la madre (tabla `mimiciv.fetal_death_code_patterns`). *Estricta:* el código indica que el feto murió. *Parcial:* embarazo múltiple en el que murieron solo algunos fetos.
- Se excluyen las pérdidas previables (aborto, embarazo ectópico, aborto retenido, ICD-9 630–639): ocurren antes de las 22 semanas.
- La verificación de factibilidad encontró 154 admisiones con la definición estricta o parcial (136 solo estrictas). **[decisión]** Definición principal: estricta, o estricta más parcial.
- Las muertes neonatales tempranas no se capturan (MIMIC-IV no tiene un vínculo madre–recién nacido validado), por lo que en todos los documentos el desenlace debe llamarse *muerte fetal*, no *muerte perinatal*.

## 4. Momento de la predicción y control de fuga

- Una variable es elegible solo si se conoce al llegar o antes (registro en urgencias o ingreso, lo que ocurra primero), o si se midió en las primeras 24 horas desde la llegada.
- No son elegibles: diagnósticos, procedimientos, DRG, tratamientos y microbiología de la misma admisión (los produce el evento), ni las pruebas de coagulación y la LDH (se piden después del diagnóstico).
- **[decisión]** Momento de la predicción: a la llegada, o a las 24 horas (como en el modelo de SMM, lo que excluiría los eventos anteriores a las 24 h y exigiría reportarlos aparte).
- No se usan los indicadores de grupos de diagnóstico (`gdg_*`): provienen de los mismos diagnósticos codificados que definen el desenlace.

## 5. Predictores

Bloques del conjunto ampliado (`mimiciv.cohort_fetal_death_dataset_ext`): atributos de la admisión; antecedentes de admisiones previas de la misma paciente (hipertensión, diabetes, obesidad, enfermedad renal, muerte fetal previa de al menos 365 días antes); primer hemograma y panel químico en las primeras 24 horas; mediciones ambulatorias de los 365 días previos a la admisión (presión arterial, peso, IMC). `gest_weeks` (de los códigos Z3A, solo ICD-10) y las banderas estricta/parcial son metadatos, no predictores.

## 6. Validación y análisis

Sigue el proyecto materno revisado:

- Particiones agrupadas por paciente (`StratifiedGroupKFold`); validación cruzada anidada repetida varias veces; imputación, escalado, ajuste, apilamiento y recalibración se ajustan dentro de la porción de entrenamiento de cada pliegue.
- Modelos: regresión logística regularizada, Random Forest, Extra Trees, XGBoost y un ensamble apilado con metaaprendiz logístico.
- Métricas: AUROC, AUPRC con la prevalencia, puntaje de Brier, pendiente e intercepto de calibración, observado/esperado, curva de decisión; intervalos bootstrap a nivel de paciente.
- Verificación del tamaño de muestra con los criterios de Riley et al. antes de modelar. Con unos 150 eventos, hay que reportar cuántos parámetros pueden sostener los datos.
- **[decisión]** Si se ejecuta el modelo cuando los criterios no se cumplen, o si se reporta solo como análisis de factibilidad (como se hizo con la muerte materna).

## 7. Análisis de sensibilidad (propuestos)

Desenlace solo estricto; solo admisiones ICD-10 (hay semanas de gestación); primera admisión por paciente; con y sin las variables ambulatorias (OMR); era calendario y validación temporal.

## 8. Reporte

Lista TRIPOD+AI en `docs/`; solo salidas agregadas en `data/outputs_*.txt` (conteos y métricas, sin identificadores); cada script SQL con su versión `_es`.

## 9. Orden de trabajo

1. ~~Migrar y revisar los scripts SQL de `legacy/sql` (factibilidad, conjunto de datos, descubrimiento de variables, variables ampliadas), con sus versiones `_es`.~~ Hecho el 28/10/2026 (`sql/`; código sin cambios, comentarios actualizados; aún no se han ejecutado en este proyecto).
2. Repetir los conteos de factibilidad y resolver las decisiones anteriores.
3. Construir los conjuntos de datos y ejecutar el notebook (migrado el 28/10/2026 como `notebooks/01_fetal_death_models.ipynb`), agregando validación anidada agrupada por paciente.
4. Verificación del tamaño de muestra, modelos, calibración, análisis de sensibilidad.
5. Salidas, lista TRIPOD+AI y manuscrito.
