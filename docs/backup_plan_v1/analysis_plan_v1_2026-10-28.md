# Analysis plan — perinatal death (fetal component) models, MIMIC-IV

Working document. Items marked **[decision]** are open and must be settled before the first run. Numbers quoted here come from the earlier exploratory scripts in `legacy/` and must be re-verified when those scripts are migrated.

## 1. Purpose

Build and evaluate prediction models for perinatal death using the obstetric admissions of MIMIC-IV, starting with the fetal-death component (the third model of the thesis, after maternal mortality and severe maternal morbidity). The first aim is to test whether the modelling framework of the maternal project (patient-grouped validation, recalibration, reporting under TRIPOD+AI) carries over to a new outcome without leakage.

## 2. Population

- Starting point: the 25,736 obstetric admissions of the maternal cohort (`mimiciv.cohort_smm_dataset`), so all models share one cohort.
- **[decision]** Final population: all obstetric admissions, or only delivery hospitalizations (as in the SMM model).
- **[decision]** Same-pregnancy rule: admissions within a set number of days after an earlier fetal-death admission of the same patient are dropped (the notebook uses the parameter `POST_EVENT_WINDOW_DAYS`).

## 3. Outcome

- Fetal death from 22 completed weeks, from the mother's ICD-9-CM and ICD-10-CM codes (table `mimiciv.fetal_death_code_patterns`). *Strict:* the code says the fetus died. *Partial:* multiple pregnancy where only some fetuses died.
- Pre-viable losses (abortion, ectopic pregnancy, missed abortion, ICD-9 630–639) are excluded: they fall below 22 weeks.
- The feasibility check found 154 admissions with the strict or partial definition (136 strict only). **[decision]** Main definition: strict, or strict plus partial.
- Early neonatal deaths are not captured (no validated mother–newborn linkage in MIMIC-IV), so the outcome must be named *fetal death*, not *perinatal death*, in every document.

## 4. Prediction time and leakage control

- A feature is eligible only if it is known at or before arrival (ED registration or admission, whichever is earlier), or measured in the first 24 hours from arrival.
- Not eligible: diagnoses, procedures, DRG codes, treatments and microbiology of the same admission (the event produces them), and coagulation tests and LDH (ordered after the diagnosis).
- **[decision]** Prediction time: at arrival, or at 24 hours (as in the SMM model, which would exclude events before 24 h and must be reported separately).
- Diagnosis-group indicators (`gdg_*`) are not used: they come from the same coded diagnoses that define the outcome.

## 5. Predictors

Blocks of the extended dataset (`mimiciv.cohort_fetal_death_dataset_ext`): admission attributes; history from earlier admissions of the same patient (hypertension, diabetes, obesity, renal disease, prior fetal death at least 365 days earlier); first blood count and chemistry panel in the first 24 hours; outpatient measurements of the 365 days before admission (blood pressure, weight, BMI). `gest_weeks` (from Z3A codes, ICD-10 only) and the strict/partial flags are metadata, not predictors.

## 6. Validation and analysis

Follows the revised maternal project:

- Splits grouped by patient (`StratifiedGroupKFold`); nested cross-validation repeated several times; imputation, scaling, tuning, stacking and recalibration fitted inside the training part of each fold.
- Models: regularized logistic regression, Random Forest, Extra Trees, XGBoost and a stacked ensemble with a logistic meta-learner.
- Metrics: AUROC, AUPRC with the prevalence, Brier score, calibration slope and intercept, observed/expected, decision curve; patient-level bootstrap intervals.
- Sample-size check with the criteria of Riley et al. before modelling. With about 150 events, the number of parameters the data can support must be reported.
- **[decision]** Whether to run the model at all if the criteria are not met, or to report it as a feasibility analysis only (as was done for maternal death).

## 7. Sensitivity analyses (proposed)

Strict-only outcome; ICD-10 admissions only (gestational weeks available); first admission per patient; with and without outpatient (OMR) features; calendar era and temporal validation.

## 8. Reporting

TRIPOD+AI checklist in `docs/`; aggregate outputs only in `data/outputs_*.txt` (counts and metrics, no identifiers); every SQL script with its `_es` version.

## 9. Order of work

1. ~~Migrate and review the SQL scripts in `legacy/sql` (feasibility, dataset, feature discovery, extended features), with `_es` versions.~~ Done on 2026-10-28 (`sql/`; code unchanged, comments updated; not yet run in this project).
2. Re-run the feasibility counts and settle the decisions above.
3. Build the datasets and run the notebook (migrated on 2026-10-28 as `notebooks/01_fetal_death_models.ipynb`), adding patient-grouped nested validation.
4. Sample-size check, models, calibration, sensitivity analyses.
5. Outputs, TRIPOD+AI checklist and manuscript.
