# Muerte fetal en MIMIC-IV (modelo M3)

> **Framework.** Este repositorio aplica el framework por etapas para modelos de predicción clínica de la tesis. El framework (etapas, puertas, criterios y literatura) y el catálogo de modelos con su estado están en [StagedFramework_ClinicalPrediction](https://github.com/Tesis-Doctoral/StagedFramework_ClinicalPrediction).

¿Se puede predecir la muerte fetal en las hospitalizaciones de parto de MIMIC-IV? El desenlace es la parte de la mortalidad perinatal que ocurre antes del nacimiento, identificada con los códigos CIE de la madre (MIMIC-IV no vincula a la madre con el recién nacido, así que no captura las muertes neonatales tempranas). Los notebooks siguen el framework etapa por etapa y puerta por puerta, en dos puntos de predicción:

1. **Ingreso + 6 horas.** La auditoría de conteos encontró que 73 de las 129 muertes fetales (56,6%) ya estaban presentes en ese punto, así que la etapa E6 detuvo el modelo antes de ajustarlo: habría fallado el criterio C1.
2. **Retorno R3: predicción prenatal.** Solo con la información registrada al menos 7 días antes del ingreso. El modelo es factible en los datos (99 de 129 eventos tienen información previa), pero la puerta de tamaño de muestra P3 no pasa: el R² de Cox-Snell con validación cruzada es negativo (−0,00221).

> **Estado: clasificado como análisis de factibilidad.** Con la información que MIMIC-IV registra antes del ingreso, la muerte fetal no puede predecirse. No se realizan las etapas E8 a E10 ni la puerta P4.

[English version](README.md)

## Orden de ejecución

Cada notebook tiene su versión en inglés (sin sufijo) y en español (`_es`), con el mismo código; solo cambia el idioma de las salidas. Cada sección empieza con el código de la etapa o la puerta, una breve descripción y una tabla de resultado → acción, y su salida termina con la decisión tomada. Cada notebook termina con un resumen.

| Orden | Notebook | Etapas y puertas | Tablas del esquema `mimiciv` que construye o verifica | Salida |
|---|---|---|---|---|
| 1 | `notebooks/01_outcome_definition_es.ipynb` | E1 · E2 · E3 · P1 | `fetal_death_code_patterns_v2`, `fetal_death_label_v2` | `data/outputs_01_outcome_definition.txt` |
| 2 | `notebooks/02_count_audit_es.ipynb` | E4 | ninguna (solo lectura) | `data/outputs_02_count_audit.txt` |
| 3 | `notebooks/03_unit_and_prediction_point_es.ipynb` | E5 · E6 → retorno R3 | `unit_of_analysis_v2` | `data/outputs_03_unit_and_prediction_point.txt` |
| 4 | `notebooks/04_antenatal_count_audit_es.ipynb` | R3 · E2 · E3 · P1 · E4 | `antenatal_obstetric_universe`, `antenatal_fetal_death_label` | `data/outputs_04_antenatal_count_audit.txt` |
| 5 | `notebooks/05_antenatal_predictors_es.ipynb` | E5 · E6 · E7 · P2 | `antenatal_predictors_v1` | `data/outputs_05_antenatal_predictors.txt` |
| 6 | `notebooks/06_sample_size_gate_es.ipynb` | P3 · clase · E11 | ninguna | `data/outputs_06_sample_size_gate.txt` |

Los notebooks corren los scripts de `sql/` en una sola conexión, como DBeaver con Alt+X. Las tablas del esquema `mimiciv` que ya existen se leen como están y solo se corren sus verificaciones; si una tabla no existe, se construye con su script. Para reconstruirla, poner **`REBUILD = True`** en la primera celda de código del notebook. Las salidas `data/outputs_*.txt` están en inglés (las citan los documentos); los notebooks en español escriben además una copia `data/outputs_*_es.txt`.

Conteos de referencia que deben reproducirse (puerta P1): 25.736 admisiones obstétricas de 15.084 pacientes; 19.440 admisiones en la población del modelo, de 13.735 pacientes; 129 eventos estrictos y 142 con códigos parciales.

## Documentos

| Documento | Contenido |
|---|---|
| [`count_audit_es.md`](count_audit_es.md) | Auditoría de conteos del punto de predicción al ingreso (grupos A a E) y decisiones D1 a D8 |
| [`count_audit_antenatal_es.md`](count_audit_antenatal_es.md) | Auditoría de la información disponible antes del ingreso (retorno R3) |
| [`predictor_table_antenatal_es.md`](predictor_table_antenatal_es.md) | Verificación de la tabla de predictores prenatales |
| [`docs/outcome_card_fetal_death_es.md`](docs/outcome_card_fetal_death_es.md) | Ficha del desenlace, punto de predicción al ingreso + 6 h |
| [`docs/outcome_card_antenatal_es.md`](docs/outcome_card_antenatal_es.md) | Ficha del desenlace, retorno R3 (predicción prenatal) |
| [`docs/tripod_ai_fetal_mimic_es.md`](docs/tripod_ai_fetal_mimic_es.md) | Lista TRIPOD+AI (reducida: análisis de factibilidad, sin modelo ajustado) |
| [`analysis_plan_es.md`](analysis_plan_es.md) | Plan de análisis (decisiones D1 a D14) |
| [StagedFramework_ClinicalPrediction](https://github.com/Tesis-Doctoral/StagedFramework_ClinicalPrediction/blob/main/README_es.md) | Framework por etapas aplicado (única versión vigente; sin copia local) |

Cada documento tiene su versión en inglés con el mismo nombre sin `_es`.

## Requisitos previos

- Una base local de PostgreSQL con MIMIC-IV v3.1 (esquema `mimiciv`).
- Las tablas de la cohorte obstétrica revisada: `cohort_obstetric_v2`, `hadm_delivery_v2`, `obstetric_dx_v2` y `predictors_24h_v2` (notebooks 01 a 03). El retorno R3 (notebooks 04 a 06) construye su propio universo desde las tablas de MIMIC-IV y no depende de ellas.
- Copiar `.env.example` a `.env` en la raíz del proyecto y completar la contraseña de la base local. `.env` nunca se versiona.
- Entorno de Python:
  ```powershell
  python -m venv .venv
  .venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
  pip install -r requirements.txt
  ```
  Seleccionar `.venv` como intérprete y como kernel de Jupyter.

## Estructura del repositorio

```
notebooks/                 Los seis notebooks, en el orden del framework (EN y _es)
sql/00_mimic_layer/        Unidad de análisis (E5): unit_of_analysis_v2
sql/01_labels/             Catálogo verificado de códigos y etiqueta por admisión (E3)
sql/02_audit_counts/       Auditoría de conteos al ingreso: grupos A-D, E (punto de predicción) y G (momento del evento); solo lectura
sql/03_antenatal/          Retorno R3: universo, etiqueta, información previa al ingreso y tabla de predictores
libraries/                 database.py (conexión), sql_runner.py (corre los scripts), presentation.py e i18n (tablas EN/ES),
                           antenatal_design.py (matriz de diseño de los 27 parámetros)
scripts/check_sql_pair.py  Verifica que cada script SQL y su versión _es tengan el mismo código
data/                      Solo salidas agregadas outputs_*.txt y las tablas de grupos *_groups.xlsx
docs/                      Fichas del desenlace
legacy/                    Material anterior al framework, solo como referencia
```

Cada script SQL tiene una versión en español con el sufijo `_es` y el mismo código (`python scripts/check_sql_pair.py sql`).

## Acceso a los datos

Este repositorio **no** incluye datos a nivel de paciente. MIMIC-IV está disponible en [PhysioNet](https://physionet.org/content/mimiciv/) para usuarios acreditados (curso CITI y acuerdo de uso de datos de PhysioNet). Solo se publican salidas agregadas; ningún `subject_id`, `hadm_id` ni fila a nivel de paciente, y los conteos de 1 a 4 se muestran como "<5".

Referencia: Johnson, A.E.W. et al. *MIMIC-IV, a freely accessible electronic health record dataset.* Scientific Data **2023**, 10, 1. https://doi.org/10.1038/s41597-022-01899-x

## Licencia

El código se publica bajo la licencia MIT (ver `LICENSE`).

## Contacto

Emmanuel Gutiérrez Jiménez — emmanuelg@uninorte.edu.co
