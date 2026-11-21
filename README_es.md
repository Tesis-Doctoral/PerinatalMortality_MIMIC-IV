# Modelos de muerte perinatal (componente fetal) en MIMIC-IV

> **Framework.** Este repositorio aplica el framework por etapas para modelos de predicción clínica de la tesis. El framework (etapas, puertas, criterios y literatura) y el catálogo de modelos con su estado están en [StagedFramework_ClinicalPrediction](https://github.com/Tesis-Doctoral/StagedFramework_ClinicalPrediction).

Modelos de predicción de la **muerte perinatal** en admisiones obstétricas de MIMIC-IV, empezando por el **componente de muerte fetal** identificado a partir de los códigos ICD de la madre (el "Modelo C" de la tesis). Este proyecto continúa el trabajo exploratorio hecho dentro de `MaternalMortality_MIMIC-IV`, que se conserva en [`legacy/`](legacy/) hasta que se migre.

> **Estado: migración terminada; los scripts SQL nuevos se están ejecutando uno por uno.** Ejecutados hasta ahora: la tabla verificada de códigos (T15), la auditoría de conteos (T08, T20) y la etiqueta por admisión (T16). Escrito y pendiente de ejecutar: la unidad de análisis (T17). Los cuatro scripts migrados en `sql/`, las consultas de los conjuntos de datos en `libraries/database.py` y el notebook de modelado no se han ejecutado en su nueva ubicación.

[English version](README.md)

## Alcance

- **Desenlace:** muerte fetal desde las 22 semanas completas de gestación (período perinatal de la OMS / ICD-10), identificada a partir de los códigos ICD-9-CM e ICD-10-CM de la madre (una definición *estricta* y una *parcial* que añade los embarazos múltiples en los que murieron solo algunos fetos).
- **Limitación de los datos:** MIMIC-IV no tiene un vínculo madre–recién nacido validado, por lo que las muertes neonatales tempranas (que están en el registro del recién nacido) **no** se capturan.
- **Población:** admisiones obstétricas de la cohorte materna de `MaternalMortality_MIMIC-IV`.
- **Regla contra la fuga de información:** un predictor debe conocerse al llegar o antes, o medirse en las primeras 24 horas; no se usan diagnósticos, procedimientos, DRG ni tratamientos de la misma admisión, porque los genera el propio evento.

El plan de análisis (versión 2, 28/10/2026) está en [`analysis_plan_es.md`](analysis_plan_es.md) (inglés: [`analysis_plan.md`](analysis_plan.md)). Sigue el proyecto materno: una auditoría de conteos y las decisiones sobre cohorte, unidad de análisis y punto de predicción van antes de cualquier modelo. El avance se sigue tarea por tarea en el Excel local `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (no versionado).

La auditoría de conteos está redactada en [`count_audit_es.md`](count_audit_es.md) (inglés: [`count_audit.md`](count_audit.md)): qué midió cada conteo, qué resolvió y qué sigue abierto.

El framework por etapas (versión 1.0, alineada con el artículo de SMM: etapas E1–E11, puertas P1–P4, retornos R1–R4) está en [`framework_es.md`](framework_es.md) (inglés: [`framework.md`](framework.md)); la ficha del desenlace de este proyecto es [`docs/outcome_card_fetal_death_es.md`](docs/outcome_card_fetal_death_es.md). La maqueta del 29/10/2026 se guarda en `docs/backup_framework_v0.1/`. Los análisis de sensibilidad del plan se numeran SA1–SA11.

## Estructura del repositorio

```
sql/                        Scripts SQL de este proyecto, cada uno con su versión _es (ver "Scripts SQL" más abajo)
notebooks/                  01_fetal_death_models.ipynb (hold-out, validación cruzada agrupada por paciente, ablación por bloques de variables, análisis de sensibilidad, SHAP)
libraries/
  database.py               Conexión a la base PostgreSQL de MIMIC-IV (variables de entorno) y las dos consultas que cargan los conjuntos de datos de muerte fetal
  functions.py              Pequeña utilidad estadística
scripts/
  check_sql_pair.py         Verifica que cada script SQL y su versión _es tengan el mismo código
data/                       Tablas de grupos de categorías *_groups.xlsx (solo equivalencias) y salidas agregadas outputs_*.txt (solo conteos y métricas); nada más se versiona
docs/                       Documentos de reporte (lista TRIPOD+AI, tablas suplementarias), el Excel de seguimiento (local) y backup_plan_v1/
legacy/                     Copias originales del material anterior, conservadas solo como referencia (ver legacy/README.md)
docker-compose.yml          Entorno local opcional de PostgreSQL + Jupyter
requirements.txt  .env.example  LICENSE
.vscode/                    Ajustes compartidos de VS Code y extensiones recomendadas
PerinatalMortality_MIMIC-IV.code-workspace
```

## Scripts SQL

**Catálogo verificado de códigos (tarea T15 del plan, ejecutado el 28/10/2026).** `sql/01_labels/01_fetal_death_codes_official.sql` (versión en español: `01_fetal_death_codes_official_es.sql`) crea `mimiciv.fetal_death_code_patterns_v2`: cada patrón de código de muerte fetal con su título oficial, su nivel (estricto, parcial o excluido) y su fuente, más cinco verificaciones agregadas (Q-T15a a Q-T15e). Reemplaza los 13 patrones provisionales de los scripts antiguos; los códigos no cambian, pero la muerte fetal temprana (O02.1, 632) y los códigos de registros de recién nacidos (P95, 768.0, 768.1) quedan ahora listados como excluidos de forma explícita. Se ejecuta como un solo script completo en una conexión (DBeaver: Alt+X).

**Etiqueta por admisión (tarea T16 del plan, ejecutada el 29/10/2026).** `sql/01_labels/02_fetal_death_label_by_admission.sql` (versión en español: `02_fetal_death_label_by_admission_es.sql`) crea `mimiciv.fetal_death_label_v2`, una fila por admisión de `cohort_obstetric_v2`, construida con la tabla verificada de códigos. Además de la etiqueta principal (código estricto, decisión D5) incluye, como columnas y no como filtros, el nivel del evento, las familias de código, la posición del código, las banderas de pérdida temprana y de registro del recién nacido, las semanas de gestación de los códigos Z3A, la era de CIE, la bandera de población de D3 y la bandera de D8 (`ends_before_6h`). Siguen siete verificaciones agregadas (Q-T16a a Q-T16g). Ejecutar el script completo en una sola conexión (DBeaver: Alt+X); la tabla es persistente, así que las verificaciones se pueden repetir solas.

**Unidad de análisis (tarea T17 del plan, escrita el 29/10/2026, aún sin ejecutar).** `sql/00_mimic_layer/01_unit_of_analysis.sql` (versión en español: `01_unit_of_analysis_es.sql`) crea `mimiciv.unit_of_analysis_v2`, una fila por admisión de `cohort_obstetric_v2` y ninguna columna del desenlace: es el adaptador de MIMIC-IV de la etapa E5 del framework (ver `framework_es.md`). Trae las columnas del contrato (`unit_id`, `group_id`, `t0`, `t_pred` = ingreso + 6 h, `t_end`), el periodo (era CIE, grupo de año ancla), el orden de las admisiones, el intervalo con la anterior y las cadenas de embarazo para intervalos de 30, 90 y 180 días. Siete verificaciones agregadas (Q-T17a a Q-T17g) reproducen las cifras de la auditoría de conteos y la consistencia con la tabla de etiqueta; necesitan `fetal_death_label_v2` (T16). Ejecútelo como un script completo en una sola conexión (DBeaver: Alt+X).

**Auditoría de conteos, grupo G (tarea T45, escrita el 17/11/2026, aún sin ejecutar).** `sql/02_audit_counts/audit_counts_event_timing.sql` (versión en español: `audit_counts_event_timing_es.sql`) cuenta los proxies que podrían ubicar cada evento de muerte fetal en el tiempo (código de muerte intrauterina, código de muerte fetal como diagnóstico principal, valores de laboratorio del estudio y mifepristona o misoprostol con su hora, procedimiento de parto el día del ingreso) y propone clases temporales. Prepara los criterios C1 y C2 de la puerta de clasificación (etapa E3 del framework, puerta P1). Solo lectura; necesita `fetal_death_label_v2` (T16). Ejecútelo como un script completo en una sola conexión (DBeaver: Alt+X); Q-G3 y Q-G4 pueden tardar unos minutos.

**Auditoría de conteos (tarea T08 del plan, ejecutada el 28/10/2026).** `sql/02_audit_counts/audit_counts.sql` (versión en español: `audit_counts_es.sql`) trabaja sobre las tablas revisadas del proyecto materno (`cohort_obstetric_v2`, `hadm_delivery_v2`, `obstetric_dx_v2`, `predictors_24h_v2`). Es de solo lectura (tablas temporales y SELECT, salida agregada) y cubre los grupos A–D del plan: conteos base, eventos y definición, solapamiento de pacientes y mismo embarazo, época y codificación. Se ejecuta como un solo script completo en una conexión (DBeaver: Alt+X); cada resultado empieza con una columna `q` que coincide con el identificador de la hoja *Conteos* del Excel de seguimiento. La etiqueta es provisional (los 13 patrones de código heredados) hasta la tabla verificada de códigos de la tarea T15; Q-C5 se calcula en el notebook de la tarea T13.

**Auditoría de conteos, grupo E (tarea T20, ejecutada el 28/10/2026).** `sql/02_audit_counts/audit_counts_timing.sql` (versión en español: `audit_counts_timing_es.sql`) trabaja sobre la población decidida en D3 y mide la duración de la estancia, los eventos perdidos en cada punto de predicción candidato y el momento del primer valor de laboratorio, el ingreso a UCI, el registro en urgencias y los procedimientos de parto, en eventos y no eventos. Cierra D6 a D8. Se ejecuta igual; Q-E3b lee `labevents` y puede tardar unos minutos. El grupo F es un script aparte.

Los cuatro scripts migrados de abajo todavía parten de la tabla materna antigua `cohort_smm_dataset`; el plan de análisis (sección 6) los reemplaza por scripts sobre la cohorte revisada. Su orden, si los ejecutas tal como están, cada uno como script completo en una sola conexión (DBeaver: Alt+X), después de construir las tablas previas del proyecto materno:

| Orden | Script | Qué hace |
|---|---|---|
| 1 | `sql/perinatal_feasibility_es.sql` | Cuenta las admisiones que tienen un código de muerte fetal (solo lee; tablas temporales) |
| 2 | `sql/fetal_death_dataset_es.sql` | Construye `mimiciv.fetal_death_code_patterns` y `mimiciv.cohort_fetal_death_dataset` (desenlace estricto/parcial, versión de ICD, semanas de gestación) |
| 3 | `sql/perinatal_feature_discovery_es.sql` | Explora qué predictores adicionales existen, con qué frecuencia y si difieren según el desenlace (solo lee) |
| 4 | `sql/fetal_death_features_es.sql` | Construye `mimiciv.cohort_fetal_death_dataset_ext` (antecedentes, hemograma y panel de las primeras 24 h, mediciones ambulatorias) |

Los scripts 1 y 3 solo leen datos y no son necesarios para construir las tablas; el 2 debe ir antes del 3 y del 4. Los scripts sin sufijo son los originales en inglés y los `_es` tienen el mismo código.

Cada script SQL debe tener una versión en español con el mismo nombre más el sufijo `_es` (por ejemplo `fetal_death_dataset.sql` y `fetal_death_dataset_es.sql`). Las sentencias son idénticas; solo se traducen los comentarios. El script sin sufijo es el original (en inglés). Se comprueba con:

```powershell
python scripts/check_sql_pair.py sql
```

## Requisitos previos

Este proyecto lee tablas que construye el proyecto hermano **MaternalMortality_MIMIC-IV** en la misma base de datos: `mimiciv.cohort_smm_dataset` y `mimiciv.pregnancy_diagnoses_expanded` (sus scripts `sql/01` a `sql/03`). Constrúyelas primero siguiendo el README de ese proyecto. No ejecutes dos contenedores de PostgreSQL sobre el mismo directorio de datos: si el contenedor del proyecto materno ya está corriendo, conéctate a ese y no levantes el `docker-compose.yml` de este proyecto.

## Instalación y ejecución

1. **Obtén acceso con credenciales a MIMIC-IV** (ver [Acceso a los datos](#acceso-a-los-datos)) y cárgalo localmente como se explica en el proyecto materno.
2. **Configura tus credenciales:** copia `.env.example` a `.env` en la raíz del proyecto y completa la contraseña de tu base de datos local (los mismos valores del proyecto materno). `.env` está en `.gitignore` y nunca debe subirse.
3. **Abre el proyecto en VS Code:** `Archivo > Abrir área de trabajo desde archivo...` y elige `PerinatalMortality_MIMIC-IV.code-workspace`. VS Code sugerirá las extensiones recomendadas.
4. **Crea un entorno e instala las dependencias:**
   ```powershell
   cd PerinatalMortality_MIMIC-IV
   python -m venv .venv
   .venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
   pip install -r requirements.txt
   ```
   Selecciona `.venv` como intérprete y como kernel de Jupyter.
5. **Sigue el plan de análisis.** Los cuatro scripts migrados y el notebook exploratorio son el material de partida: el plan los reemplaza paso a paso (etiquetas, auditoría de conteos y predictores sobre la cohorte materna revisada). No los uses como pipeline final; sigue el orden de tareas del Excel de seguimiento.

## Acceso a los datos

Este repositorio **no** incluye datos a nivel de paciente. Todos los análisis usan la base **MIMIC-IV**, disponible en [PhysioNet](https://physionet.org/content/mimiciv/) con acceso por credenciales. Para reproducir este trabajo debes:

1. Completar el curso CITI "Data or Specimens Only Research".
2. Firmar el acuerdo de uso de datos de salud con credenciales de PhysioNet.
3. Solicitar y obtener acceso a MIMIC-IV, y descargar tu propia copia.

Referencia: Johnson, A.E.W. et al. *MIMIC-IV, a freely accessible electronic health record dataset.* Scientific Data **2023**, 10, 1. https://doi.org/10.1038/s41597-022-01899-x

## Licencia

El código se publica bajo la licencia MIT (ver `LICENSE`).

## Contacto

Emmanuel Gutiérrez Jiménez — emmanuelg@uninorte.edu.co
