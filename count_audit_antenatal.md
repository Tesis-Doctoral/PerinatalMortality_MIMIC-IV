# Count audit — information available before the admission (antenatal model)

Run on 2026-11-18 with the scripts of `sql/03_antenatal/` (population and label, task A0) and `sql/03_antenatal/03_prior_information.sql` (earlier information, task A1); the Spanish versions carry the suffix `_es`. Spanish version: [`count_audit_antenatal_es.md`](count_audit_antenatal_es.md).

**Framework stage:** S4 (count audit). Its results fix the predictors (S7) and the candidate parameters before the sample-size gate (G3).

All figures are aggregate counts. No `subject_id`, `hadm_id` or patient-level row is published, and counts of 1 to 4 are shown as "<5". The proposals of this document are recorded in the outcome card ([`docs/outcome_card_antenatal.md`](docs/outcome_card_antenatal.md)) before any model is fitted.

## 1. What we needed to know

The antenatal model may use only what was known about the woman **before** the delivery admission. Before building it we needed three answers:

1. How many patients have any earlier information? If almost none, the model is not feasible.
2. What information is there, how often, and how recent is it?
3. Given that, which predictors enter the model?

## 2. How it was measured

- **Population:** delivery hospitalizations, plus admissions with a stillbirth code that were not flagged as deliveries: 19,440 admissions of 13,735 patients.
- **Outcome:** fetal death with the strict definition, that is, a code of fetal death of the whole pregnancy (ICD-10-CM O36.4, Z37.1, Z37.4, Z37.7; ICD-9-CM 656.4, V27.1, V27.4, V27.7): 129 events (0.66%). The label is in the table `antenatal_fetal_death_label`, with one row per admission (`sql/03_antenatal/`).
- **Information window:** everything recorded **at least 7 days before** the admission (main buffer). Buffers of 1 and 30 days are sensitivity analyses. The buffer keeps out information from a visit at which the fetal death had already been found.
- **Sources:**
  - earlier admissions to the same hospital (their diagnoses and procedures);
  - outpatient measurements (table `omr`: weight, blood pressure, body mass index, height);
  - outpatient laboratory values (`labevents` without an admission).
- **Rule against selection by outcome:** only the block-availability queries (Q-A1 to Q-A3) split events and non-events, because they decide whether the model is feasible. The frequency of each condition or measurement (Q-A4 to Q-A7) is shown for the whole population only. This way no predictor is chosen by its association with fetal death.
- **Adjustments made to the script while running it:**
  - in this database `omr.chartdate` is a timestamp, so it was cast to a date;
  - the race column is called `ethnicity`, as in earlier loads of MIMIC-IV.

## 3. Population and label (definition gate G1)

Before measuring the earlier information, we checked that the population and the label are built the same way and reproduce the reference counts. This is the condition of gate G1: population, unit and definition fixed, and counts reproducible. Scripts: `sql/03_antenatal/01_obstetric_universe.sql` and `02_fetal_death_label.sql`.

### Q-U1. Obstetric universe and population

| Obstetric admissions | Patients | Delivery hospitalizations | With a stillbirth code | Population of the model |
|---|---|---|---|---|
| 25,736 | 15,084 | 19,425 | 124 | 19,440 |

**What it means.** The obstetric universe is the admissions of women aged 12 to 55 with at least one diagnosis of pregnancy, delivery or the puerperium. Of them, 19,425 are delivery hospitalizations. Of the 124 stillbirth codes, 109 are within deliveries and 15 fall outside the delivery flag. Those 15 are added to the population: 19,425 + 15 = 19,440.

### Q-U2. Population by coding era

| Era | Deliveries | Stillbirth code without delivery flag |
|---|---|---|
| ICD-10 | 8,883 | 10 |
| ICD-9 | 10,542 | 5 |

**What it means.** The 15 stillbirth admissions outside the delivery flag also carry an abortive code, which is why the flag excludes them. They stay in the population because fetal death is the outcome. The population is split almost in half between the two coding eras.

### Q-L1. Fetal-death code catalogue

| Tier | ICD-9 | ICD-10 |
|---|---|---|
| Strict | 4 | 4 |
| Partial | 2 | 3 |
| Excluded | 3 | 2 |

