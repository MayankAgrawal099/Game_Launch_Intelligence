-- ============================================================
-- 06a_load_model_predictions.sql
-- Gaming Launch Intelligence
-- Python -> PostgreSQL model-output bridge
-- ============================================================
--
-- Purpose:
--   1. Create the raw model prediction table.
--   2. Create a dynamic scenario-level compatibility view.
--
-- The pipeline loads the Python CSV AFTER this file creates the
-- raw table. The scenario view reads directly from the raw table,
-- so it automatically reflects the newly imported predictions.
--
-- This avoids the previous ordering problem where the scenario
-- aggregation was created before the CSV rows had been loaded.
-- ============================================================

SET search_path TO analysis, public;

DROP VIEW IF EXISTS v_model_success_predictions CASCADE;
DROP TABLE IF EXISTS model_success_predictions_scenario;
DROP TABLE IF EXISTS model_success_predictions;

-- ------------------------------------------------------------
-- 1. Raw game-level model predictions
-- ------------------------------------------------------------

CREATE TABLE model_success_predictions (
    title TEXT,
    genre TEXT,
    console TEXT,
    platform_family TEXT,
    release_date DATE,
    release_year INTEGER,
    total_sales NUMERIC,
    is_success INTEGER,
    success_probability NUMERIC,
    predicted_success INTEGER,
    decision_threshold NUMERIC
);

COPY model_success_predictions
FROM 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/Python_Analysis/outputs/model_success_predictions.csv'
WITH (
    FORMAT CSV,
    HEADER TRUE,
    NULL ''
);

-- ------------------------------------------------------------
-- 2. Scenario-level compatibility view
--
-- Python uses `console` as the platform-code field. Downstream
-- SQL uses `platform` consistently.
--
-- The view is dynamic, so it reflects the rows loaded into the
-- raw table by run_pipeline.sql.
-- ------------------------------------------------------------

DROP TABLE IF EXISTS analysis.model_success_predictions_scenario CASCADE;

CREATE TABLE analysis.model_success_predictions_scenario AS
SELECT
    genre,
    console AS platform,
    AVG(success_probability) AS success_probability,
    COUNT(*) AS prediction_count
FROM analysis.model_success_predictions
WHERE success_probability IS NOT NULL
  AND genre IS NOT NULL
  AND console IS NOT NULL
GROUP BY
    genre,
    console;

CREATE INDEX IF NOT EXISTS idx_model_predictions_scenario
ON analysis.model_success_predictions_scenario (genre, platform);

DROP VIEW IF EXISTS analysis.v_model_success_predictions CASCADE;

CREATE VIEW analysis.v_model_success_predictions AS
SELECT
    genre,
    platform,
    success_probability,
    prediction_count
FROM analysis.model_success_predictions_scenario;

-- ------------------------------------------------------------
-- 3. Validation
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS prediction_rows,
    MIN(success_probability) AS min_probability,
    MAX(success_probability) AS max_probability,
    AVG(success_probability) AS avg_probability
FROM model_success_predictions;

SELECT
    COUNT(*) AS scenario_rows
FROM v_model_success_predictions;

SELECT *
FROM analysis.v_model_success_predictions
ORDER BY success_probability DESC
LIMIT 20;

