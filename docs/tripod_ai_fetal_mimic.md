# Stage S11 — TRIPOD+AI checklist: fetal death in MIMIC-IV (M3), feasibility analysis

Spanish version: [`tripod_ai_fetal_mimic_es.md`](tripod_ai_fetal_mimic_es.md). Checklist of TRIPOD+AI (Collins et al., BMJ 2024;385:e078378) for model M3 (fetal death, identified with the mother's ICD codes, in the delivery hospitalizations of MIMIC-IV v3.1). Version of 2026-11-26.

**Reduced checklist.** M3 stopped before any model was fitted: at admission + 6 hours, stage S6 found that 73 of the 129 fetal deaths (56.6%) were already present (it would fail C1); after return R3 (antenatal prediction), gate G3 did not pass (cross-validated Cox-Snell R² −0.00221). It is reported as a **feasibility analysis**. The items about the data, the outcome, the predictors and the sample size apply; the items about the fitted model, its performance and its use do not, and are marked "—" with the reason.

**Status:** ✅ reported in the repository · 📝 to be written in the monograph or article · ⚠️ gap · — not applicable (with the reason).

Abbreviations: **OC-A** = outcome card of the antenatal model [`outcome_card_antenatal.md`](outcome_card_antenatal.md); **OC-6h** = outcome card at admission + 6 h [`outcome_card_fetal_death.md`](outcome_card_fetal_death.md); **CA** = [`../count_audit.md`](../count_audit.md); **CA-A** = [`../count_audit_antenatal.md`](../count_audit_antenatal.md); **NB0x** = `notebooks/0x_*.ipynb`; **OUT0x** = `data/outputs_0x_*.txt`; **FW** = framework ([StagedFramework_ClinicalPrediction](https://github.com/Tesis-Doctoral/StagedFramework_ClinicalPrediction)).

## Title and abstract

| Item | Content | Where | Status |
|---|---|---|---|
| 1 | Title: development not completed, population, outcome | Monograph chapter 7: "fetal death in MIMIC-IV… feasibility" | 📝 |
| 2 | Abstract | Monograph | 📝 |

## Introduction

| Item | Content | Where | Status |
|---|---|---|---|
| 3a | Healthcare context and rationale; existing models | OC-A §1, §6 (antenatal stillbirth models usually reach AUROC 0.60–0.75); monograph | 📝 |
| 3b | Target population, prediction point, intended users | OC-A §2–§3 (delivery hospitalizations; information at least 7 days before admission) | ✅ |
| 3c | Known health inequalities | Monograph | 📝 |
| 4 | Objectives | README; OC-A §1 | ✅ |

## Methods

| Item | Content | Where | Status |
|---|---|---|---|
| 5a | Data source, representativeness | README (data access); OC-A §2, §7: MIMIC-IV v3.1, one academic hospital (Beth Israel Deaconess Medical Center, Boston) | ✅ |
| 5b | Dates of the data | MIMIC-IV 2008–2022, dates shifted per patient (anchor-year groups); NB01 (S1) | ✅ |
| 6a | Setting and centres | One centre, hospital admissions and outpatient records (OC-A §3) | ✅ |
| 6b | Eligibility criteria | OC-A §2: delivery hospitalizations plus admissions with a stillbirth code (19,440 admissions, 13,735 patients); NB01, NB04 (gate G1) | ✅ |
| 6c | Treatments and how they were handled | OC-A §3: nothing of the current admission enters; only earlier history | ✅ |
| 7 | Data preparation and quality control | `sql/` scripts with checks; NB01 and NB04 (gate G1: reference counts reproduced); plausibility limits (OC-A §4) | ✅ |
| 8a | Outcome, how and when assessed | OC-A §2: strict fetal-death code of the mother (129 events, 0.66%), always labelled a proxy; CA (code catalogue) | ✅ |
| 8b | Subjective assessment of the outcome | Diagnosis codes recorded by the hospital; the codes carry no date (CA, group G) | ✅ |
| 8c | Blinding | — No model was fitted | — |
| 9a | Initial choice of predictors | OC-A §4 (27 parameters fixed from the count audit, never split by outcome; dropped variables with the reason) | ✅ |
| 9b | Definition of every predictor | OC-A §4; [`../predictor_table_antenatal.md`](../predictor_table_antenatal.md); NB05 | ✅ |
| 9c | Subjective assessment of predictors | Blood pressure, BMI and laboratory values are measurements; histories are diagnosis codes | ✅ |
| 10 | Sample size | NB06 gate G3 (Riley et al. with the observed cross-validated Cox-Snell R²: −0.00221, −2.9% of the maximum; minimum R² 0.0124 for 27 parameters and 0.0078 for the reduced set of 17); OUT06 | ✅ |
| 11 | Missing data | OC-A §5 (multiple imputation planned; pressure missing in 38.7%, hemoglobin 41.2%, BMI 57.3%); NB05 | ✅ |
| 12a–12g | Use of the data, predictors, model type, tuning, measures, updating, predictions | — No model was fitted: the analysis stopped at S6 (admission + 6 h) and at G3 (antenatal). The partition grouped by patient used to estimate the R² of gate G3 is in NB06 | — |
| 13 | Class imbalance | — No model was fitted | — |
| 14 | Fairness | — No model was fitted | — |
| 15 | Model output and thresholds | — No model was fitted | — |
| 16 | Differences between development and evaluation data | — No evaluation | — |
| 17 | Ethics approval and consent | MIMIC-IV: de-identified data, original IRB approval with waiver of consent; access under the PhysioNet credentialed data use agreement with CITI training (README, data access); only aggregate outputs, counts 1–4 shown as "<5". Decision of the Uninorte ethics committee pending | 📝 |

## Open science

| Item | Content | Where | Status |
|---|---|---|---|
| 18a | Funding | Monograph | 📝 |
| 18b | Conflicts of interest | Monograph | 📝 |
| 18c | Protocol and deviations | [`../analysis_plan.md`](../analysis_plan.md) (decisions D1 to D14); OC-A and OC-6h (dated decisions); FW | ✅ |
| 18d | Registration | Not registered; state it | 📝 |
| 18e | Data availability | MIMIC-IV on PhysioNet to credentialed users; not redistributed (README) | ✅ |
| 18f | Code availability, software and versions | GitHub (Tesis-Doctoral/PerinatalMortality_MIMIC-IV); `requirements.txt`; library versions printed in NB01 (S1) | ✅ |
| 19 | Patient and public involvement | None; state it | 📝 |

## Results

| Item | Content | Where | Status |
|---|---|---|---|
| 20a | Flow of participants, with and without the outcome | NB01 and NB04 (universe 25,736 obstetric admissions → population 19,440 → 129 strict events; 99 events with information 7 days before admission, OUT04 Q-A1) | ✅ |
| 20b | Characteristics of the data, predictors, missing values | OUT05 (Q-P2, Q-P3: categorical and continuous predictors; missing values of the design matrix) | ✅ |
| 20c | Development vs evaluation | — No evaluation | — |
| 21 | Participants and events in each analysis | OUT03 (73 of 129 events present at admission + 6 h); OUT06 (19,440 admissions, 129 events, folds of gate G3) | ✅ |
| 22–24 | Model specification, performance, updating | — No model was fitted | — |

## Discussion

| Item | Content | Where | Status |
|---|---|---|---|
| 25 | Overall interpretation | OUT06 (class: feasibility; with the information MIMIC-IV records before the admission, fetal death cannot be predicted); monograph chapter 7 | 📝 |
| 26 | Limitations | OC-A §3 (a death before the 7-day buffer cannot be excluded with codes), CA (codes without date, no mother–newborn link) | ✅ |
| 27a–27b | Input data and users in use | — No use | — |
| 27c | Future research | OC-6h and OC-A (data that would be needed: dated obstetric events, linkage with the newborn record); monograph | 📝 |

No gaps of the repository remain: what is missing are texts of the monograph (📝) and the decision of the Uninorte ethics committee.

*Confidential: internal use of the research project.*
