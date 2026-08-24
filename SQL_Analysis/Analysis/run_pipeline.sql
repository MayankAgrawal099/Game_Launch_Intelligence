-- ============================================================
-- run_pipeline.sql
-- Gaming Launch Intelligence
-- FINAL SQL EXECUTION ORDER
-- ============================================================
--
-- IMPORTANT:
--   Phase 1 Python must be executed BEFORE this SQL pipeline if
--   Phase 5 is expected to contain success probabilities.
--
--   The pipeline is:
--
--   01 -> 02 -> 03 -> 03a -> 03b -> 04 -> 05
--        -> 07 -> 06a -> 08 -> 06
--
--   06 is intentionally the LAST analytical/export file.
--
-- Before running:
--   1. Confirm database/schema is correct.
--   2. Confirm Phase 1 model CSV exists.
--   3. Set the `model_csv` and `export_dir` variables.
--
-- Example:
--
-- \set model_csv 'C:/.../Python_Analysis/results/model/model_success_predictions.csv'
-- \set export_dir 'C:/.../Python_Analysis/results/sql_exports'
--
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- Existing project setup/data-model files
\i '01_setup_and_load.sql'
\i '02_data_quality_and_cleaning.sql'
\i '03_data_model.sql'

-- Phase 3
\i '03a_source_architecture.sql'

-- Phase 4 compatibility
\i '03b_compatibility_check.sql'

-- Phase 2
\i '04_market_analysis.sql'
\i '05_launch_decision.sql'

-- Phase 4
\i '06_launch_timing.sql'

COMMIT;

-- ------------------------------------------------------------
-- Python -> PostgreSQL bridge
-- This file creates the table. The actual CSV import is
-- performed by the \copy command in 06a.
-- ------------------------------------------------------------

\set model_csv 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/Python_Analysis/outputs/model_success_predictions.csv'

\copy analysis.model_success_predictions FROM :'model_csv' WITH CSV HEADER;

-- Build scenario-level prediction table/view.
\i '06a_load_model_predictions.sql'

-- Phase 5
\i '07_final_decision_engine.sql'

-- Final export
\set export_dir 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/results'
\i '08_export_results.sql'