**What it means.** The catalogue has the 18 expected patterns.
- **Strict:** fetal death of the whole pregnancy (O36.4, Z37.1, Z37.4, Z37.7; 656.4, V27.1, V27.4, V27.7).
- **Partial:** multiple pregnancies in which some fetus died.
- **Excluded:** early fetal death (before 20 or 22 weeks) and newborn-record codes. They are listed for audit only.

### Q-L2. Reference counts of the population

| Admissions | Patients | Strict events | Events with partial codes |
|---|---|---|---|
| 19,440 | 13,735 | 129 | 142 |

**What it means.** The population and the outcome match the reference counts. **Gate G1 is passed.**

### Q-L3. Size of every label definition

| Definition | Events | Use |
|---|---|---|
| Strict, any gestational age | 129 | Main model |
| Strict plus partial | 142 | Sensitivity |
| Strict without an early-loss code | 119 | Sensitivity |
| Strict at 22 weeks or more | 55 | Sensitivity (ICD-10 only) |
| Strict at 28 weeks or more | 37 | Sensitivity (ICD-10 only) |
| Strict without gestational weeks | 61 | Reported separately |
| Strict with a newborn-record code | 0 | Control |

**What it means.**
1. Gestational weeks exist only in ICD-10. That is why the 22- and 28-week definitions have few events (55 and 37); they will show the direction of the result, not support a model of their own.
2. No event uses a newborn-record code, so the label uses only the mother's record.

## 4. Information available before the admission (Q-A0 to Q-A7)

### Q-A0. Population check

| Admissions | Patients | Strict events | Events with partial codes |
|---|---|---|---|
| 19,440 | 13,735 | 129 | 142 |

**What it means.** The figures match the reference counts of the population and the label. The database, the population and the label are correctly linked.

**For the model.** These become the expected counts: any run with another population stops (gate G1).

### Q-A1. How many have earlier information? (the feasibility count)

| Buffer | Group | Admissions | Any information | % | Earlier admission | Earlier obstetric admission | Outpatient measurements | Outpatient laboratory |
|---|---|---|---|---|---|---|---|---|
| 1 day | Strict events | 129 | 100 | 77.5 | 50 | 48 | 87 | 80 |
| 1 day | Partial only | 13 | 11 | 84.6 | 7 | 7 | 10 | 10 |
| 1 day | Non-events | 19,298 | 17,174 | 89.0 | 8,508 | 7,592 | 14,192 | 14,102 |
| **7 days** | **Strict events** | **129** | **99** | **76.7** | **49** | **47** | **86** | **79** |
| 7 days | Partial only | 13 | 11 | 84.6 | 7 | 7 | 10 | 10 |
| **7 days** | **Non-events** | **19,298** | **17,056** | **88.4** | **8,369** | **7,438** | **14,151** | **13,965** |
| 30 days | Strict events | 129 | 97 | 75.2 | 47 | 44 | 84 | 78 |
| 30 days | Partial only | 13 | 11 | 84.6 | 7 | 7 | 10 | 10 |
| 30 days | Non-events | 19,298 | 16,811 | 87.1 | 8,031 | 7,059 | 14,004 | 13,721 |

The source columns do not add up: a patient can have several sources.

**What it means.**
1. **The model is feasible.** Three in four women with a fetal death (99 of 129) have information before the admission.
2. **Outpatient measurements are the most common source** (67% of events), ahead of earlier admissions (38%).
3. **The buffer barely matters.** Between 1 and 30 days only 3 events with information are lost, so the result will not depend on that choice.
4. **Women with a fetal death have somewhat less information** (77% against 88%). This may reflect less prenatal care in this hospital, a known risk factor, or referral from elsewhere.

**For the model.**
- Main buffer of 7 days; 1 and 30 days as sensitivity.
- Each block has an indicator of whether information exists, because the absence of a record is not the absence of the condition.
- New sensitivity analysis: refit the model **only among patients with any earlier information** (99 events), to check that the result does not depend on who has a history and who does not.

### Q-A2. Earlier information by period (7-day buffer)

