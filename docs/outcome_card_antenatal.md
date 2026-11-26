# Outcome card — antenatal prediction of fetal death, MIMIC-IV

Outcome card of the antenatal model, following the staged framework ([`../framework.md`](../framework.md)). Fields marked **pending** are fixed, and recorded in the decision log, before the gate that needs them. Spanish version: [`outcome_card_antenatal_es.md`](outcome_card_antenatal_es.md).

## 1. The question

When the woman arrives at the hospital, the fetal death has often already happened: a model using information from the admission would recognize it, but would not predict it. So this model asks the question before the admission: **with what was known about the woman before this admission, could a high risk of fetal death be seen?** Only information recorded before the admission enters the model, so the event happens after the information that predicts it.

## 2. Identity

| Field | Value |
|---|---|
| Outcome | Perinatal death before birth (fetal death or stillbirth), identified from the mother's ICD codes and always labelled a proxy |
| Rung | Ideal outcome (first rung of the outcome ladder) |
| Data source | MIMIC-IV v3.1 (section 7) |
| Unit and group | Delivery hospitalization; patient as grouping unit (partitions never split a patient) |
| Population | Delivery hospitalizations, plus admissions with a stillbirth code that were not flagged as deliveries: 19,440 admissions of 13,735 patients |
| Main label | Strict code of fetal death at any gestational age (ICD-10-CM O36.4, Z37.1, Z37.4, Z37.7; ICD-9-CM 656.4, V27.1, V27.4, V27.7): 129 events (0.66%) |
| Sensitivity labels | Strict plus partial (multiple pregnancies where some fetus died); 22 and 28 weeks or more (ICD-10 only, where gestational weeks exist); without early-loss codes |

## 3. Prediction point and information window (S6)

| Field | Value |
|---|---|
| Time zero and prediction point | Admission time of the delivery hospitalization |
| Information window | Everything recorded **at least 7 days before** the admission: earlier MIMIC-IV admissions discharged by then, outpatient measurements (OMR) and outpatient laboratory values dated by then |
| Why 7 days | A fetal death diagnosed at an outpatient visit is usually followed by an admission within days. A buffer keeps information recorded after the death out of the model. Sensitivity: 1 and 30 days (the audit lost only 3 events with information between them) |
| Current-pregnancy window | Measurements and laboratory values of the current pregnancy are taken **between 280 and 7 days before** the admission (about one pregnancy). Earlier values are not used; with no value in this window the predictor is missing, with its indicator |
| Also allowed | Patient attributes of the current admission that do not depend on how she arrived: age, race and ethnicity, insurance, language, marital status |
| Excluded | Anything of the current admission: diagnoses, procedures, laboratory values, admission type and admission location (they reflect how she presented, which the event itself can cause), emergency department data |

## 4. Predictors (S7), fixed with the count audit

Fixed on 2026-11-18 from the frequencies of the count audit (whole population, never split by outcome) and clinical reasons. **Absence of a record is not absence of the condition**: many women have no earlier encounter in this hospital, so the blocks carry indicators.

| Block | Predictors | Parameters | Source in the audit |
|---|---|---|---|
| Registration | Age (continuous); race and ethnicity (White, Black, Hispanic, Asian, other or unknown); insurance (Medicaid, private, Medicare or other or missing); language (English, other or missing); marital status (married, not married, missing) | 10 | Q-A7 |
| Encounter history | Any earlier admission; admission in the previous 90 days (current pregnancy) | 2 | Q-A1, Q-A3 |
| History (earlier admissions) | Earlier cesarean; hypertensive disorder in an earlier pregnancy; chronic hypertension; pregestational diabetes; gestational diabetes in an earlier pregnancy; tobacco, alcohol or drug use; thyroid disease; **adverse outcome in an earlier pregnancy** (fetal death or preterm delivery); **other high-risk chronic condition** (lupus, antiphospholipid syndrome or thrombophilia; HIV or syphilis; chronic kidney disease) | 9 | Q-A4 |
| Current-pregnancy visits (omr) | Last systolic and last diastolic blood pressure; any pressure of 140/90 or more; last body mass index (if missing, computed from the last weight and any height) | 4 | Q-A5 |
| Current-pregnancy laboratory | Last hemoglobin | 1 | Q-A6 |
| Indicator | Had prenatal care in this hospital (any outpatient measurement or laboratory value in the current-pregnancy window) | 1 | Q-A1, Q-A5, Q-A6 |
| **Total** | | **27** | |

