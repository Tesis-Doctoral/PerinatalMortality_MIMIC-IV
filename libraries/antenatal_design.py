# -*- coding: utf-8 -*-
"""Design matrix of the antenatal model (return R3): the 27 candidate parameters of the outcome card
(docs/outcome_card_antenatal.md, section 4), fixed with the count audit before any model.
Used by notebooks 05 (stage S7) and 06 (gate G3), so both read exactly the same matrix."""
import pandas as pd

# block of the outcome card -> columns of the design matrix
BLOCKS = {
    "registration": ["age", "race_Black", "race_Hispanic", "race_Asian", "race_Other or unknown", "ins_Medicaid",
                     "ins_Medicare_other_missing", "english", "marital_Not_married", "marital_Missing"],
    "history of care": ["any_prior_admission", "prior_admission_90d"],
    "conditions in earlier admissions": ["hx_cesarean", "hx_hypertensive_pregnancy", "hx_chronic_hypertension",
                                         "hx_pregestational_diabetes", "hx_gestational_diabetes", "hx_substance_use",
                                         "hx_thyroid_disease", "hx_adverse_pregnancy_outcome",
                                         "hx_other_high_risk_chronic"],
    "current pregnancy, outpatient measurements": ["last_sbp", "last_dbp", "any_elevated_bp", "last_bmi"],
    "current pregnancy, laboratory": ["last_hemoglobin"],
    "indicator": ["had_prenatal_care_here"],
}

# reduced set fixed before any model (outcome card, section 5); used only if gate G3 failed with the 27 parameters
REDUCED_SET = ["age", "race and ethnicity (4 parameters)", "Medicaid", "English", "married",
               "had prenatal care in this hospital", "last systolic pressure", "elevated pressure (140/90 or more)",
               "body mass index", "hemoglobin", "hypertensive history (chronic or in an earlier pregnancy)",
               "diabetes (pregestational or gestational in an earlier pregnancy)", "adverse outcome in an earlier pregnancy"]
REDUCED_PARAMETERS = 17          # as fixed in the outcome card

# information that never enters (gate G2): it describes how the patient arrived or comes from the same admission
EXCLUDED_COLUMNS = ["admission_type", "admission_location", "discharge_location", "edregtime", "drg_code"]


def design_matrix(d):
    """The 27 candidate parameters of the outcome card (section 4). Reference levels:
    White, Private, Married."""
    X = pd.DataFrame(index=d.index)
    X["age"] = d["age"].astype(float)
    for g in ["Black", "Hispanic", "Asian", "Other or unknown"]:
        X[f"race_{g}"] = (d["race_group"] == g).astype(float)
    X["ins_Medicaid"] = (d["insurance_group"] == "Medicaid").astype(float)
    X["ins_Medicare_other_missing"] = (d["insurance_group"] == "Medicare, other or missing").astype(float)
    X["english"] = d["english"].astype(float)
    X["marital_Not_married"] = (d["marital_group"] == "Not married").astype(float)
    X["marital_Missing"] = (d["marital_group"] == "Missing").astype(float)
    for c in ["any_prior_admission", "prior_admission_90d",
              "hx_cesarean", "hx_hypertensive_pregnancy", "hx_chronic_hypertension",
              "hx_pregestational_diabetes", "hx_gestational_diabetes", "hx_substance_use",
              "hx_thyroid_disease", "hx_adverse_pregnancy_outcome", "hx_other_high_risk_chronic"]:
        X[c] = d[c].astype(float)
    X["last_sbp"] = d["last_sbp"].astype(float)
    X["last_dbp"] = d["last_dbp"].astype(float)
    X["any_elevated_bp"] = d["any_elevated_bp"].astype(float)
    X["last_bmi"] = d["last_bmi"].astype(float)
    X["last_hemoglobin"] = d["last_hemoglobin"].astype(float)
    X["had_prenatal_care_here"] = d["had_prenatal_care_here"].astype(float)
    return X
