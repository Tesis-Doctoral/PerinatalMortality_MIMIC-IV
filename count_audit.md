# Count audit — models of perinatal death before birth (fetal death), MIMIC-IV

Living document. First version written on 2026-10-28, after running groups A–E and verifying the code catalogue. It reports what the audit measured, what each result settled and what is still open. The plan is in [`analysis_plan.md`](analysis_plan.md) (section 4 lists every count), the per-count figures are in the sheet *Conteos* of the tracking workbook `docs/Plan_Muerte_Fetal_MIMIC-IV.xlsx` (local file, not versioned) and the Spanish version of this document is [`count_audit_es.md`](count_audit_es.md).

**Status.** Groups A–E run (22 of 29 counts). Pending: Q-C5 (notebook, task T13), group F (predictors, tasks T22–T25) and the checks of the label table by admission (Q-T16a to Q-T16g, script written, not yet run). All figures below are aggregate counts; no row-level output with `subject_id` or `hadm_id` is produced or published.

## 1. Purpose and principle

The audit measures, before any model is built, the numbers that decide the design: which admissions form the population, what the unit of analysis is, how the outcome is defined, when the prediction is made and how many events remain. It follows the maternal project: **no overlap and no selection by outcome**. Each cohort rule is first measured as a column and only then applied, so that every choice is made with numbers and reported together with its sensitivity analysis.

The outcome is a **proxy**: a fetal-death diagnosis code on the maternal admission. MIMIC-IV has no chart review and no mother–newborn linkage, so early neonatal deaths are not captured. The outcome is named **perinatal death before birth** (the antenatal part of perinatal death, that is, fetal death or stillbirth), always labelled as a proxy (decision D2). The perinatal period starts at 22 completed weeks in ICD-10, which is why the 22-week sensitivity analysis matters for the events under 22 weeks.

## 2. Data and scripts

| Item | Detail |
|---|---|
| Database | MIMIC-IV, local PostgreSQL, schema `mimiciv` |
| Universe | `cohort_obstetric_v2` of the revised maternal project (25,736 admissions, 15,084 patients); companion tables `hadm_delivery_v2`, `obstetric_dx_v2`, `predictors_24h_v2` |
| Label used by the counts | Provisional: 13 code patterns inherited from the legacy scripts (strict and partial). Replaced by the verified catalogue (T15), which gives the same events |
| Group A–D | `sql/02_audit_counts/audit_counts.sql` (task T08), run 2026-10-28 |
| Group E | `sql/02_audit_counts/audit_counts_timing.sql` (task T20), run 2026-10-28 |
| Verified codes | `sql/01_labels/01_fetal_death_codes_official.sql` (task T15), run 2026-10-28 |
| Label table by admission | `sql/01_labels/02_fetal_death_label_by_admission.sql` (task T16), written, not yet run |

Every script has an `_es` version with identical code (only comments translated), checked with `scripts/check_sql_pair.py`.

**Event definition.** *Strict*: the admission carries a code of fetal death of the whole pregnancy at an obstetric stage (ICD-10-CM O36.4, Z37.1, Z37.4, Z37.7; ICD-9-CM 656.4, V27.1, V27.4, V27.7). *Partial*: one or more fetuses died while others were liveborn or the pregnancy continued (Z37.3, Z37.6, O31.2; V27.3, V27.6). Early fetal death (O02.1, 632) and newborn-record codes (P95, 768.0, 768.1) are excluded. The label has **no event time**: it is a discharge code.

## 3. Results

### 3.1 Group A — base

The provisional label reproduces the legacy dataset exactly (154 events, 154 in both, 0 discordant admissions), and the base counts match the maternal audit.

| Count | Result |
|---|---|
| Q-A1 base | 25,736 admissions; 15,084 patients; 19,425 delivery hospitalizations (13,729 patients with a delivery); 19,383 eligible at 24 h |
| Q-A2 reconciliation | All 25,736 admissions in both the legacy and the revised table; 154 events in each; 0 discordant |
| Q-A3 admissions per patient | 1: 8,291 · 2: 4,418 · 3: 1,558 · 4: 491 · 5 or more: 326 patients; 6,793 of 15,084 (45.0%) have more than one admission; maximum 27 |