**Dropped, with the reason:** number of earlier admissions and days since the last discharge (replaced by the 90-day indicator); obesity by code (the measured body mass index is more precise and has far more coverage); creatinine (old values, little information; kidney disease is in the composite); hemoglobin A1c (ordered selectively; diabetes is covered by the history); rare conditions as single predictors (merged into the two composites).

**Plausibility limits:** systolic 60–250 mmHg, diastolic 30–150 mmHg, body mass index 12–80 kg/m², weight 70–600 lb, height 48–84 in, hemoglobin 3–20 g/dL. Values outside are set to missing.

## 5. Sample size and learner (G3, S8)

| Field | Value |
|---|---|
| Candidate parameters | 27 |
| Supported parameters | About 17 to 25 by the criteria of Riley et al. with 19,440 admissions and 129 events, if the Cox-Snell R² is 10% or 15% of its maximum; the gate uses the observed R² |
| Primary learner | Penalized logistic regression (events per parameter below 20); tree models and the ensemble as comparisons |
| Missing values | Multiple imputation by chained equations, fitted only on the training data of each validation split and applied to its test data. The indicator "had prenatal care in this hospital" is the only missingness indicator; no parameters are added (27). Pressure is missing in 38.7%, hemoglobin in 41.2% and BMI in 57.3% ([`../predictor_table_antenatal.md`](../predictor_table_antenatal.md)). Decided on 2026-11-19, before any model; pending validation by the supervisor |
| Reduced predictor set (17 parameters) | Age; race and ethnicity (4); Medicaid; English; married; had prenatal care in this hospital; last systolic; elevated pressure; body mass index; hemoglobin; hypertensive history (chronic or in an earlier pregnancy); diabetes (pregestational or gestational in an earlier pregnancy); adverse outcome in an earlier pregnancy. Fixed before any model; never chosen by association with the outcome |

## 5b. Sensitivity analyses

| Analysis | Question |
|---|---|
| Buffers of 1 and 30 days | Does the result depend on the buffer? |
| Only patients with any earlier information (99 events) | Does the result depend on who has a history in this hospital? |
| Calibration by period | Does the model work the same in periods with less history (C4; the audit found less information in recent periods) |
| Strict plus partial; 22 and 28 weeks or more; without early-loss codes | Do the label definitions change the result? |

## 6. Classification criteria (G4)

| Criterion | How it applies | Status |
|---|---|---|
| C1, events already present | The information window closes 7 days before admission, so a death after that point is after the information. A death before it cannot be excluded with codes; the 1-day and 30-day buffers test how much this matters | Applicable through the buffer sensitivity |
| C2, outcome with time | The event is after the information window by design | Applicable |
| C3, detection bias | The outcome is not defined from a test | Not applicable |
| C4, stability over time | Development before 2017, a single test from 2017 onward | Applicable |

**Stated before the results.** Antenatal models of stillbirth built on maternal characteristics usually reach an AUROC of about 0.60 to 0.75. The framework classifies a model as a predictor only with an AUROC of 0.75 or more, so this model may be classified as *neither* if it falls below that. The threshold is not changed for this outcome; any proposal to change it must be decided with the supervisor before the first model is fitted.

## 7. Data used

MIMIC-IV tables `admissions`, `patients`, `diagnoses_icd`, `procedures_icd`, `omr`, `labevents` and `d_labitems`, and the tables built by the scripts of `sql/03_antenatal/`: `mimiciv.antenatal_obstetric_universe` (obstetric universe and delivery flag) and `mimiciv.antenatal_fetal_death_label` (label by admission).

## 8. Next tasks

1. ~~Count audit A1~~ (done, [`../count_audit_antenatal.md`](../count_audit_antenatal.md)).
2. ~~Predictor table A2~~ (done 2026-11-19, [`../predictor_table_antenatal.md`](../predictor_table_antenatal.md)). Missing values: multiple imputation (section 5).
3. ~~Sample-size gate G3~~ (2026-11-20): **not passed**. Observed cross-validated Cox-Snell R²: −0.00054 (−0.7% of the maximum); the reduced set of 17 would not pass either (minimum 0.0124 for 27 parameters and 0.0078 for 17). The outcome is reported as a feasibility analysis.
4. Nested grouped validation, criteria C1, C2 and C4, classification.

*Confidential: internal use of the research project.*
