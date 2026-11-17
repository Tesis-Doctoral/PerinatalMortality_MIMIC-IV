# Outcome card — perinatal death before birth (fetal death), MIMIC-IV

Version 1, 2026-11-17. Card of the second application of the staged framework ([`../framework.md`](../framework.md), version 1.0). Filled from [`../analysis_plan.md`](../analysis_plan.md) (decisions D1 to D14) and [`../count_audit.md`](../count_audit.md). Fields marked **pending** must be fixed, and recorded in the decision log, before the gate that needs them. Spanish version: [`outcome_card_fetal_death_es.md`](outcome_card_fetal_death_es.md).

## 1. Identity

| Field | Value | Source |
|---|---|---|
| Outcome | Perinatal death before birth (fetal death or stillbirth), always labelled a proxy; early neonatal deaths are not captured | D2 |
| Rung on the outcome ladder | Ideal outcome of the perinatal slot (first rung). Rungs below: **pending** (section 6) | — |
| Data source and adapter | MIMIC-IV v3.1; tables of the revised maternal project plus `unit_of_analysis_v2` | D1, T17 |
| Unit of analysis | Delivery hospitalization; patient as grouping unit; 90-day pregnancy chain as sensitivity | D4 |
| Population | Delivery flag (v2) or stillbirth code: 19,440 admissions; 19,437 at the prediction point | D3, D8 |

## 2. Event (S3)

| Field | Value | Source |
|---|---|---|
| Main definition | Strict code at any gestational age: ICD-10-CM O36.4, Z37.1, Z37.4, Z37.7; ICD-9-CM 656.4, V27.1, V27.4, V27.7 | D5, T15 |
| Events (expected count) | 129 strict (0.66%); 142 with partial codes | T16 |
| Label table | `mimiciv.fetal_death_label_v2` (one row per admission; sensitivity definitions as columns) | T16 |
| Event time | **None**: discharge diagnosis codes without a date. 65 of 129 events (50%) have a fetal-death code as principal diagnosis; procedure codes carry a date | Q-T16, Q-E4 |
| Timing classes | **Pending (new task, see section 5).** Needed for criteria C1 and C2 and for gate G1 | — |
| Known hazards | No event time; pre-viable losses inside the label (10 strict events with an early-loss code); gestational weeks only in ICD-10; rate rises with calendar period (5.2 to 12.9 per 1,000) | count audit |

## 3. Prediction point, window and predictors (S6, S7)

| Field | Value | Source |
|---|---|---|
| Time zero | Admission time | D7 |
| Prediction point | Admission + 6 hours; 12 h, 24 h and retrospective classification as sensitivities | D6 |
| Window | From 24 h before admission to the prediction point | D7 |
| Excluded | Same-admission diagnoses, procedures, DRG codes and treatments (main model) | D9 (proposed) |
| Candidate predictors | **Pending (group F, tasks T22–T25; D10).** Blocks: registration variables and age, history from earlier admissions, blood count and chemistry in the window, outpatient measurements (OMR), each with a missingness indicator | analysis plan |
| Candidate parameters | **Pending.** Count every category and every missingness indicator | — |

## 4. Sample size and learner (G3, S8)

| Field | Value | Source |
|---|---|---|
| Pre-estimate of supported parameters | With 19,437 admissions and 129 events (prevalence 0.0066, maximum Cox-Snell R² 0.077), the shrinkage criterion supports about **17 parameters** if the R² is 10% of its maximum and about **25** if it is 15%. For reference, the SMM model reached 16% and the escalation model 12%. Calculation by the assistant; the gate uses the observed R² | Riley et al. |
| Primary learner | Penalized logistic regression, because the events per candidate parameter will be below 20 (129 events / 17–25 parameters ≈ 5–8). Random forest, extra trees, XGBoost and the stacked ensemble are comparisons. Consistent with D11 | D11; framework rule of 2026-11-11 (pending validation) |
| Reduced predictor set | **To fix before G3** (sample-size reduction). Proposed rule, as in the SMM study: keep age and the core laboratory values with their missingness indicators; collapse insurance, language, admission type and admission location into binary indicators; group race and ethnicity into five categories; drop blocks with low coverage first. Never chosen by association with the outcome | framework, section 4 |
| If G3 fails | Feasibility analysis (D12) and return R1 to the next rung | D12 |

## 5. Classification criteria (G4)

Fixed before any model. The thresholds are those of the framework (section 4).

| Criterion | How it applies to this outcome | Status |
|---|---|---|
| C1, events already present | Landmark population = admissions without a fetal death already present at the prediction point. Because the label has no time, presence must come from proxies. Candidates to measure: an intrauterine-death code (O36.4, 656.4: care for a known fetal death); a fetal-death code as principal diagnosis (reason for admission); ICU admission before the prediction point; delivery or induction procedure dated on the admission day. Each proxy is first counted, then the rule is fixed | **Pending: new count task** |
| C2, outcome with time | Needs events dated after the prediction point. ICD codes cannot separate an antepartum from an intrapartum death, and newborn records are not linked. Unless the timing task finds a dated subset, C2 cannot be tested | **Probably not testable** |
| C3, detection bias | The outcome is not defined from a laboratory test, so detection does not depend on who was tested in the data | Not applicable (proposed) |
| C4, stability over time | Development before 2017 and a single test from 2017 onward, as in the SMM study; cut at 2015 (ICD transition) as sensitivity. The rising rate (5.2 to 12.9 per 1,000) makes calibration drift likely | Applicable; events per period **pending** |

**What to expect, stated before the results.** The count audit already found that fetal death is often present at arrival and that the label has no time. If C2 cannot be tested, the best possible class is early identifier, whatever the AUROC. That is a legitimate result of the framework: it would stop the claim that the model predicts fetal death.

## 6. Returns available

| Return | Option for this outcome | Status |
|---|---|---|
| R1 | Next rung if G3 fails: a more frequent surrogate on the same path (for example fetal growth restriction or a composite of adverse fetal outcome codes) | **Pending**: candidates to count |
| R2 | An outcome dated after the prediction point: none identified yet (intrapartum death cannot be separated) | **Pending** |
| R3 | Another prediction point: arrival (registration data only) or 12–24 h | Possible (D6 sensitivities) |
| R4 | More or different predictors: outpatient records (OMR) or history blocks | Possible (group F) |

At most two returns.

## 7. Sensitivity set (S9)

SA1 to SA11 of [`../analysis_plan.md`](../analysis_plan.md), section 7 (renamed from S1–S11 on 2026-11-17 so that they do not clash with the stages). The criteria C1 to C4 are added to them.

## 8. Next tasks, in the order the gates need them

1. Run T17 (`unit_of_analysis_v2`) and Q-C5 (T13). → S5.
2. New task: timing classes of the fetal-death events from the proxies of section 5, and the decision on C1 and C2. → S3, G1.
3. Group F of the count audit (T22–T25) and decisions D9, D10. → S7.
4. Count the candidate parameters, fix the reduced predictor set and record the primary learner. → before G3.
5. Sample-size check with the observed Cox-Snell R² (D12). → G3.

*Confidential: internal use of the research project.*
