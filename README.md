# Perinatal Death (Fetal Component) Models in MIMIC-IV

Prediction models for **perinatal death** in obstetric admissions of MIMIC-IV, starting with the **fetal-death component** identified from the mother's ICD codes (the "Modelo C" of the thesis). This project is the continuation of the earlier exploratory work done inside `MaternalMortality_MIMIC-IV`, which is kept in [`legacy/`](legacy/) as a reference.

> **Status: migration finished; the new SQL scripts are being run one by one.** Run so far: the verified code table (T15), the count audit (T08, T20) and the label by admission (T16). Written and waiting to be run: the unit of analysis (T17). The four migrated scripts in `sql/`, the dataset queries in `libraries/database.py` and the modelling notebook have not been run in their new location.

[Versión en español](README_es.md)

## Scope

- **Outcome:** fetal death from 22 completed weeks (WHO / ICD-10 perinatal period), identified from the mother's ICD-9-CM and ICD-10-CM codes (a *strict* definition and a *partial* one that adds multiple pregnancies where only some fetuses died).
- **Limitation of the data:** MIMIC-IV has no validated mother–newborn linkage, so early neonatal deaths (which live in the newborn's record) are **not** captured.
- **Population:** obstetric admissions of the maternal cohort of `MaternalMortality_MIMIC-IV`.
- **Rule against leakage:** a predictor must be known at or before arrival, or measured in the first 24 hours; diagnoses, procedures, DRG codes and treatments of the same admission are not used because the event itself produces them.

The analysis plan (version 2, 2026-10-28) is in [`analysis_plan.md`](analysis_plan.md) (Spanish: [`analysis_plan_es.md`](analysis_plan_es.md)). It follows the maternal project: a count audit and the decisions on cohort, unit of analysis and prediction point come before any model. Progress is tracked task by task in the local workbook `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (not versioned).

The count audit is written up in [`count_audit.md`](count_audit.md) (Spanish: [`count_audit_es.md`](count_audit_es.md)): what each count measured, what it settled and what is still open.

The staged framework (version 1.0, aligned with the SMM article: stages S1–S11, gates G1–G4, returns R1–R4) is in [`framework.md`](framework.md) (Spanish: [`framework_es.md`](framework_es.md)); the outcome card of this project is [`docs/outcome_card_fetal_death.md`](docs/outcome_card_fetal_death.md). The mockup of 2026-10-29 is kept in `docs/backup_framework_v0.1/`. The sensitivity analyses of the plan are numbered SA1–SA11.

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

**Verified code catalogue (plan task T15, run on 2026-10-28).** `sql/01_labels/01_fetal_death_codes_official.sql` (Spanish: `01_fetal_death_codes_official_es.sql`) creates `mimiciv.fetal_death_code_patterns_v2`: every fetal-death code pattern with its official title, its tier (strict, partial or excluded) and its source, plus five aggregate checks (Q-T15a to Q-T15e). It replaces the 13 provisional patterns of the legacy scripts; the codes themselves do not change, but early fetal death (O02.1, 632) and newborn-record codes (P95, 768.0, 768.1) are now listed as explicitly excluded. Run it as one whole script in one connection (DBeaver: Alt+X).

**Label by admission (plan task T16, run on 2026-10-29).** `sql/01_labels/02_fetal_death_label_by_admission.sql` (Spanish: `02_fetal_death_label_by_admission_es.sql`) creates `mimiciv.fetal_death_label_v2`, one row per admission of `cohort_obstetric_v2`, built from the verified code table. Besides the main label (strict code, decision D5) it carries, as columns and not as filters, the tier of the event, the code families, the position of the code, the early-loss and newborn-record flags, the gestational weeks from Z3A codes, the ICD era, the population flag of D3 and the flag of D8 (`ends_before_6h`). Seven aggregate checks (Q-T16a to Q-T16g) follow. Run it as one whole script in one connection (DBeaver: Alt+X); the table is persistent, so the checks can be re-run alone.

**Unit of analysis (plan task T17, written on 2026-10-29, not yet run).** `sql/00_mimic_layer/01_unit_of_analysis.sql` (Spanish: `01_unit_of_analysis_es.sql`) creates `mimiciv.unit_of_analysis_v2`, one row per admission of `cohort_obstetric_v2` and no outcome column: it is the MIMIC-IV adapter of stage S5 of the framework (see `framework.md`). It carries the contract columns (`unit_id`, `group_id`, `t0`, `t_pred` = admission + 6 h, `t_end`), the period (ICD era, anchor-year group), the order of admissions, the gap to the previous one and the pregnancy chains for gaps of 30, 90 and 180 days. Seven aggregate checks (Q-T17a to Q-T17g) reproduce the figures of the count audit and the consistency with the label table; they need `fetal_death_label_v2` (T16). Run it as one whole script in one connection (DBeaver: Alt+X).

**Count audit, group G (task T45, written on 2026-11-17, not yet run).** `sql/02_audit_counts/audit_counts_event_timing.sql` (Spanish: `audit_counts_event_timing_es.sql`) counts the proxies that could place each fetal-death event in time (intrauterine-death code, fetal-death code as principal diagnosis, work-up laboratory values and mifepristone or misoprostol with their times, delivery procedure on the admission day) and proposes timing classes. It prepares criteria C1 and C2 of the classification gate (framework stage S3, gate G1). Read-only; needs `fetal_death_label_v2` (T16). Run it as one whole script in one connection (DBeaver: Alt+X); Q-G3 and Q-G4 can take a few minutes.

**Count audit (plan task T08, run on 2026-10-28).** `sql/02_audit_counts/audit_counts.sql` (Spanish: `audit_counts_es.sql`) works on the revised tables of the maternal project (`cohort_obstetric_v2`, `hadm_delivery_v2`, `obstetric_dx_v2`, `predictors_24h_v2`). It is read-only (temporary tables and SELECTs, aggregate output) and covers groups A–D of the plan: base counts, events and definition, patient overlap and same pregnancy, era and coding. Run it as one whole script in one connection (DBeaver: Alt+X); every result set starts with a column `q` that matches the identifier in the sheet *Conteos* of the tracking workbook. The label is provisional (the 13 legacy code patterns) until the verified code table of task T15; Q-C5 is computed in the notebook of task T13.

**Count audit, group E (task T20, run on 2026-10-28).** `sql/02_audit_counts/audit_counts_timing.sql` (Spanish: `audit_counts_timing_es.sql`) works on the population decided in D3 and measures length of stay, events lost at each candidate prediction point, and the timing of the first laboratory value, ICU admission, emergency department registration and delivery procedures, for events and non-events. It settles D6 to D8. Same way of running; Q-E3b reads `labevents` and can take a few minutes. Group F is a separate script.

The four migrated scripts below still build on the old maternal table `cohort_smm_dataset`; the analysis plan (section 6) replaces them with scripts on the revised cohort. Their order, if you run them as they are, each as a whole script in one connection (DBeaver: Alt+X), after building the prerequisite tables of the maternal project:

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