### 3.2 Group B — events and definition

**Events by tier and ICD version (Q-B1).** 154 admissions in 148 patients: 136 strict and 18 partial only. ICD-10: 86 (72 strict, 14 partial); ICD-9: 68 (64, 4).

**Events by scope (Q-B2).** All events carry a structured obstetric code (by construction).

| Scope | Events | Strict | Events per 1,000 |
|---|---|---|---|
| Any obstetric admission | 154 | 136 | 5.98 (per 1,000 admissions) |
| Delivery flag v2 | 127 | 114 | 6.54 (per 1,000 deliveries) |
| Not a delivery | 27 | 22 | — |

**Agreement with the stillbirth-code flag (Q-B3, Q-B3b).** The 109 deliveries with a stillbirth code (Z37.1/.4/.7, V27.1/.4/.7) are all strict events. Of the 136 strict events: 109 carry a stillbirth code and the delivery flag; 15 carry a stillbirth code but not the delivery flag; 12 carry no stillbirth code (they come from O36.4 or 656.4), 5 of them inside the delivery flag. All 15 admissions with a stillbirth code and no delivery flag also carry an abortive, ectopic or molar code (the delivery flag excludes them for that reason). Partial-only events: 18 (13 in a delivery).

**Gestational age (Q-B4, Q-B4b).** Gestational weeks (Z3A codes) exist only in ICD-10.

| Group | Under 22 weeks | 22–27 | 28 or more | No Z3A code |
|---|---|---|---|---|
| Strict, ICD-10 (72) | 13 | 19 | 37 | 3 |
| Partial only, ICD-10 (14) | 3 | 0 | 11 | 0 |

ICD-9 events (68) have no weeks. Of 69 strict events with weeks, 13 (19%) are under 22 weeks, and 7 of those 13 are inside the delivery flag: the flag does not remove pre-viable losses. Finer bands for the 83 ICD-10 events with weeks: under 20 weeks 10 (7 outside a delivery with an abortive code, 3 in a delivery); 20–21 weeks 6 (5 in a delivery); 22–27 weeks 19 (17); 28–36 weeks 25 (21); 37 or more 23 (all in a delivery).

**Position of the code (Q-B5).** Position 1–4 in the diagnosis list: 118 events; 5–10: 30; beyond 10: 6. Only 1 event has no other obstetric code.

**Outside the universe (Q-B6).** Empty: no strict code lies outside the obstetric universe.

**Other outcomes (Q-B7).** Severe maternal morbidity (revised definition) in 15 of 136 strict events and 0 of 18 partial; no maternal death in the same admission.

**Abortive, ectopic or molar codes (Q-B8).** 20 events carry one (19 strict), none in the delivery flag; 134 do not (127 in a delivery, 7 outside).

### 3.3 Group C — patient overlap

**Events per patient (Q-C1).** 143 patients with one event admission, 4 with two, 1 with three (148 patients, 154 event admissions).

**Gap to the previous admission of the same patient (Q-C2).**

| Interval | Admissions | Events |
|---|---|---|
| First admission | 15,084 | 93 |
| Under 90 days | 3,649 | 21 |
| 90–179 days | 595 | 1 |
| 180–364 days | 415 | 2 |
| 365 days or more | 5,993 | 37 |

**Events after an earlier event admission (Q-C3).** Under 90 days: 17 admissions (5 events, 12 non-events); 90–179 days: none; 180–364 days: 15 (0 events); 365 days or more: 78 (1 event). The 17 are the same admissions the legacy scripts described as "under 90 days" (SQL) and "within 180 days" (notebook): no admission lies between 90 and 179 days, so the contradiction is settled. Events in a first admission: 93 (86 strict); in a later admission: 61 (50 strict), that is 40% of the events.

**Events under each candidate unit (Q-C4).**