The anchor-year group is assigned to each patient by MIMIC-IV (dates are shifted). It shows roughly when the patient started to appear in the hospital, not the year of the delivery.

| ICD era | Anchor-year group | Admissions | With information | % | Strict events | Events with information |
|---|---|---|---|---|---|---|
| ICD-10 | 2008–2010 | 1,533 | 1,497 | 97.7 | 12 | 12 |
| ICD-10 | 2011–2013 | 1,512 | 1,480 | 97.9 | 10 | 10 |
| ICD-10 | 2014–2016 | 2,561 | 2,342 | 91.4 | 16 | 15 |
| ICD-10 | 2017–2019 | 2,353 | 2,009 | 85.4 | 22 | 11 |
| ICD-10 | 2020–2022 | 934 | 765 | 81.9 | 11 | 9 |
| ICD-9 | 2008–2010 | 6,700 | 5,910 | 88.2 | 34 | 30 |
| ICD-9 | 2011–2013 | 2,826 | 2,417 | 85.5 | 17 | 9 |
| ICD-9 | 2014–2016 | 1,020 | 746 | 73.1 | 7 | <5 |
| ICD-9 | 2017–2019 | <5 | 0 | — | 0 | 0 |

**What it means.**
1. **The longer a patient has been in the hospital, the more earlier information she has.** Coverage falls from 98% to 82% in ICD-10 and from 88% to 73% in ICD-9, because patients of recent groups had less time to accumulate records.
2. **The effect is stronger among events.** In recent groups about half of the women with a fetal death have earlier information.

**For the model.**
- It affects criterion **C4 (stability over time)**. Temporal validation trains on periods with a long history and tests on periods with a shorter one. Performance may fall, and the information indicators may mean different things by period.
- Calibration is reported by period, the sensitivity analysis "only patients with earlier information" is kept, and this is stated as a known limitation before modelling.

### Q-A3. Earlier admissions: how many and how long ago (7-day buffer)

| Group | Admissions | None | One | Two or three | Four or more | Last ≤ 90 days | 91–365 days | > 1 year |
|---|---|---|---|---|---|---|---|---|
| Strict events | 129 | 80 | 22 | 20 | 7 | 12 | <5 | 34 |
| Partial only | 13 | 6 | <5 | <5 | 0 | <5 | 0 | <5 |
| Non-events | 19,298 | 10,929 | 5,156 | 2,636 | 577 | 1,513 | 870 | 5,986 |
| Total | 19,440 | 11,015 | 5,181 | 2,660 | 584 | 1,528 | 873 | 6,024 |

**What it means.**
1. **Six in ten women have no earlier admission** to this hospital. For them, the diagnosis-based history will be empty.
2. **Most earlier admissions were more than a year before** (69–72%), that is, in earlier pregnancies. This source mainly provides **obstetric history**: cesarean, preeclampsia, preterm delivery or fetal death in another pregnancy.
3. **Those within 90 days** probably belong to the current pregnancy (threatened preterm labor, hypertension, bleeding). They are few but reflect complications of the ongoing pregnancy.

**For the model.**
- Two indicators: **any earlier admission** and **admission in the previous 90 days**. The second is more useful than the days since the last discharge, because it separates the current pregnancy from earlier ones.

### Q-A4. Conditions in earlier admissions (7-day buffer; whole population only)

The percentage "with history" is computed over the 8,425 admissions with any earlier admission.

| Condition | Admissions | % of population | % of those with history |
|---|---|---|---|
| Earlier cesarean | 1,670 | 8.59 | 19.82 |
| Hypertensive disorder in an earlier pregnancy | 989 | 5.09 | 11.74 |
| Thyroid disease | 728 | 3.74 | 8.64 |
| Obesity (code) | 669 | 3.44 | 7.94 |
| Chronic hypertension | 472 | 2.43 | 5.60 |
| Tobacco, alcohol or drug use | 457 | 2.35 | 5.42 |
| Earlier preterm delivery | 419 | 2.16 | 4.97 |
| Gestational diabetes in an earlier pregnancy | 418 | 2.15 | 4.96 |
| Pregestational diabetes | 267 | 1.37 | 3.17 |
| Lupus, antiphospholipid syndrome or thrombophilia | 91 | 0.47 | 1.08 |
| Earlier fetal death | 52 | 0.27 | 0.62 |
| HIV or syphilis | 30 | 0.15 | 0.36 |
| Chronic kidney disease | 27 | 0.14 | 0.32 |

