# Framework for outcome models in MIMIC-IV — mockup

Draft mockup, version 0.1, written on 2026-10-29. Nothing here is implemented as shared code yet. It is built from two real cases, the maternal project (`MaternalMortality_MIMIC-IV`: severe maternal morbidity and maternal death) and this project (perinatal death before birth), and leaves a slot for the neonatal model. The status of the maternal case comes from its README, its analysis plan of the notebooks and its count audit; the status of this project comes from [`analysis_plan.md`](analysis_plan.md) and [`count_audit.md`](count_audit.md). The neonatal case has not been mapped. Spanish version: [`framework_es.md`](framework_es.md). An interactive view of the stage map is the artifact "Framework de desenlaces MIMIC-IV".

## 1. Why a framework

The maternal project went through the same path that this one is following: an exploratory first model (maternal mortality), a count audit that showed how few events there were, a revision of the labels, a pivot to severe maternal morbidity as the main outcome with maternal death kept as a feasibility question, sensitivity analyses and reporting. Writing that path once, as stages with fixed inputs and outputs, turns a new outcome into a module instead of a new project, and it shows which steps a model skipped.

## 2. Principles that do not change

1. **Audit before model.** Counts that decide the design (population, unit, definition, timing, sample size) are measured and recorded before any model is fitted.
2. **No overlap and no selection by outcome.** A cohort rule is first measured as a column and only then applied as a filter, with its sensitivity analysis.
3. **The label is a documented proxy.** A verified code catalogue (official title, tier, source, date) and a label table with one row per unit, where the sensitivity definitions are columns, not filters.
4. **Patient-grouped validation, everything inside the training part.** Imputation, scaling, tuning, stacking and recalibration are fitted inside each training fold.
5. **Prediction point and information window are fixed before the predictors.** Diagnoses of the same admission are not predictors in the main model.
6. **Every choice is a numbered decision** (D1, D2, …) with its evidence, and a sensitivity analysis when the choice could change the result.
7. **Aggregate outputs only.** No `subject_id`, `hadm_id` or `stay_id` in any published result.
8. **Reproducibility.** Fixed configuration, certified expected counts that stop a run when the population is not the audited one, SQL scripts in EN/ES pairs checked by script, TRIPOD+AI reporting.

## 3. Architecture

Three layers and the gates between stages. The **method** layer is everything that does not depend on the dataset or the outcome: the stages, the validation, the stacked ensemble, the metrics and the reporting. The **data adapter** is the code that turns one dataset into the table the method reads (SQL for MIMIC-IV today; the neonatal dataset and the data of a health entity will need their own). The **outcome module** is the small set of choices that define one outcome (section 5). The **gates** are the decisions that must be recorded before the next stage starts. The method never reads a dataset directly: it reads the contract table of section 3.1.

![Path to a defensible model: stages E0 to E11, three decision gates, stacked ensemble inside E8, feasibility branch and the prevention stage E10](framework_flow.svg)

*Figure. The path of every outcome. Dots mark the stages where the outcome card enters; squares mark the stages that depend on the data adapter; the amber dashed path is the feasibility branch; the dashed teal block is the proposed prevention stage.*

The path through the stages is the same for every outcome. What changes is the outcome card that feeds E1, E2, E5, E6, E9 and E10. The gate at E7 is where the maternal project decided that maternal death (3 events among the eligible deliveries) could only be a feasibility analysis while severe maternal morbidity (445 events) could be modelled.

## 3.1 Data contract

Whatever the dataset, an adapter has to deliver one table with one row per unit of analysis and these columns. Stages E4 to E11 run from that table only.

| Column | Meaning | MIMIC-IV adapter today |
|---|---|---|
| `unit_id` | Identifier of one unit of analysis | `hadm_id` |
| `group_id` | What must never be split between training and test | `subject_id` (patient) |
| `t0` | Time zero | Admission time |
| `t_pred` | Prediction point | `t0` + 6 h (perinatal), `t0` + 24 h (maternal) |
| `label_*` | Main label and sensitivity labels, as columns | `fetal_death_label_v2`, `label_admission_v2` |
| `x_*` with its availability time | Predictors and the moment each value became known | Predictors table of the 24-hour window rule |
| `period` | Calendar period or coding era, if the dataset has one | ICD version, anchor-year group |

Rules for any adapter: one row per unit; no personal identifier leaves the database; the counts reproduce the expected counts of the configuration; the same table feeds the audit and the models. If a dataset has no group identifier or no timestamps, the adapter must say so and the framework records the decision (for the neonatal dataset: the mother or the newborn as group, and whether E4 applies).

## 3.2 Which layer owns each stage