| Unit | Units | Events | Strict | Patients with an event |
|---|---|---|---|---|
| Admission | 25,736 | 154 | 136 | 148 |
| Delivery hospitalization | 19,425 | 127 | 114 | 126 |
| First admission per patient | 15,084 | 93 | 86 | 93 |
| Pregnancy chain, 30 days | 23,257 | 150 | 135 | 148 |
| Pregnancy chain, 90 days | 22,080 | 149 | 134 | 148 |
| Pregnancy chain, 180 days | 21,485 | 149 | 134 | 148 |

**Pending.** Q-C5 (patients and event-bearing patients on both sides of an admission-level split, hold-out 80/20 and 5-fold), to be computed in the notebook `01_patient_overlap` (task T13). In the maternal project 58–59% of the test patients were also in training.

### 3.4 Group D — era and coding

ICD-9 covers about 2008–2014 (median 2011) and ICD-10 about 2014–2021 (median 2017): **coding version and calendar period are almost confounded**.

| Event rate in deliveries (Q-D1) | Events / deliveries | Per 1,000 |
|---|---|---|
| ICD-10 | 70 / 8,883 | 7.88 |
| ICD-9 | 57 / 10,542 | 5.41 |
| Total | 127 / 19,425 | 6.54 (95% CI 5.5–7.8) |

By anchor-year group: 2008–10 5.23 · 2011–13 6.69 · 2014–16 6.43 · 2017–19 8.51 · 2020–22 12.85 (12 / 934). The trend is significant (p = 0.007, computed by the assistant, to be reproduced in the analysis code).

**Gestational weeks (Q-D2).** Available in 83 of 86 ICD-10 events and 8,844 of 8,883 ICD-10 deliveries; in none of the ICD-9 events or deliveries. In total 8,844 of 19,425 deliveries (45.5%) have weeks, all from the ICD-10 era.

**Plausibility (Q-D3).** Per 1,000 delivery hospitalizations: A, stillbirth code only 109 / 19,425 = 5.61; B, strict 114 = 5.87; C, strict or partial 127 = 6.54; D, ICD-10 only, strict and 28 weeks or more, 36 / 8,883 = 4.05. National reference (NCHS, per 1,000 live births plus fetal deaths): 20 weeks or more 5.48 (2022) and 5.44 (2024); 28 weeks or more 2.71 (2022) and 2.57 (2024) (Gregory et al. 2024, 2026; section 6). The rates at any gestational age are close to the national figure; the 28-week rate is above it (4.05 against 2.57), which may reflect a referral population (not tested). The denominators differ (hospital deliveries, not all births), so the comparison is a plausibility check, not a validation.

### 3.5 Group E — eligibility and timing

The population of decision D3 (delivery flag or stillbirth code) has 19,440 admissions, 142 events and 129 strict events (control Q-E0).

**Length of stay (Q-E1), hours: median [p25–p75]; p05–p95.**

| Group | n | Median [p25–p75] | p05–p95 |
|---|---|---|---|
| Strict events | 129 | 54.4 [36.7–87.8] | 18.6–226.1 |
| Partial only | 13 | 77.1 [61.3–98.9] | — |
| Non-events | 19,298 | 71.0 [58.1–100.5] | 44.7–159.4 |

A stay under 24 h: 17 of 129 strict events (13.2%) against 28 of 19,298 non-events (0.15%); under 12 h: 5 against 7. No missing or non-positive stay.

**Eligibility and events kept (Q-E2, Q-E2b).** At 24 h, 19,395 admissions of the population are eligible (1 died and 44 left before 24 h); 17 of 129 strict events (13.2%) and 0 of 13 partial are lost. With the delivery flag alone, 19,383 are eligible (as in the maternal project) and 14 of 114 strict events are lost (12.3%).

| Hours since admission | Strict events still in hospital (of 129) | Admissions remaining |
|---|---|---|
| 0 | 129 | 19,440 |
| 6 | 129 | 19,437 |
| 12 | 124 (96.1%) | 19,428 |
| 24 | 112 (86.8%) | 19,395 |
| 36 | 97 (75.2%) | 19,144 |
| 48 | 75 (58.1%) | 17,858 |

