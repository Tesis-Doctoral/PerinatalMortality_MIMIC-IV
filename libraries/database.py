# -*- coding: utf-8 -*-
"""
database.py -- Perinatal death (fetal component) models, MIMIC-IV

Connection helpers for the local PostgreSQL instance that holds the MIMIC-IV schema
(the same database used by the companion project MaternalMortality_MIMIC-IV).
All parameters come from environment variables (see .env.example), so no credential
is ever committed. The functions get_fetal_death_cohort_query() and
get_fetal_death_cohort_ext_query() return the SELECT statements that load the
tables built by sql/fetal_death_dataset.sql and sql/fetal_death_features.sql.
"""
import os
import sqlalchemy as alchemy

# Optional: load variables from a local .env file if python-dotenv is installed.
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


def get_connect_database():
    """Return a SQLAlchemy engine for the local MIMIC-IV PostgreSQL database.

    MIMICIV_DB_PASSWORD has no default on purpose: the function raises if it is
    missing, rather than connecting with a blank password.
    """
    driver = "postgresql+psycopg2"
    user = os.environ.get("MIMICIV_DB_USER", "postgres")
    password = os.environ.get("MIMICIV_DB_PASSWORD")
    host = os.environ.get("MIMICIV_DB_HOST", "localhost")
    port = os.environ.get("MIMICIV_DB_PORT", "5433")
    database = os.environ.get("MIMICIV_DB_NAME", "mimiciv")

    if not password:
        raise RuntimeError(
            "MIMICIV_DB_PASSWORD is not set. Copy .env.example to .env, fill in your "
            "own local Postgres password, and make sure python-dotenv is installed "
            "(see requirements.txt)."
        )

    return alchemy.create_engine(f"{driver}://{user}:{password}@{host}:{port}/{database}")


def disconnect_database(engine):
    engine.dispose()


def get_fetal_death_cohort_query():
    """
    Returns the SELECT that loads the base analysis-ready dataset of the fetal-death
    model (perinatal death, fetal component): mimiciv.cohort_fetal_death_dataset,
    built by sql/fetal_death_dataset.sql.

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
    Extended dataset of the fetal-death model:
    mimiciv.cohort_fetal_death_dataset_ext, built by
    sql/fetal_death_features.sql.

    Same base columns as get_fetal_death_cohort_query() plus four feature
    blocks (history of earlier admissions, first-24h CBC, first-24h
    pre-eclampsia panel, outpatient OMR measurements before admission) and
    days_since_prior_fd, which is NOT a predictor: the notebook uses it to drop admissions of the same pregnancy as an earlier
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