**What it means.**
1. Frequent conditions (more than 1% of the population) have enough cases for the model to learn from them.
2. Rare ones (under 1%) contribute at most one or two events each. The model cannot learn anything stable from them, and each would use one of the 17 to 25 parameters the data support (section 5).
3. Earlier fetal death is the strongest risk factor in the literature, but here it is very rare (52 admissions).

**For the model** (decided only from these frequencies and clinical reasons, without looking at the outcome).
- **Kept as single predictors:**
  - earlier cesarean;
  - hypertensive disorder in an earlier pregnancy;
  - chronic hypertension;
  - pregestational diabetes;
  - gestational diabetes in an earlier pregnancy;
  - tobacco, alcohol or drug use;
  - thyroid disease.
- **Composite "adverse outcome in an earlier pregnancy":** earlier fetal death or preterm delivery, about 460 admissions (2.4%). The history of fetal death is kept this way.
- **Composite "other high-risk chronic condition":** lupus, antiphospholipid syndrome or thrombophilia; HIV or syphilis; chronic kidney disease. About 150 admissions (0.8%).
- **Obesity by code:** dropped in favour of the measured body mass index (Q-A5).
- The code lists are provisional and are verified before the predictor table is built.

### Q-A5. Outpatient measurements (7-day buffer; whole population only)

| Measurement | Admissions with a value | % of population | Value in the last year | Median days before admission |
|---|---|---|---|---|
| Weight (Lbs) | 13,586 | 69.9 | 11,124 | 13 |
| Blood pressure | 13,267 | 68.2 | 12,161 | 12 |
| Body mass index (kg/m2) | 10,195 | 52.4 | 7,950 | 14 |
| Height (Inches) | 9,227 | 47.5 | 5,368 | 267 |
| Body mass index (other name: BMI) | 757 | 3.9 | 730 | 62 |
| Weight (other name) | 124 | 0.6 | 110 | 85 |
| Blood pressure sitting | 66 | 0.3 | 29 | 518 |
| Blood pressure standing (1 min) | 52 | 0.3 | 22 | 518 |
| Blood pressure lying | 49 | 0.3 | 19 | 532 |
| Blood pressure standing | 10 | 0.1 | <5 | 1,139 |
| Blood pressure standing (3 min) | 7 | 0.0 | <5 | 305 |
| Height (other name) | 6 | 0.0 | 6 | 207 |

**What it means.**
1. **This is the most valuable block.** Seven in ten women have weight and blood pressure, and half of those values were taken **less than two weeks before the delivery**. They are measurements from the prenatal visits of the current pregnancy.
2. **Blood pressure is the most promising predictor.** Hypertensive disorders of pregnancy are among the main causes of fetal death, and here the measured pressure is available, not only a code.
3. Body mass index has lower coverage than weight, but it can be computed from weight and height. Height barely changes, so an old value still works.
4. The body mass index of a prenatal visit includes pregnancy weight gain; it is not the pre-pregnancy value.
5. The rows with other names are the same measurements recorded by another system and are merged with the main one.

**For the model.**
- **Current-pregnancy window:** only values taken between 280 and 7 days before the admission. With no value in that window the predictor is missing, with its indicator.
- **Blood pressure:**
  - last systolic;
  - last diastolic;
  - indicator of **any pressure of 140/90 or more** in the window.
- **Body mass index:** the last recorded value; if missing, computed from the last weight and any available height.
- **Obesity by code:** dropped.

### Q-A6. Outpatient laboratory values (7-day buffer; whole population only)

| Test | Admissions with a value | % of population | Value in the last year | Median days before admission |
|---|---|---|---|---|
| Hemoglobin | 13,453 | 69.2 | 11,669 | 85 |
| Creatinine | 9,790 | 50.4 | 6,460 | 200 |
| Hemoglobin A1c | 3,349 | 17.2 | 2,076 | 239 |
| Any other test | 14,054 | 72.3 | 12,471 | 59 |