| Stage | Layer |
|---|---|
| E0 Governance | Method |
| E1 Universe and population | Data adapter |
| E2 Outcome definition | Outcome module, reading the adapter's code tables |
| E3 Count audit | Method structure (groups A–F), adapter queries |
| E4 Unit of analysis and overlap | Data adapter |
| E5 Prediction point and window | Outcome module, using the adapter's timestamps |
| E6 Predictors | Data adapter and outcome module |
| E7 Feasibility gate | Method |
| E8 Modelling, validation and metrics | Method |
| E9 Sensitivity and robustness | Method, plus the outcome's own set |
| E10 From prediction to prevention strategy | Method, outcome module and the health entity |
| E11 Reporting | Method |
## 4. Stage map

Stages are numbered E0 to E11 (E from the Spanish etapa) so that they do not clash with the sensitivity analyses S1–S11 of the analysis plan.

| Stage | Question it answers | Reused part (method, or the MIMIC-IV adapter) | Outcome parameter |
|---|---|---|---|
| E0 Governance and configuration | What is fixed before anything runs so that analyses are comparable? | Decision register, tracking workbook, seed and fixed settings (5 × 3 folds, bootstrap, trees), expected counts, EN/ES script pairs | Configuration file of the outcome (proposal FD2) |
| E1 Universe and population | Which admissions can be studied? | Obstetric universe tables (`cohort_obstetric_v2`, `hadm_delivery_v2`, `obstetric_dx_v2`) | Population rule |
| E2 Outcome definition | What exactly counts as an event, and from which sources? | Code catalogue structure (tier, title, source, date); label table, one row per unit, sensitivities as columns | The code list and the tiers |
| E3 Count audit | How many events, where, when and with what overlap? | Groups A–F: base, events, patient overlap, era, eligibility and timing, predictors | Events per definition |
| E4 Unit of analysis and overlap | What is one record, and who appears on both sides of a split? | Unit columns (admission rank, gap, pregnancy chain, first admission) without outcome columns; simulation of admission-level splitting | None |
| E5 Prediction point and window | When is the prediction made and what may it use? | Time zero, prediction point, information window, eligibility, events lost, no same-admission diagnoses | The prediction point |
| E6 Predictors | Which variables, with what coverage and limits? | Dictionary, 10% coverage rule, plausibility limits, missingness indicators | Outcome-specific blocks |
| E7 Feasibility gate | Are there enough events to model? | Riley criteria, events per parameter, decision: full model or feasibility only | None |
| E8 Modelling, validation and metrics | How well does it work, with what uncertainty? | Patient-grouped nested validation and leak-free pipeline; base models (logistic regression, random forest, extra trees, XGBoost); **stacked ensemble with a logistic meta-learner as the default strategy**, always compared with logistic regression and with the best base model under the same validation; recalibration, patient-level bootstrap, calibration, decision curve, paired differences | None |
| E9 Sensitivity and robustness | Does the result survive other reasonable choices? | Resampling, era and ICD version, temporal validation, availability indicators, timing of events against the prediction point | The outcome's own sensitivity set |
| E10 From prediction to prevention strategy | How does the risk estimate become a decision and an action in a health entity? | Risk tiers and thresholds taken from the decision curve and the events captured in the top 5% and 10% of risk, tied to the entity's capacity; actionable against non-actionable predictors; subgroup and equity check; alert design with human validation; local validation and recalibration before use; monitoring of calibration | The actions the entity can take for that outcome, defined with its clinical team |
| E11 Reporting | What is delivered? | TRIPOD+AI, code-list supplements, missingness tables, aggregate output files | Outcome text |

## 4.1 Stacking inside E8

Stacking is the modelling strategy of the framework, and it is what the maternal and neonatal studies have in common (the neonatal manuscript is a stacked ensemble; the maternal severe-morbidity model uses a stacked ensemble with a logistic meta-learner). What the framework fixes is how it is built and how it is judged:

*Drawn inside stage E8 of the figure in section 3: four base models, out-of-fold predictions, logistic meta-learner, Platt recalibration, and the paired comparison.*

1. Base models and the meta-learner are tuned in nested folds; the meta-learner sees only out-of-fold predictions.
2. Recalibration is fitted inside the training part and reported as part of the whole procedure.
3. The stack is never reported alone: the framework requires the paired difference against regularized logistic regression and against the best base model, with patient-level bootstrap intervals. In the maternal study the gain of the stack over logistic regression was small (AUROC +0.009, 95% interval 0.002 to 0.016) and there was no difference from XGBoost, so the comparison is part of the result, not a formality.
4. Whatever the outcome, the same four base models and the same meta-learner are used, so the outcomes can be compared with each other.

## 4.2 E10 in detail: from prediction to prevention strategy

