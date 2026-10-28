# Modelos de muerte perinatal (componente fetal) en MIMIC-IV

Modelos de predicción de la **muerte perinatal** en admisiones obstétricas de MIMIC-IV, empezando por el **componente de muerte fetal** identificado a partir de los códigos ICD de la madre (el "Modelo C" de la tesis). Este proyecto continúa el trabajo exploratorio hecho dentro de `MaternalMortality_MIMIC-IV`, que se conserva en [`legacy/`](legacy/) hasta que se migre.

> **Estado: migración terminada, aún sin ejecutar.** Las carpetas, la configuración, el plan de análisis, los cuatro scripts SQL (con sus versiones `_es`), las consultas de los conjuntos de datos en `libraries/database.py` y el notebook de modelado están listos. Nada de este repositorio se ha ejecutado en su nueva ubicación.

[English version](README.md)

## Alcance

- **Desenlace:** muerte fetal desde las 22 semanas completas de gestación (período perinatal de la OMS / ICD-10), identificada a partir de los códigos ICD-9-CM e ICD-10-CM de la madre (una definición *estricta* y una *parcial* que añade los embarazos múltiples en los que murieron solo algunos fetos).
- **Limitación de los datos:** MIMIC-IV no tiene un vínculo madre–recién nacido validado, por lo que las muertes neonatales tempranas (que están en el registro del recién nacido) **no** se capturan.
- **Población:** admisiones obstétricas de la cohorte materna de `MaternalMortality_MIMIC-IV`.
- **Regla contra la fuga de información:** un predictor debe conocerse al llegar o antes, o medirse en las primeras 24 horas; no se usan diagnósticos, procedimientos, DRG ni tratamientos de la misma admisión, porque los genera el propio evento.

El plan de análisis (versión 2, 28/10/2026) está en [`analysis_plan_es.md`](analysis_plan_es.md) (inglés: [`analysis_plan.md`](analysis_plan.md)). Sigue el proyecto materno: una auditoría de conteos y las decisiones sobre cohorte, unidad de análisis y punto de predicción van antes de cualquier modelo. El avance se sigue tarea por tarea en el Excel local `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (no versionado).

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

Estos cuatro scripts migrados todavía parten de la tabla materna antigua `cohort_smm_dataset`; el plan de análisis (sección 6) los reemplaza por scripts sobre la cohorte revisada. Su orden, si los ejecutas tal como están, cada uno como script completo en una sola conexión (DBeaver: Alt+X), después de construir las tablas previas del proyecto materno:

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