**First laboratory value, ICU, emergency department (Q-E3).** An ED registration exists in 20 of 129 strict events (15.5%) and 427 of 19,298 non-events (2.2%), a median of 3.4 and 2.6 hours before admission, none more than 24 hours before. The first laboratory value is drawn around admission: median 0.0 h in strict events (p05 −7.5, p95 3.3) and 0.1 h in non-events (−7.8, 5.0); about half are drawn before the admission time (52 of 104 strict events with a laboratory value, 7,544 of 15,880 non-events); 25 of 129 strict events and 3,418 of 19,298 non-events have no laboratory value. ICU stay: 8 of 129 strict events (6.2%; 5 in the first 24 h; median 11.1 h) against 197 of 19,298 non-events (1.0%; 110 in 24 h; median 20.6 h).

**Procedure dates (Q-E4).** Procedure codes carry a date, diagnosis codes do not. Date of the first delivery procedure relative to the admission date:

| Group | No procedure | Before | Day 0 | Day 1 | Day 2 or later |
|---|---|---|---|---|---|
| Strict (129) | 21 | 0 | 36 | 51 | 21 |
| Partial only (13) | 1 | 0 | 5 | 5 | 2 |
| Non-events (19,298) | 4,293 | 21 | 8,551 | 4,733 | 1,700 |

Among admissions with a procedure, day 0, day 1 and day 2 or later are 33%, 47% and 19% in strict events against 57%, 32% and 11% in non-events: events reach the delivery procedure later than non-events. Induction (provisional code list): 43 strict events with a procedure (14 on day 0, 29 on day 1 or later), 4 partial and 6,770 non-events (4,602 on day 0, 2,113 later).

### 3.6 Code verification (T15)

The verified table reproduces the provisional label exactly: 154 events, 136 strict, 18 partial only; 142 and 129 in the population of D3. Every admission with any of these codes in the whole database lies inside the obstetric universe. No admission carries P95, 768.0, 768.1 (newborn-record codes), Z37.6, Z37.7 or V27.6. Seven strict events lie outside the population of D3 (6 with ICD-9 656.4, 1 with ICD-10 O36.4); the six equal the number of 656.43 (antepartum) codes, a coincidence that the label table checks in Q-T16b. The early-loss codes (O02.1, 632) appear in 113 admissions: 102 without an event code (correctly excluded) and 11 with one, which the label table flags as `has_early_loss_code`.

### 3.7 Pending and not yet run

| Item | What it will show | Where |
|---|---|---|
| Q-T16a–g | Integrity of the label table, the 7 strict events outside D3, code families and position, events with early-loss codes, label sizes, admissions under 6 h | `02_fetal_death_label_by_admission.sql` |
| Q-C5 | Patient leakage of an admission-level split | notebook `01_patient_overlap` (T13) |
| Q-F1–F6 | Predictor availability, coverage rule, history visibility, outpatient records, units, outcome-related codes among the first diagnoses | group F (T22–T25) |

## 4. What the audit settled

| Decision | Choice (2026-10-28) | Evidence |
|---|---|---|
| D1 database | Revised tables of the maternal project | Base counts match the maternal audit; the label reproduces the legacy dataset (Q-A1, Q-A2) |
| D3 population | Delivery flag v2 **or** stillbirth code (19,440 admissions; 142 events, 129 strict) | The flag alone leaves out 15 admissions with a stillbirth code, all with an abortive code (Q-B3b); no strict code outside the universe (Q-B6) |
| D4 unit | One record per delivery hospitalization, validation grouped by patient; 90-day pregnancy chain as sensitivity | Chains change the event count by at most 5 (Q-C4); first admission only would lose 40% of the events (Q-C3); 5 patients have more than one event admission (Q-C1) |
| D5 outcome | Strict code at any gestational age as main; sensitivities: strict + partial, 22 weeks or more, 28 weeks or more (ICD-10 only), excluding events with an early-loss code | Weeks exist only in ICD-10 and 19% of strict events with weeks are under 22 (Q-B4, Q-D2); the 20/22/28-week definitions differ by source |
| D6 prediction point | Admission + 6 h (12 h, 24 h and retrospective as sensitivities) | At 24 h 13.2% of strict events are lost against 0.15% of non-events; all 129 remain at 6 h (Q-E1, Q-E2) |
| D7 time zero and window | Admission time; window from 24 h before admission to the prediction point | First laboratory value around admission and half before it; ED registration a median 3 h earlier (Q-E3) |
| D8 short admissions | Exclude the 3 admissions that end before 6 h (0 events) and report them apart | Q-E2b: 19,440 − 19,437 admissions at 6 h |