The thesis title asks for models that support prevention strategies and action plans in health entities, so the framework needs a stage after the model is validated. This stage is a proposal: none of the three outcomes has gone through it, and the maternal manuscript states that its models are research prototypes that must not guide individual clinical decisions. Its deliverable is a one-page strategy sheet per outcome:

1. Risk tiers and the threshold of each tier, with the reason (for example the share of events captured in the top 5% and 10% of risk and the decision-curve range), and the entity's capacity to act on each tier.
2. Which predictors can be acted on or monitored and which only describe the patient.
3. Performance and calibration by subgroup (age band, insurance type, ICD era), reported even when it is poor.
4. Who receives the alert, who validates it (a responsible clinician) and which action follows.
5. Local validation and recalibration with the entity's own data before any use, because the models are built on one US hospital.
6. A monitoring metric and a review date (calibration drift, event rate).

## 5. Outcome module

A module is a card with the fields below. Filling it is the only thing a new outcome has to do before the stages run. The perinatal column is filled from this project; the maternal columns from the maternal project; the neonatal column lists what has to be defined.

| Field | Severe maternal morbidity | Maternal death | Perinatal death before birth | Neonatal (slot) |
|---|---|---|---|---|
| Dataset | MIMIC-IV | MIMIC-IV | MIMIC-IV | Not MIMIC-IV; not available yet |
| Status | Manuscript in revision | Feasibility only | In progress: audit and label done | Manuscript exists; not mapped |
| Unit | Delivery hospitalization | Delivery hospitalization | Delivery hospitalization (D4) | To define (neonatal stay) |
| Population | Delivery hospitalizations still in hospital at 24 h: 19,383 | Same | Delivery flag or stillbirth code (D3): 19,440 | To define |
| Event definition | At least one of the 20 active CDC indicators (ICD-9-CM, ICD-10-CM/PCS) | Death in the same admission | Strict code of fetal death at any gestational age; tiers strict, partial, excluded | To define |
| Events | 445 (2.30%) | 3 | 142 with partial codes, 129 strict | To define |
| Event time | Diagnosis codes without time; procedure codes with a date | Death time | None: discharge code | To confirm |
| Prediction point | 24 h after admission | 24 h | Admission + 6 h (D6) | To define |
| Label table | `label_admission_v2` (model B) | Same table (model A) | `fetal_death_label_v2` | To define |
| Sample-size gate | Passed: full model | Failed: feasibility | Pending (D12) | To define |
| Own sensitivity set | Creatinine indicator, renal-only, timing against the prediction point | None | Strict plus partial, 22 and 28 weeks, early-loss codes excluded (S1–S11 of the plan) | To define |
| Use in the entity (E10) | Not yet: the manuscript calls the models research prototypes, not for individual decisions | Not applicable | To define | To define |
| Known hazard | Missing creatinine encodes who was tested | Too few events | Label has no time; pre-viable losses; weeks only in ICD-10 | To define |

## 6. Outcome ladder

A pattern that the maternal project followed and that this project is following: a target outcome is first audited; if the audit shows too few events at the prediction point, a related outcome with more events becomes the main model and the target is kept as a feasibility analysis.

*Drawn as the feasibility branch of the figure in section 3: gate 3 sends an outcome with too few events to a feasibility analysis, and an outcome with enough events to the full model.*

In the maternal project the target was maternal death and the related outcome was severe maternal morbidity. For perinatal death before birth the audit found 129 strict events in 19,440 admissions; the decision D12 will say whether that is enough for the full model.

## 7. Maturity by stage

Status as of 2026-10-29. "Shared" means the stage is the same as for severe maternal morbidity.

| Stage | Severe maternal morbidity | Maternal death | Perinatal death before birth | Neonatal |
|---|---|---|---|---|
| E0 Governance | Done | Shared | In progress (D9–D14 open) | To map |
| E1 Universe and population | Done | Shared | Done (D1, D3) | To map |
| E2 Outcome definition | Done (official CDC list) | Done | Done (T15, T16) | To map |
| E3 Count audit | Done | Done | Groups A–E done, group F pending | To map |
| E4 Unit and overlap | Done (notebook 01) | Shared | Pending (T17, T13) | To map |
| E5 Prediction point and window | Done (24 h) | Shared | Decided (D6–D8), table pending | To map |
| E6 Predictors | Done | Shared | Pending (group F) | To map |
| E7 Feasibility gate | Done: full model | Done: feasibility only | Pending (D12) | To map |
| E8 Modelling and validation | Done (notebook 02) | Not modelled | Pending | To map |
| E9 Sensitivity | Done (notebooks 03–07) | Not applicable | Defined (S1–S11), not run | To map |
| E10 Prediction to strategy | Pending | Not applicable | Pending | To map |
| E11 Reporting | In revision (TRIPOD+AI done) | In the same manuscript | Pending | To map |

