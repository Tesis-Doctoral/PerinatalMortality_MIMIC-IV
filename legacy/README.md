# legacy/

Earlier material of the fetal-death model ("Modelo C"), **copied unchanged** on 2026-10-28 from the backup of `MaternalMortality_MIMIC-IV` (`article/backup/cleanup_2026-10-27/`). The four SQL scripts have since been reviewed and migrated to `../sql/` (without the `_en` suffix and with `_es` versions; code unchanged), so the copies in `legacy/sql/` are kept only as a reference for the original wording. The notebook was migrated to `../notebooks/01_fetal_death_models.ipynb` and the two dataset queries to `../libraries/database.py` (query text unchanged; only comments and docstrings updated).

| File | What it is |
|---|---|
| `sql/perinatal_feasibility_en.sql` → migrated to `../sql/perinatal_feasibility.sql` | Feasibility check: how many admissions carry a fetal-death code (reads only; temporary tables) |
| `sql/fetal_death_dataset_en.sql` → migrated to `../sql/fetal_death_dataset.sql` | Builds `mimiciv.cohort_fetal_death_dataset` (outcome strict/partial, ICD version, gestational weeks) |
| `sql/perinatal_feature_discovery_en.sql` → migrated to `../sql/perinatal_feature_discovery.sql` | Feature discovery: which extra predictors exist, how often, and whether they differ by outcome |
| `sql/fetal_death_features_en.sql` → migrated to `../sql/fetal_death_features.sql` | Builds `mimiciv.cohort_fetal_death_dataset_ext` (history, first-24 h blood count and panel, outpatient measurements) |
| `notebooks/maternal_fetal_death_models.ipynb` → migrated to `../notebooks/01_fetal_death_models.ipynb` | Models of the fetal-death outcome (30 cells) |
| `libraries/fetal_death_queries_from_maternal_repo.py` → migrated to `../libraries/database.py` | Verbatim copy of the two dataset queries used by the notebook |

Migration finished on 2026-10-28 (SQL scripts, queries, notebook). Everything here is also in `MaternalMortality_MIMIC-IV/article/backup/cleanup_2026-10-27/`, so this folder can be deleted once you have checked the migrated files.

# legacy/ (español)

Material anterior del modelo de muerte fetal ("Modelo C"), **copiado sin cambios** el 28/10/2026 desde el respaldo de `MaternalMortality_MIMIC-IV` (`article/backup/cleanup_2026-10-27/`). Los cuatro scripts SQL ya se revisaron y migraron a `../sql/` (sin el sufijo `_en` y con versiones `_es`; código sin cambios), por lo que las copias de `legacy/sql/` se conservan solo como referencia de la redacción original. El notebook se migró a `../notebooks/01_fetal_death_models.ipynb` y las dos consultas de los conjuntos de datos a `../libraries/database.py` (texto de las consultas sin cambios; solo se actualizaron comentarios y docstrings). Migración terminada el 28/10/2026 (scripts SQL, consultas, notebook). Todo lo que hay aquí también está en `MaternalMortality_MIMIC-IV/article/backup/cleanup_2026-10-27/`, por lo que esta carpeta puede eliminarse cuando hayas revisado los archivos migrados.
