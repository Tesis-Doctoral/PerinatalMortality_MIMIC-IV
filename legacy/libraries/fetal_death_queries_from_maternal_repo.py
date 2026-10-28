# -*- coding: utf-8 -*-
"""Reference copy (verbatim) of the two dataset queries of the fetal-death model, taken from
libraries/database.py of MaternalMortality_MIMIC-IV on 2026-10-28. Not imported by anything;
migrate them into libraries/database.py when the matching SQL scripts are migrated."""


def get_fetal_death_cohort_query():
    """
    Returns the SELECT that loads the analysis-ready dataset of Modelo C
    (perinatal death, fetal component): mimiciv.cohort_fetal_death_dataset,
    built by sql/04_cohort_perinatal/fetal_death_dataset_en.sql.

    The gdg_* diagnosis-group columns are deliberately NOT selected: they are
    built from the admission's top-4 ICD diagnoses, i.e. from the same coded
    diagnoses that define the outcome (leakage). The SMM columns, the delivery
    flag and the primary SMM category are not selected either. The columns
    outcome_fetal_death, fd_strict, admission_icd_version and gest_weeks are
    returned for outcome definition and sensitivity analyses; the notebook
    removes them from X.
    """
    query = """SELECT subject_id, hadm_id, stay_id, dob, age_at_admission
                      , outcome_fetal_death, fd_strict, admission_icd_version, gest_weeks
                      , ethnicity, insurance, language
                      , admission_type, admission_location
                      , icu_stay, icu_stay_count
                      , heart_rate, respiratory_rate, o2_saturation
                      , pressure_blood_mean, pressure_blood_systolic, pressure_blood_diastolic
                      , temperature_fahrenheit, weight_admission, glucose
                      , hemoglobine, sodium, potassium, noionized_calcium
                      , magnesium, chloride, bicarbonate, phosphorus, creatine
                      , hematrocit, lactic_acid, gcs_eye_opening
                      , gcs_verbal_response, gcs_motor_response, richmond_ras_scale
                      , peep_set, height, anion_gap
                FROM mimiciv.cohort_fetal_death_dataset;"""
    return query


def get_fetal_death_cohort_ext_query():
    """
    Extended dataset of Modelo C (fetal death):
    mimiciv.cohort_fetal_death_dataset_ext, built by
    sql/04_cohort_perinatal/fetal_death_features_en.sql.

    Same base columns as get_fetal_death_cohort_query() plus three feature
    blocks (history of earlier admissions, first-24h CBC, first-24h
    pre-eclampsia panel, outpatient OMR measurements before admission) and days_since_prior_fd, which is NOT a predictor:
    the notebook uses it to drop admissions of the same pregnancy as an earlier
    fetal-death admission. gdg_*, SMM columns and the delivery flag are not
    selected (leakage control).
    """
    query = """SELECT subject_id, hadm_id, stay_id, dob, age_at_admission
                      , outcome_fetal_death, fd_strict, admission_icd_version, gest_weeks
                      , days_since_prior_fd
                      , ethnicity, insurance, language
                      , admission_type, admission_location
                      , icu_stay, icu_stay_count
                      , heart_rate, respiratory_rate, o2_saturation
                      , pressure_blood_mean, pressure_blood_systolic, pressure_blood_diastolic
                      , temperature_fahrenheit, weight_admission, glucose
                      , hemoglobine, sodium, potassium, noionized_calcium
                      , magnesium, chloride, bicarbonate, phosphorus, creatine
                      , hematrocit, lactic_acid, gcs_eye_opening
                      , gcs_verbal_response, gcs_motor_response, richmond_ras_scale
                      , peep_set, height, anion_gap
                      , hx_hypertension, hx_diabetes, hx_obesity, hx_renal_disease
                      , hx_prior_fetal_death_1y
                      , lab_hemoglobin, lab_hematocrit, lab_platelets, lab_wbc, lab_mcv, lab_rdw
                      , lab_creatinine, lab_alt, lab_ast, lab_uric_acid, lab_urea_nitrogen
                      , lab_urine_prot_creat
                      , omr_sbp_last, omr_dbp_last, omr_sbp_max, omr_dbp_max
                      , omr_weight_kg_last, omr_bmi_last, omr_n_visits_365, omr_days_since_last
                FROM mimiciv.cohort_fetal_death_dataset_ext;"""
    return query
