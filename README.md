# Fetal death in MIMIC-IV (model M3)

> **Framework.** This repository applies the staged framework for clinical prediction models of the thesis. The framework (stages, gates, criteria and literature) and the catalogue of models with their status are in [StagedFramework_ClinicalPrediction](https://github.com/Tesis-Doctoral/StagedFramework_ClinicalPrediction).

Can fetal death be predicted in the delivery hospitalizations of MIMIC-IV? The outcome is the part of perinatal mortality that happens before birth, identified with the mother's ICD codes (MIMIC-IV does not link mother and newborn, so early neonatal deaths are not captured). The notebooks follow the framework stage by stage and gate by gate, at two prediction points:

1. **Admission + 6 hours.** The count audit found that 73 of the 129 fetal deaths (56.6%) were already present at that point, so stage S6 stopped the model before fitting it: it would have failed criterion C1.
2. **Return R3: antenatal prediction.** Only with information recorded at least 7 days before the admission. The model is feasible in the data (99 of 129 events have earlier information), but the sample size gate G3 does not pass: the cross-validated Cox-Snell R² is negative (−0.00221).

> **Status: classified as a feasibility analysis.** With the information MIMIC-IV records before the admission, fetal death cannot be predicted. Stages S8 to S10 and gate G4 are not carried out.

[Versión en español](README_es.md)

## Order of execution

Each notebook has an English version (no suffix) and a Spanish one (`_es`) with the same code; only the language of the outputs changes. Each section starts with the code of the stage or gate, a short description and a result → action table, and its output ends with the decision taken. Each notebook ends with a summary.

| Order | Notebook | Stages and gates | Tables of the `mimiciv` schema it builds or checks | Output |
|---|---|---|---|---|
| 1 | `notebooks/01_outcome_definition.ipynb` | S1 · S2 · S3 · G1 | `fetal_death_code_patterns_v2`, `fetal_death_label_v2` | `data/outputs_01_outcome_definition.txt` |
| 2 | `notebooks/02_count_audit.ipynb` | S4 | none (read-only) | `data/outputs_02_count_audit.txt` |
| 3 | `notebooks/03_unit_and_prediction_point.ipynb` | S5 · S6 → return R3 | `unit_of_analysis_v2` | `data/outputs_03_unit_and_prediction_point.txt` |
| 4 | `notebooks/04_antenatal_count_audit.ipynb` | R3 · S2 · S3 · G1 · S4 | `antenatal_obstetric_universe`, `antenatal_fetal_death_label` | `data/outputs_04_antenatal_count_audit.txt` |
| 5 | `notebooks/05_antenatal_predictors.ipynb` | S5 · S6 · S7 · G2 | `antenatal_predictors_v1` | `data/outputs_05_antenatal_predictors.txt` |
| 6 | `notebooks/06_sample_size_gate.ipynb` | G3 · class · S11 | none | `data/outputs_06_sample_size_gate.txt` |

The notebooks run the scripts of `sql/` in one connection, as DBeaver does with Alt+X. Tables of the `mimiciv` schema that already exist are read as they are and only their checks run; a missing table is built from its script. To rebuild it, set **`REBUILD = True`** in the first code cell of the notebook. The outputs `data/outputs_*.txt` are in English (the documents cite them); the Spanish notebooks also write a copy `data/outputs_*_es.txt`.

Reference counts to be reproduced (gate G1): 25,736 obstetric admissions of 15,084 patients; 19,440 admissions in the population of the model, of 13,735 patients; 129 strict events and 142 with partial codes.

## Documents

| Document | Content |
|---|---|
| [`count_audit.md`](count_audit.md) | Count audit of the prediction point at admission (groups A to E) and decisions D1 to D8 |
| [`count_audit_antenatal.md`](count_audit_antenatal.md) | Audit of the information available before the admission (return R3) |
| [`predictor_table_antenatal.md`](predictor_table_antenatal.md) | Check of the antenatal predictor table |
| [`docs/outcome_card_fetal_death.md`](docs/outcome_card_fetal_death.md) | Outcome card, prediction point at admission + 6 h |
| [`docs/outcome_card_antenatal.md`](docs/outcome_card_antenatal.md) | Outcome card, return R3 (antenatal prediction) |
| [`docs/tripod_ai_fetal_mimic.md`](docs/tripod_ai_fetal_mimic.md) | TRIPOD+AI checklist (reduced: feasibility analysis, no model fitted) |
| [`analysis_plan.md`](analysis_plan.md) | Analysis plan (decisions D1 to D14) |
| [StagedFramework_ClinicalPrediction](https://github.com/Tesis-Doctoral/StagedFramework_ClinicalPrediction) | Staged framework applied (single current version; no local copy) |

Each document has a Spanish version with the same name plus `_es`.

## Prerequisites

- A local PostgreSQL database with MIMIC-IV v3.1 (schema `mimiciv`).
- The tables of the revised obstetric cohort: `cohort_obstetric_v2`, `hadm_delivery_v2`, `obstetric_dx_v2` and `predictors_24h_v2` (notebooks 01 to 03). Return R3 (notebooks 04 to 06) builds its own universe from the MIMIC-IV tables and does not depend on them.
- Copy `.env.example` to `.env` at the project root and fill in the password of the local database. `.env` is never committed.
- Python environment:
  ```powershell
  python -m venv .venv
  .venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
  pip install -r requirements.txt
  ```
  Select `.venv` as interpreter and Jupyter kernel.

## Repository structure

```
notebooks/                 The six notebooks, in framework order (EN and _es)
sql/00_mimic_layer/        Unit of analysis (S5): unit_of_analysis_v2
sql/01_labels/             Verified code catalogue and label by admission (S3)
sql/02_audit_counts/       Count audit at admission: groups A-D, E (prediction point) and G (event timing); read-only
sql/03_antenatal/          Return R3: universe, label, information before the admission and predictor table
libraries/                 database.py (connection), sql_runner.py (runs the scripts), presentation.py and i18n (EN/ES tables),
                           antenatal_design.py (design matrix of the 27 parameters)
scripts/check_sql_pair.py  Checks that each SQL script and its _es version have the same code
data/                      Only aggregate outputs outputs_*.txt and the group tables *_groups.xlsx
docs/                      Outcome cards
legacy/                    Material from before the framework, kept only as reference
```

Each SQL script has a Spanish version with the `_es` suffix and the same code (`python scripts/check_sql_pair.py sql`).

## Data access

This repository does **not** include patient-level data. MIMIC-IV is available on [PhysioNet](https://physionet.org/content/mimiciv/) to credentialed users (CITI training and the PhysioNet data use agreement). Only aggregate outputs are published; no `subject_id`, `hadm_id` or patient-level row, and counts from 1 to 4 are shown as "<5".

Reference: Johnson, A.E.W. et al. *MIMIC-IV, a freely accessible electronic health record dataset.* Scientific Data **2023**, 10, 1. https://doi.org/10.1038/s41597-022-01899-x

## License

The code is released under the MIT license (see `LICENSE`).

## Contact

Emmanuel Gutiérrez Jiménez — emmanuelg@uninorte.edu.co