The dataset for the neonatal module is not MIMIC-IV and is not available yet. The neonatal manuscript (a stacked ensemble on 20,982 neonatal admissions) uses interquartile-range outlier removal and skewness-driven imputation in its preprocessing. Mapping it to E6 and E8 would show whether those steps were fitted inside the training folds, which the abstract does not say; that has to be checked before any claim.

## 8. Folder skeleton

Proposed common skeleton, with where each project stands today. The split follows the three layers.

| Proposed | Holds | Maternal project today | This project today |
|---|---|---|---|
| `method/` | Notebooks and code that read the contract table: validation, stacking, metrics, sensitivity, reporting | `notebooks/`, `libraries/functions.py` | `notebooks/` (exploratory, to be rebuilt) |
| `adapters/<dataset>/` | SQL or code that produces the contract table from one dataset | `sql/01_load_mimic_iv_schema/`, `02_cohort_mortality/`, `03_cohort_smm/`, the base of `04_labels/`, `05_predictors/` | Uses the maternal tables; new `sql/00_mimic_layer/` |
| `outcomes/<outcome>/` | Outcome card, code catalogue, label script, sensitivity set | `04_labels/` | `sql/01_labels/` |
| `audit/<outcome>/` | Count audit scripts and write-up | `06_audit_counts/`, `revision_audit_counts.md` | `sql/02_audit_counts/`, `count_audit.md` |
| `docs/` | Plan, TRIPOD+AI, code lists, strategy sheets (E10) | `analysis_plan_notebooks.md`, `docs/` | `analysis_plan.md`, workbook |

## 9. Open design decisions for the framework

| ID | Decision | Options | Recommendation |
|---|---|---|---|
| FD1 | Where the method layer lives | The maternal repository stays the home of the shared code and the others depend on it (today); one monorepo with method, adapters and outcomes; a separate method repository | Keep the first option while the maternal manuscript is in revision; move to a monorepo after publication |
| FD2 | Outcome configuration | One file per outcome (population, label table, prediction point, window, expected counts, thresholds) read by the audit scripts and notebooks; values written inside each script | One file per outcome |
| FD3 | Unit-of-analysis columns | A table per dataset adapter with no outcome columns; columns inside each outcome's label table | A table per adapter, without outcome columns, joined to the label table in the audit; for MIMIC-IV `sql/00_mimic_layer/01_unit_of_analysis.sql` |
| FD4 | Names | A common pattern for outcome identifiers, `*_v2` suffix and `<outcome>_label_v2` tables | Adopt the pattern already used (`fetal_death_label_v2`) |
| FD5 | Neonatal | The dataset is not MIMIC-IV and is not available yet; it defines the adapter, the group identifier (mother or newborn) and whether E4 applies | Decide when the dataset arrives; the contract is written so that nothing in E7 to E11 depends on that choice |
| FD6 | Contract format | A written specification only; or a specification plus a check script that validates any adapter's table (required columns, types, one row per unit, expected counts) | Specification plus check script |

## 10. What this means for T17

T17 is the MIMIC-IV adapter of stage E4. The unit-of-analysis columns (admission rank within the patient, days since the previous admission, first admission, pregnancy chain at 30, 90 and 180 days) do not depend on the outcome, so they become a table with no outcome columns, `unit_of_analysis_v2`, written in `sql/00_mimic_layer/01_unit_of_analysis.sql` and valid only for MIMIC-IV. The event counts per unit (already measured in Q-C4) come from joining it with `fetal_death_label_v2` in the audit, and the same table serves severe maternal morbidity. Another dataset will need its own table with the same contract columns (section 3.1).

## 11. Fit with the thesis title

Title: *Framework for the construction of predictive models that support the formulation of prevention strategies and action plans in health entities against maternal, perinatal and neonatal deaths.*

| Element of the title | Where the framework covers it | What is missing |
|---|---|---|
| Framework for building predictive models | E0 to E9 and E11 | Nothing at this level |
| Maternal, perinatal and neonatal deaths | Outcome module with three slots; the outcome ladder explains why maternal death is a feasibility analysis and severe morbidity the modelled proxy | Neonatal mapping; the thesis must say plainly which outcomes are modelled deaths and which are proxies |
| Prevention strategies and action plans | E10 (proposed) | Not yet applied to any outcome |
| In health entities | E10 items 5 and 6: local validation and monitoring, through a data adapter written for the entity's data | No local data yet; MIMIC-IV is a single US hospital |

A framework drawn from two cases is a generalisation, not yet a validation; the neonatal case would be the third test.

*Confidential: internal use of the research project.*