Open decisions: D2 (outcome name) and D9–D14 (predictor blocks, coverage rule, models, sample size, reporting).

## 5. Interpretation and limits

- **Early risk or detection model, not a forecast of a later event.** The label is a discharge code without a time and fetal death is often already present at arrival; the model estimates the risk of a fetal-death code from information available up to the prediction point.
- **Era confounding.** ICD version, gestational-age availability and calendar period move together; the rise from 5.2 to 12.9 per 1,000 may reflect coding practice as well as case mix. Any sensitivity analysis by version cannot separate them.
- **Pre-viable losses.** The delivery flag does not remove them (7 of 13 strict events under 22 weeks are inside it); only ICD-10 admissions allow a weeks-based cut, and 3 strict ICD-10 events have no weeks.
- **Denominators.** The rates use hospital deliveries of a tertiary centre; comparison with national figures is a plausibility check only.
- **Provisional elements.** The induction procedure list (ICD-9 73.0, 73.1, 73.4; ICD-10-PCS 10907ZC) is provisional. The CDC and CMS code files were not downloaded; the catalogue rests on AAPC, Kodex, findacode and icd9data pages and on the WHO ICD-10 2019 browser, and must be cross-checked before submission. The O31.2 seventh character and the Z3A codes were not verified one by one; WHO has no ICD-9.
- **Trend test.** The p = 0.007 was computed by the assistant and must be reproduced in the analysis code before it is quoted.
- **Small cells.** Several cells are small (partial events, 5 patients with several event admissions); report them with care and never at row level.

## 6. Sources

- Gregory ECW, Valenzuela CP, Hoyert DL. Fetal mortality: United States, 2022. National Vital Statistics Reports, vol. 73, no. 9. Hyattsville, MD: National Center for Health Statistics; September 12, 2024. https://www.cdc.gov/nchs/data/nvsr/nvsr73/nvsr73-09.pdf (20 weeks or more: 5.48; 28 weeks or more: 2.71, per 1,000 live births and fetal deaths).
- Gregory ECW, Valenzuela CP, Hoyert DL. Fetal mortality: United States, 2024. National Vital Statistics Reports, vol. 75, no. 6. Hyattsville, MD: National Center for Health Statistics; September 10, 2026. https://www.cdc.gov/nchs/data/nvsr/nvsr75/nvsr75-06.pdf (20 weeks or more: 5.44, 5.98 in 2014; 28 weeks or more: 2.57, 2.83 in 2014). Both reports count fetal deaths at 20 weeks or more (early 20–27 weeks, late 28 weeks or more) and exclude induced terminations; checked against the PDFs on 2026-10-28.
- WHO ICD-10 (2019 browser): O36.4, Z37, P95 (screenshots supplied by the author on 2026-10-28).
- ICD-10-CM (AAPC, Kodex, findacode.com) and ICD-9-CM (icd9data.com): code titles and inclusion terms, as listed in the header of `sql/01_labels/01_fetal_death_codes_official.sql`.
- Stillbirth thresholds: WHO and ICD-11, 22 weeks; NCHS, 20 weeks.
- MIMIC-IV tables and the revised maternal cohort: `MaternalMortality_MIMIC-IV` (manuscript healthcare-4661619).

*Confidential: internal use of the research project; aggregate results only.*
