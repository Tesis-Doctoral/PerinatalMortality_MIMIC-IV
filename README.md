# Perinatal Death (Fetal Component) Models in MIMIC-IV

Prediction models for **perinatal death** in obstetric admissions of MIMIC-IV, starting with the **fetal-death component** identified from the mother's ICD codes (the "Modelo C" of the thesis). This project is the continuation of the earlier exploratory work done inside `MaternalMortality_MIMIC-IV`, which is kept in [`legacy/`](legacy/) as a reference.

> **Status: migration finished, not yet run.** The folders, configuration, analysis plan, the four SQL scripts (with `_es` versions), the dataset queries in `libraries/database.py` and the modelling notebook are in place. Nothing in this repository has been run in its new location.

[Versión en español](README_es.md)

## Scope

- **Outcome:** fetal death from 22 completed weeks (WHO / ICD-10 perinatal period), identified from the mother's ICD-9-CM and ICD-10-CM codes (a *strict* definition and a *partial* one that adds multiple pregnancies where only some fetuses died).
- **Limitation of the data:** MIMIC-IV has no validated mother–newborn linkage, so early neonatal deaths (which live in the newborn's record) are **not** captured.
- **Population:** obstetric admissions of the maternal cohort of `MaternalMortality_MIMIC-IV`.
- **Rule against leakage:** a predictor must be known at or before arrival, or measured in the first 24 hours; diagnoses, procedures, DRG codes and treatments of the same admission are not used because the event itself produces them.

The analysis plan (version 2, 2026-10-28) is in [`analysis_plan.md`](analysis_plan.md) (Spanish: [`analysis_plan_es.md`](analysis_plan_es.md)). It follows the maternal project: a count audit and the decisions on cohort, unit of analysis and prediction point come before any model. Progress is tracked task by task in the local workbook `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (not versioned).

## Repository structure

```
sql/                        SQL scripts of this project, each with its _es version (see "SQL scripts" below)
notebooks/                  01_fetal_death_models.ipynb (hold-out, patient-grouped cross-validation, feature-block ablation, sensitivity analyses, SHAP)
libraries/
  database.py               Connection to the MIMIC-IV PostgreSQL database (environment variables) and the two queries that load the fetal-death datasets
  functions.py              Small statistics helper
scripts/
  check_sql_pair.py         Checks that every SQL script and its _es version have identical code
data/                       Category-group tables *_groups.xlsx (lookup only) and aggregate outputs outputs_*.txt (counts and metrics only); nothing else is tracked
docs/                       Reporting documents (TRIPOD+AI checklist, supplementary tables), the tracking workbook (local) and backup_plan_v1/
legacy/                     Original copies of the earlier material, kept only as a reference (see legacy/README.md)
docker-compose.yml          Optional local PostgreSQL + Jupyter environment
requirements.txt  .env.example  LICENSE
.vscode/                    Shared VS Code settings and recommended extensions
PerinatalMortality_MIMIC-IV.code-workspace
```

## SQL scripts

These four migrated scripts still build on the old maternal table `cohort_smm_dataset`; the analysis plan (section 6) replaces them with scripts on the revised cohort. Their order, if you run them as they are, each as a whole script in one connection (DBeaver: Alt+X), after building the prerequisite tables of the maternal project:

| Order | Script | What it does |
|---|---|---|
| 1 | `sql/perinatal_feasibility.sql` | Counts the admissions that carry a fetal-death code (reads only; temporary tables) |
| 2 | `sql/fetal_death_dataset.sql` | Builds `mimiciv.fetal_death_code_patterns` and `mimiciv.cohort_fetal_death_dataset` (outcome strict/partial, ICD version, gestational weeks) |
| 3 | `sql/perinatal_feature_discovery.sql` | Explores which extra predictors exist, how often, and whether they differ by outcome (reads only) |
| 4 | `sql/fetal_death_features.sql` | Builds `mimiciv.cohort_fetal_death_dataset_ext` (history, first-24 h blood count and panel, outpatient measurements) |

Scripts 1 and 3 only read data and are not required to build the tables; 2 must precede 3 and 4.

Every SQL script must have a Spanish version with the same name plus the suffix `_es` (for example `fetal_death_dataset.sql` and `fetal_death_dataset_es.sql`). The statements are identical; only the comments are translated. The script without suffix is the original (English). Check it with:

```powershell
python scripts/check_sql_pair.py sql
```

## Prerequisites

This project reads tables that are built by the companion project **MaternalMortality_MIMIC-IV** in the same database: `mimiciv.cohort_smm_dataset` and `mimiciv.pregnancy_diagnoses_expanded` (its `sql/01` to `sql/03` scripts). Build them first, following the README of that project. Never run two PostgreSQL containers on the same data directory: if the maternal project's container is already running, connect to it and do not start this project's `docker-compose.yml`.

## Installation and execution

1. **Get credentialed access to MIMIC-IV** (see [Data access](#data-access)) and load it locally as described in the maternal project.
2. **Set your credentials:** copy `.env.example` to `.env` in the project root and fill in your local database password (the same values as in the maternal project). `.env` is git-ignored and must never be committed.
3. **Open the project in VS Code:** `File > Open Workspace from File...` and choose `PerinatalMortality_MIMIC-IV.code-workspace`. VS Code will suggest the recommended extensions.
4. **Create an environment and install dependencies:**
   ```powershell
   cd PerinatalMortality_MIMIC-IV
   python -m venv .venv
   .venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
   pip install -r requirements.txt
   ```
   Select `.venv` as the interpreter and as the Jupyter kernel.
5. **Follow the analysis plan.** The four migrated scripts and the exploratory notebook are the starting material: the plan replaces them step by step (labels, audit counts and predictors on the revised maternal cohort). Do not use them as a final pipeline; follow the task order of the tracking workbook.

## Data access

This repository does **not** include any patient-level data. All analyses use the **MIMIC-IV** database, available through [PhysioNet](https://physionet.org/content/mimiciv/) under credentialed access. To reproduce this work you must:

1. Complete the CITI "Data or Specimens Only Research" training course.
2. Sign the PhysioNet Credentialed Health Data Use Agreement.
3. Request and be granted access to MIMIC-IV, and download your own copy.

Reference: Johnson, A.E.W. et al. *MIMIC-IV, a freely accessible electronic health record dataset.* Scientific Data **2023**, 10, 1. https://doi.org/10.1038/s41597-022-01899-x

## License

The code is released under the MIT License (see `LICENSE`).

## Contact

Emmanuel Gutiérrez Jiménez — emmanuelg@uninorte.edu.co
