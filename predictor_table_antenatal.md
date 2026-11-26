# Predictor table — verification (antenatal model)

Run on 2026-11-19 with `sql/03_antenatal/04_predictor_table.sql` (task A2); the Spanish version has the `_es` suffix. Spanish version: [`predictor_table_antenatal_es.md`](predictor_table_antenatal_es.md).

**Framework stage:** S6 and S7 (information window and predictors). Creates `mimiciv.antenatal_predictors_v1`, the table the models read, with one row per admission and buffer (1, 7 and 30 days). Queries Q-P1 to Q-P4 verify the table before the sample-size gate (G3).

All figures are aggregate counts of the whole population; no query splits events and non-events, except the event count of Q-P1. No `subject_id`, `hadm_id` or patient-level row is published.

## Q-P1. Integrity

| Buffer | Rows | Admissions | Patients | Strict events | With any prior information |
|---|---|---|---|---|---|
| 1 day | 19,440 | 19,440 | 13,735 | 129 | 17,285 (88.9%) |
| **7 days** | **19,440** | **19,440** | **13,735** | **129** | **17,166 (88.3%)** |
| 30 days | 19,440 | 19,440 | 13,735 | 129 | 16,919 (87.0%) |

**What it means.** Each buffer has exactly one row per admission, with no duplicates or losses, and keeps the population and events of gate G1. Admissions with any prior information match the count audit (Q-A1): for example, at 7 days, 99 events + 11 partial-only + 17,056 non-events = 17,166. The table and the audit are built the same way.

## Q-P2. Categorical and binary predictors (7-day buffer)

| Predictor | Category | Admissions | % |
|---|---|---|---|
| Race and ethnicity | White | 8,715 | 44.8 |
| | Black | 4,459 | 22.9 |
| | Hispanic | 1,876 | 9.7 |
| | Asian | 1,795 | 9.2 |
| | Other or unknown | 2,595 | 13.3 |
| Insurance | Private | 12,631 | 65.0 |
| | Medicaid | 6,169 | 31.7 |
| | Medicare, other or missing | 640 | 3.3 |
| Language | English | 17,846 | 91.8 |
| Marital status | Married | 11,664 | 60.0 |
| | Not married | 7,391 | 38.0 |
| | Missing | 385 | 2.0 |
| Any earlier admission | Yes | 8,425 | 43.3 |
| Admission in the previous 90 days | Yes | 1,524 | 7.8 |
| Earlier cesarean | Yes | 1,670 | 8.6 |
| Hypertensive disorder in an earlier pregnancy | Yes | 989 | 5.1 |
| Chronic hypertension | Yes | 472 | 2.4 |
| Pregestational diabetes | Yes | 267 | 1.4 |
| Gestational diabetes in an earlier pregnancy | Yes | 418 | 2.2 |
| Tobacco, alcohol or drug use | Yes | 457 | 2.4 |
| Thyroid disease | Yes | 728 | 3.7 |
| Adverse outcome in an earlier pregnancy | Yes | 459 | 2.4 |
| Other high-risk chronic condition | Yes | 143 | 0.7 |
| Any pressure of 140/90 or more | Yes | 2,009 | 10.3 |
| Had prenatal care in this hospital | Yes | 14,954 | 76.9 |
| Hypertensive history (any) | Yes | 1,348 | 6.9 |
| Diabetes (any) | Yes | 669 | 3.4 |

**What it means.**
1. Earlier admissions (8,425) and the history predictors match the audit (Q-A4).
2. No category is empty. The rarest is "other high-risk chronic condition" (143 admissions, 0.7%), which is why it was defined as a composite.
3. Three in four women had prenatal care in the hospital, and one in ten had an elevated pressure in the current pregnancy.

## Q-P3. Continuous predictors (7-day buffer)

| Predictor | With value | % | P5 | P25 | Median | P75 | P95 |
|---|---|---|---|---|---|---|---|
| Age (years) | 19,440 | 100.0 | 22 | 29 | 33 | 36 | 41 |
| Last systolic (mmHg) | 11,916 | 61.3 | 98 | 108 | 116 | 122 | 136 |
| Last diastolic (mmHg) | 11,916 | 61.3 | 58 | 64 | 70 | 78 | 86 |
| Last BMI (kg/m²) | 8,304 | 42.7 | 22.7 | 27.0 | 30.5 | 35.1 | 44.2 |
| Last hemoglobin (g/dL) | 11,435 | 58.8 | 9.6 | 10.8 | 11.5 | 12.2 | 13.3 |

**What it means.**
1. The distributions are clinically plausible for pregnant women: normal pressure in most, pregnancy BMI (it includes weight gain) and hemoglobin with the physiological drop of pregnancy.
2. Coverage is lower than in the audit (Q-A5: pressure in 68%; Q-A6: hemoglobin in 69%) because only values of the current pregnancy count here (between 280 and 7 days before admission). This is expected.
3. **Missing values:** no pressure in 38.7%, no hemoglobin in 41.2% and no BMI in 57.3%. Most correspond to women without prenatal care in the hospital (23.1%), but BMI is also missing in many who had it. The handling of missing values must be fixed before gate G3 (see the final section).

## Q-P4. Source of the BMI (7-day buffer)

| Recorded | Computed from weight and height | Missing |
|---|---|---|
| 8,282 | 22 | 11,136 |

**What it means.** Computing from weight and height adds almost no values (22). The system records BMI whenever weight and height exist, so women without BMI have no height either. BMI is the continuous predictor with the most missing values.

## What remains for the model

- The table passes verification: correct population, events and uniqueness in the three buffers, and counts equal to the audit.
- **Handling of missing values (decided on 2026-11-19: option 1, multiple imputation; recorded in the outcome card)** of pressure, BMI and hemoglobin. The options are:
  1. multiple imputation inside each validation split, with "had prenatal care in this hospital" as the only indicator (no extra parameters; 27 parameters);
  2. single imputation plus one missing indicator per measurement (pressure, BMI, hemoglobin; 30 parameters).
- Next step: sample-size gate (G3) with the observed Cox-Snell R².

*Confidential: internal use of the research project.*