**What it means.**
1. **Hemoglobin is the best of this block.** Coverage is good (69%), and the median of 85 days matches the routine third-trimester blood count. Maternal anemia is a risk factor for fetal death.
2. **Creatinine is old** (median of 200 days) and is usually normal in young women.
3. **Hemoglobin A1c is ordered selectively**, almost always when diabetes is suspected. The fact that it was ordered already says something about the patient.
4. "Any other test" shows that the patient was followed in this hospital.

**For the model.**
- **Kept:** last hemoglobin in the current-pregnancy window.
- **Dropped:**
  - creatinine, because it adds little and kidney disease is already in the chronic-condition composite;
  - hemoglobin A1c, because it is ordered selectively and diabetes is already covered by the history.
- **A single indicator "had prenatal care in this hospital"** joins outpatient measurements and laboratory values. Both coverages are almost the same (70–72%) and they measure the same thing.

### Q-A7. Registration variables of the admission (whole population only)

| Admissions | Marital status missing | Insurance missing or "Other" | Language missing | Race and ethnicity unknown or declined |
|---|---|---|---|---|
| 19,440 | 385 (2.0%) | 441 (2.3%) | 30 (0.2%) | 928 (4.8%) |

**What it means.** The registration variables are almost complete. They are recorded on arrival and do not depend on how the patient presented, so they can be used.

**For the model.** Admission type and admission location remain excluded: they reflect how the patient arrived, which the fetal death itself can cause.

| Variable | Categories | Parameters |
|---|---|---|
| Age | continuous | 1 |
| Race and ethnicity | White, Black, Hispanic, Asian, other or unknown | 4 |
| Insurance | Medicaid, private, Medicare or other or missing | 2 |
| Language | English, other or missing | 1 |
| Marital status | married, not married, missing | 2 |

## 5. What the audit leaves for the model

### Parameters the data support

With 19,440 admissions and 129 events (prevalence 0.66%), the criteria of Riley et al. support about **17 parameters** if the Cox-Snell R² of the model is 10% of its maximum, and about **25** if it is 15%. This is a prior estimate: the sample-size gate (G3) is decided with the observed R².

### Proposed predictor list (about 27 parameters)

| Block | Predictors | Parameters |
|---|---|---|
| Registration | age, race and ethnicity, insurance, language, marital status | 10 |
| Encounter history | any earlier admission; admission in the previous 90 days | 2 |
| History | cesarean; hypertensive disorder in an earlier pregnancy; chronic hypertension; pregestational diabetes; gestational diabetes in an earlier pregnancy; tobacco, alcohol or drug use; thyroid disease; adverse outcome in an earlier pregnancy; other high-risk chronic condition | 9 |
| Current-pregnancy visits | last systolic; last diastolic; any pressure of 140/90 or more; last body mass index | 4 |
| Current-pregnancy laboratory | last hemoglobin | 1 |
| Indicator | had prenatal care in this hospital | 1 |
| **Total** | | **27** |

### Reduced set (17 parameters), fixed before any model

Used if the sample-size gate (G3) is not passed with 27 parameters:
- age;
- race and ethnicity (4 parameters);
- Medicaid;
- English;
- married;
- had prenatal care in this hospital;
- last systolic;
- elevated pressure;
- body mass index;
- hemoglobin;
- hypertensive history (chronic or in an earlier pregnancy);
- diabetes (pregestational or gestational in an earlier pregnancy);
- adverse outcome in an earlier pregnancy.

It is never chosen by the association of the predictors with the outcome.

### Sensitivity analyses added by the audit

| Analysis | Question |
|---|---|
| Buffers of 1 and 30 days | Does the result depend on the buffer? |
| Only patients with any earlier information | Does the result depend on who has a history in the hospital? |
| Calibration by period | Does the model work the same in periods with less history (C4)? |

### Still pending before the predictor table is built

1. Verify the code lists of the history conditions (they are provisional).
2. Split systolic and diastolic from the blood-pressure text ("120/80") and set plausibility limits for blood pressure, body mass index and hemoglobin.
3. Merge measurements recorded under different names (BMI, Weight, Height and the blood-pressure variants).

*Confidential: internal use of the research project.*
