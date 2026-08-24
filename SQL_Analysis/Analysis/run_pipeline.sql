-- ============================================================
-- run_pipeline.sql
-- Gaming Launch Intelligence
-- FINAL SQL EXECUTION ORDER
-- ============================================================
--
-- Required order:
--
--   01 -> 02 -> 03 -> 03a -> 03b -> 04 -> 05 -> 06
--        -> 06a -> COPY MODEL -> 07 -> 08
--
-- 08 is intentionally the FINAL export layer.
--
-- Before running:
--   1. Execute Python notebooks through 05.
--   2. Confirm this file is executed from SQL_Analysis/Analysis.
--   3. Confirm the model CSV exists at:
--      Python_Analysis/outputs/model_success_predictions.csv
--   4. Confirm SQL_Analysis/Result already exists.
--
-- NOTE:
--   \\copy writes on the PostgreSQL client machine. This is
--   intentional for a local portfolio project.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------------------
-- Core setup and data model
-- ------------------------------------------------------------

\i '01_setup_and_load.sql'
\i '02_data_quality_and_cleaning.sql'
\i '03_data_model.sql'

-- ------------------------------------------------------------
-- Phase 3
-- ------------------------------------------------------------

\i '03a_source_architecture.sql'
\i '03b_compatibility_check.sql'

-- ------------------------------------------------------------
-- Phase 2
-- ------------------------------------------------------------

\i '04_market_analysis.sql'
\i '05_launch_decision.sql'

-- ------------------------------------------------------------
-- Phase 4
-- ------------------------------------------------------------

\i '06_launch_timing.sql'

COMMIT;

-- ------------------------------------------------------------
-- Python -> PostgreSQL model bridge
--
-- 06a creates the raw table and dynamic compatibility view.
-- The CSV is loaded only AFTER the table exists.
-- ------------------------------------------------------------

\i '06a_load_model_predictions.sql'

\copy analysis.model_success_predictions FROM 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/Python_Analysis/outputs/model_success_predictions.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');

-- ------------------------------------------------------------
-- Re-check imported model output
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS prediction_rows,
    MIN(success_probability) AS min_probability,
    MAX(success_probability) AS max_probability,
    AVG(success_probability) AS avg_probability
FROM analysis.model_success_predictions;

SELECT
    COUNT(*) AS scenario_rows
FROM analysis.v_model_success_predictions;

-- ------------------------------------------------------------
-- Phase 5
-- ------------------------------------------------------------

\i '07_final_decision_engine.sql'

-- ------------------------------------------------------------
-- Final export layer
-- ------------------------------------------------------------

\i '08_export_results.sql'
