# Analysis plan — fetal-death models, MIMIC-IV (version 2)

Working document, written on 2026-10-28 after the migration of the legacy material. It follows the design of the revised maternal project (`MaternalMortality_MIMIC-IV`, manuscript healthcare-4661619): a **count audit before any model**, a cohort without patient overlap between training and evaluation, a fixed prediction time, nested patient-grouped validation, and sensitivity analyses that include the question of whether same-admission diagnoses may be used.

Items marked **[decision]** are open; they are listed in section 5 and in the sheet *Decisiones* of the tracking workbook `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (local file, not versioned). Figures labelled *legacy* come from the exploratory scripts migrated from `legacy/` and **must be re-verified** with the audit before they are quoted anywhere. Spanish version: [`analysis_plan_es.md`](analysis_plan_es.md). The first version of this plan is kept in `docs/backup_plan_v1/`.

## 1. Purpose and framing

- Evaluate whether the framework of the maternal project (count audit, patient-grouped validation, recalibration, TRIPOD+AI reporting) carries over to a new outcome without leakage: **fetal death identified from the mother's ICD codes**.
- The outcome is a **proxy**: there is no chart review and no mother–newborn linkage in MIMIC-IV, so early neonatal deaths are not captured. Every document must say *fetal death*, not *perinatal death*.
- The earlier notebook (`notebooks/01_fetal_death_models.ipynb`) is **exploratory**: one 80/20 hold-out, cross-validation without nested tuning, a predictor set chosen after looking at the whole dataset. It is kept as a reference and is superseded by the notebooks of section 6.
- The status of the work (full model, or feasibility analysis only) is decided after the audit and the sample-size calculation (**D12**), as was done for maternal mortality.

## 2. Starting point

**D1 (decided 2026-10-28): the cohort is built on the revised tables of the maternal project**, not on the old `cohort_smm_dataset`. The revised tables fix problems the legacy scripts inherited: the original delivery flag only recognised ICD-10 codes, so ICD-9 deliveries could never be flagged (the revised flag added 10,584 deliveries in the maternal audit; the legacy feasibility script, Query 9, was written to check the same problem for fetal-death events), and the predictor window had no fixed prediction time.

Prerequisites (built by `MaternalMortality_MIMIC-IV/sql/04_labels` and `sql/05_predictors`): `mimiciv.cohort_obstetric_v2` (universe), `mimiciv.hadm_delivery_v2` (delivery flag with `has_stillbirth_code` and `has_abortive_code`), `mimiciv.label_admission_v2`, `mimiciv.predictors_24h_v2`, `mimiciv.pregnancy_diagnoses_expanded`.

Reference numbers from the maternal audit (to confirm in Q-A1): 25,736 obstetric admissions, 15,084 patients, 6,793 patients (45.0%) with more than one admission, 19,425 delivery hospitalizations (of which 109 carry a stillbirth code), 19,383 delivery hospitalizations still in hospital 24 hours after admission.

How the maternal pieces map to this project (scripts to write are named in section 6; none is written yet):

| Maternal project | This project |
|---|---|
| `04_labels/01_smm_codes_official.sql` (verified code table) | verified fetal-death code table with sources (replaces `fetal_death_code_patterns`) |
| `04_labels/02_delivery_flag.sql`, `03_labels_same_admission.sql` | fetal-death label per admission on `cohort_obstetric_v2`, with strict/partial, gestational weeks and ICD version as columns, never as filters |
| `04_labels/04_cohort_obstetric_flags.sql` (rules as columns) | unit-of-analysis and same-pregnancy columns (admission, delivery, pregnancy chain, first admission) |
| `05_predictors/01_predictors_24h.sql`, `02_dictionary_missingness.sql` | extended predictors (history, CBC, panel, OMR) on the decided window, plus a predictor dictionary with coverage rule |
| `06_audit_counts/*` | `sql/02_audit_counts/` groups A–F (section 4) |
| Notebooks 01–07 | notebooks of section 6 |

## 3. Phases

| Phase | Content | Closes with |
|---|---|---|
| F0 · Base and decisions | project, migration, prerequisites checked, plan approved | D1–D3 settled, baseline commit |
| F1 · Cohort and count audit | counts A–D (base, events, patient overlap, era), notebook 01 | D3, D4, D5 settled with numbers |
| F2 · Outcome and labels | verified code table, label and unit columns on the revised cohort | label script + counts |
| F3 · Predictors and timing | counts E–F, prediction point, window, predictor dictionary | D6–D10 settled |
| F4 · Validation framework | sample size, models, nested patient-grouped validation, calibration | D11, D12 settled |
| F5 · Sensitivity analyses | S1–S10 (section 7) | one output file per analysis |
| F6 · Reporting | aggregate outputs, TRIPOD+AI, supplementary tables, manuscript or chapter | D13, D14 settled |

## 4. Count audit (before any model)

Read-only, aggregate output only; never publish rows with `subject_id` or `hadm_id`. Each count has an identifier (Q-…) used in the tracking workbook (sheet *Conteos*) and names the decision it informs.

**Principle: no overlap and no selection by outcome.** The cohort rules are measured as columns first and applied afterwards, so that each choice (unit, scope, definition) is made with numbers and reported with its sensitivity analysis.

| Group | Counts | Informs |
|---|---|---|
| **A · Base** | Q-A1 admissions, patients, deliveries, eligible deliveries; Q-A2 reconciliation of the legacy dataset with `cohort_obstetric_v2`; Q-A3 admissions per patient | D1, D4 |
| **B · Events and definition** | Q-B1 events by tier (strict, partial) and ICD version; Q-B2 events by scope (delivery, structured obstetric code, any); Q-B3 agreement with `has_stillbirth_code` and with ICD-9 deliveries; Q-B4 gestational weeks from Z3A codes (under 22, 22–27, 28 or more, no code); Q-B5 position of the code in the diagnosis list and events where it is the only obstetric code; Q-B6 fetal-death codes outside the obstetric universe; Q-B7 overlap with severe maternal morbidity and with maternal death in the same admission; Q-B8 co-occurrence with abortive or ectopic codes | D3, D5 |
| **C · Patient overlap** | Q-C1 events per patient; Q-C2 gap between consecutive admissions of the same patient, by event status (under 90, 90–179, 180–364, 365 or more days); Q-C3 event admissions that are not the first of the patient, and the gap to a prior event; Q-C4 events under each candidate unit (admission, delivery, pregnancy chain, first admission per patient); Q-C5 simulation of admission-level splitting: patients and event-bearing patients on both sides of a hold-out and of 5-fold CV | D4, D11 |
| **D · Era and coding** | Q-D1 events and rate per 1,000 deliveries by ICD version and anchor-year group; Q-D2 availability of gestational weeks by version; Q-D3 plausibility of the rate against published stillbirth rates (source to be looked up) | D3, D5 |
| **E · Eligibility and timing** | Q-E1 length of stay in events and non-events; Q-E2 eligibility at 24 hours by scope and events lost; Q-E3 time of first laboratory value, first ICU admission and ED arrival; Q-E4 delivery or induction procedure dates relative to admission + 24 h (procedure codes carry a date, diagnosis codes do not) | D6, D7, D8 |
| **F · Predictors** | Q-F1 availability by block (history, blood count, panel, outpatient) by event status, ICD version and scope; Q-F2 coverage rule (10% of the primary population); Q-F3 patients with no earlier admission and the effect on history flags; Q-F4 outpatient (OMR) records, coverage and timing; Q-F5 units and plausibility limits of the laboratory values; Q-F6 how many events carry an outcome-related code among the first four diagnoses (why same-admission diagnoses are excluded) | D9, D10 |

Legacy values to re-verify (they disagree with each other in one case): 154 events (136 strict only); 2 events with severe maternal morbidity and 0 maternal deaths among strict events; admissions after an earlier fetal-death admission (17, of them 5 events) are described as **under 90 days** in `fetal_death_features.sql` and as **within 180 days** in the notebook; prior fetal death at least 365 days earlier, 1 event in 78 admissions.

### Results of the count audit, groups A–D (run 2026-10-28)

Full figures are in the sheet *Conteos* of the tracking workbook. The provisional label reproduces the legacy dataset exactly (154 events, 136 strict, 0 discordant admissions) and the base counts match the maternal audit (25,736 admissions, 15,084 patients, 19,425 deliveries, 19,383 eligible at 24 h).

- **Events.** 154 admissions (148 patients): 127 in delivery hospitalizations (114 strict), 27 outside the delivery flag, 20 of them with an abortive, ectopic or molar code. Fifteen admissions carry a stillbirth code but not the delivery flag, and all 15 also carry an abortive code. No strict code lies outside the obstetric universe (Q-B6 empty). Rate: 5.87 strict per 1,000 delivery hospitalizations (national reference, NCHS, 20 weeks or more: 5.44 in 2024), but 4.05 for 28 weeks or more in ICD-10 admissions against 2.57 nationally.
- **Gestational age.** Z3A codes exist only in ICD-10 (8,844 of 19,425 deliveries). Among 69 strict ICD-10 events with weeks, 13 (19%) have fewer than 22 weeks, and 7 of those 13 are inside the delivery flag, so the flag does not remove pre-viable losses.
- **Patients.** 45.0% of patients have more than one admission; only 5 have more than one event admission. Of the 154 events, 61 (40%) are not the patient's first admission. Pregnancy-chain rules change the event count by at most 5 (150, 149, 149 events for 30, 90, 180 days). The 17 admissions after an earlier event admission are all under 90 days (none between 90 and 179), which settles the legacy contradiction.
- **Era.** ICD-9 covers about 2008–2014 and ICD-10 about 2014–2021, so version and calendar year are almost confounded. The rate rises from 5.2 (2008–10) to 12.9 (2020–22) per 1,000 deliveries (trend p = 0.007, computed by the assistant), and is 5.41 in ICD-9 against 7.88 in ICD-10.
- **Overlap with other outcomes.** 15 of 136 strict events have severe maternal morbidity (revised definition) and none has maternal death.
- **Counts for the sample-size check (D12).** 129 strict events among 19,440 admissions; the number at the chosen prediction point is pending (group E).

## 5. Decisions

Recommendations are mine; they are proposals until you record them in the workbook.

| ID | Decision | Options | Recommendation | When |
|---|---|---|---|---|
| D1 | Data base | Revised maternal tables; old cohort; both | **Decided:** revised maternal tables | 2026-10-28 |
| D2 | Name and status of the outcome | *Fetal death* (proxy); *perinatal death* | *Fetal death*, always labelled as a proxy | Before writing |
| D3 | Primary population | Delivery hospitalizations; any obstetric admission; admissions with a structured obstetric code | **Decided 2026-10-28:** delivery hospitalizations (v2 flag) plus admissions with a stillbirth code (Z37.1/.4/.7, V27.1/.4/.7), which the flag misses when an abortive code is also present: 19,440 admissions, 142 events (129 strict). Delivery flag alone and any obstetric admission as sensitivity | 2026-10-28 |
| D4 | Unit of analysis and same pregnancy | Admission; delivery; pregnancy chain (admissions linked by a gap rule); first admission per patient | **Decided 2026-10-28:** one record per delivery hospitalization, patient-grouped validation; pregnancy chain (gap of 90 days) as sensitivity; first admission per patient rejected (loses 40% of the events) | 2026-10-28 |
| D5 | Outcome definition | Strict; strict plus partial; with or without gestational check | **Decided 2026-10-28:** strict code at any gestational age as the main definition; strict plus partial, and the bands of 22 or more and 28 or more weeks (ICD-10 only) as sensitivity. The code list is verified in T15 | 2026-10-28 |
| D6 | Prediction point | Arrival; 24 h after admission (as SMM); retrospective classification | Decide with Q-E1, Q-E2, Q-E4. In the maternal data 19,383 of 19,425 deliveries remained at 24 h, so the loss is expected to be small; check it **for events** | After Q-E |
| D7 | Time zero and window | Admission time; earliest of ED registration and admission; window from 24 h before to 24 h after (maternal D10) | Same window as the maternal project unless Q-E3 shows a reason to change | After Q-E3 |
| D8 | Admissions that end before the prediction point | Exclude and report their events apart; include with missing predictors | Exclude and report apart (maternal D8) | After Q-E2 |
| D9 | Same-admission diagnoses | Out of every model; out of the main model with a retrospective sensitivity; in | Out of the main model; sensitivity S7 | After Q-F6 |
| D10 | Predictor selection | Pre-specified by time rule, clinical rationale and coverage; or chosen by outcome contrast | Pre-specified. Outcome contrast may be used only to **exclude** leaking tests (as with coagulation and LDH), never to include variables, unless done inside each training fold | After Q-F |
| D11 | Models and imbalance | Stacked ensemble plus logistic regression; regularised logistic regression only; resampling | Penalised logistic regression as reference and primary candidate; ensemble compared in the same folds; no SMOTE; class weights only as a grid option | After the sample-size check |
| D12 | Model or feasibility analysis | Full model; descriptive analysis plus a simple pre-specified model | Decide with the Riley et al. criteria and the final number of events | After Q-C4 and sample size |
| D13 | Aggregate outputs and small cells | Publish outputs; rule for small counts | Publish aggregates; replace counts under 5 by “<5” in published files | Before the first commit of outputs |
| D14 | Destination | Thesis chapter; article; both | Decide with the supervisor; sets the reporting format | Before F6 |

## 6. Validation, notebooks and scripts

**Validation (as in notebook 02 of the maternal project).** Splits grouped by patient (`StratifiedGroupKFold`), 5 outer folds repeated 3 times, inner grouped folds for tuning, imputation, scaling, stacking and recalibration fitted inside the training part. Metrics: AUROC, AUPRC with the prevalence, Brier score, calibration slope and intercept, observed/expected, decision curve; cluster (patient-level) bootstrap intervals. Sample size with the criteria of Riley et al. before modelling; report how many parameters the events can support.

**Notebooks (proposed names, none written yet).**

| Notebook | Content | Maternal analogue |
|---|---|---|
| `01_patient_overlap` | admission-level splitting: patients and event-bearing patients on both sides | 01 |
| `02_grouped_validation_fetal_death` | main model, nested patient-grouped validation, calibration, decision curve | 02 |
| `03_resampling_comparison` | no correction, class weights, SMOTENC (only if D11 allows) | 03 |
| `04_availability_indicators` | with and without the availability indicators of blood count, panel and OMR | 04 |
| `05_era_temporal_validation` | calendar era, ICD version, temporal validation | 05 |
| `06_same_admission_diagnoses` | retrospective sensitivity with diagnosis groups excluding the outcome codes (S7) | new |
| `07_timing_vs_prediction_point` | events placed in time with procedure dates | 07 |

The current `01_fetal_death_models.ipynb` is renamed `00_exploratory_fetal_death_models.ipynb` once the new notebooks exist.

**SQL scripts (proposed, each with its `_es` version).** `sql/01_labels/` (verified code table; label and unit columns), `sql/02_audit_counts/` (groups A–F; `audit_counts.sql` for A–D was run on 2026-10-28, `audit_counts_timing.sql` for E is written and verified, not yet run, task T20; F is a separate script), `sql/03_predictors/` (window, blocks, dictionary, missingness). The four migrated scripts stay in `sql/` until replaced: the feasibility script is superseded by the audit, the dataset and feature scripts are rebuilt on the revised cohort, and the feature-discovery script stays as exploratory evidence.

## 7. Sensitivity analyses

| ID | Analysis | Question |
|---|---|---|
| S1 | Strict-only outcome | Do partial codes (multiple pregnancy) change the result? |
| S2 | ICD-10 admissions only; gestational age of at least 22 weeks where known | Does the 22-week definition hold? |
| S3 | One record per patient or per pregnancy | Does patient overlap or repeated pregnancy inflate performance? |
| S4 | Scope: delivery, structured obstetric code, any obstetric admission | Does the population change the result? |
| S5 | With and without outpatient (OMR) features; with and without availability indicators | Does the model learn who was tested rather than physiology? |
| S6 | Calendar era, ICD version, temporal validation | Does the model learn the period? |
| S7 | **Same-admission diagnoses used or not** | How much apparent performance comes from information the event produces? Reported as retrospective classification, never as prediction |
| S8 | Excluding events that also have severe maternal morbidity or maternal death | Does overlap with the maternal outcomes matter? |
| S9 | Resampling comparison (optional) | Does resampling help? |
| S10 | Late stillbirth: gestational age of 28 weeks or more, ICD-10 admissions only | Does the result hold at the WHO threshold used for international comparison? |

**S7 in detail.** Main model: no diagnosis of the same admission (the outcome is defined by diagnoses). Sensitivity: add diagnosis-group indicators of the same admission with the outcome codes and their direct companions removed, and report the change in AUROC and AUPRC as the part of performance that comes from information produced by the event. Diagnoses of **earlier** admissions (history) stay in the main model.

## 8. Reporting

TRIPOD+AI checklist in `docs/` (with `_es`); aggregate outputs only in `data/outputs_*.txt` under D13; predictor dictionary, missingness tables and code lists as supplementary documents; every SQL script with its `_es` version and `python scripts/check_sql_pair.py sql` passing.

## 9. Risks stated in advance

- **Few events** (about 150 before any rule): wide intervals; the nested validation is the primary evidence and the feasibility option (D12) stays open.
- **Visibility bias in history features:** history exists only for patients with an earlier admission in the same hospital; absence is not a negative (Q-F3).
- **Selection by outcome in the exploratory phase:** the feature-discovery script compared event rates by feature on the whole dataset; D10 limits how that evidence may be used.
- **Era and coding:** gestational weeks exist only in ICD-10; ICD-9 events cannot be checked against the 22-week threshold.
- **Timing:** the diagnosis may be known on arrival; laboratory values in the window can already reflect the event (coagulation and LDH were excluded for this reason).
- **Proxy outcome and single centre:** no external validation; research code, not a clinical tool.

## 10. Order of work

Tracked task by task in the sheet *Plan de trabajo* (44 tasks, phases F0–F6). Gates: no model before D3–D5 are settled with the audit; no predictor table before D6–D8; no validation before the sample-size check (D12).
