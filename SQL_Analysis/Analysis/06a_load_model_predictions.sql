-- ============================================================
-- 06a_load_model_predictions.sql
-- Python -> PostgreSQL model-output bridge
-- ============================================================

SET search_path TO analysis, public;

-- ============================================================
-- 1. Create raw prediction table
-- ============================================================

DROP TABLE IF EXISTS model_success_predictions_scenario;
DROP VIEW IF EXISTS v_model_success_predictions CASCADE;
DROP TABLE IF EXISTS model_success_predictions;

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

-- ============================================================
-- 2. Load Phase 1 Python predictions
--
-- IMPORTANT:
-- Replace the path below with the actual location of:
--
-- model_success_predictions.csv
-- ============================================================

COPY model_success_predictions
FROM 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\Python_Analysis\outputs\model_success_predictions.csv'
WITH (
    FORMAT CSV,
    HEADER TRUE,
    NULL ''
);

-- ============================================================
-- 3. Create scenario-level predictions
--
-- Phase 5 works at:
--     Genre × Platform
--
-- while Phase 1 produces game-level predictions.
--
-- Therefore we aggregate the individual game probabilities.
-- ============================================================

CREATE TABLE model_success_predictions_scenario AS
SELECT
    genre,
    console,
    AVG(success_probability) AS success_probability,
    COUNT(*) AS prediction_count
FROM model_success_predictions
WHERE success_probability IS NOT NULL
GROUP BY
    genre,
    console;

CREATE INDEX IF NOT EXISTS idx_model_predictions_scenario
ON model_success_predictions_scenario (genre, console);

-- ============================================================
-- 4. Create Phase 5 compatibility view
-- ============================================================

CREATE OR REPLACE VIEW v_model_success_predictions AS
SELECT
    genre,
    console,
    success_probability,
    prediction_count
FROM model_success_predictions_scenario;

SELECT schemaname, viewname
FROM pg_views
WHERE viewname = 'v_model_success_predictions';

-- ============================================================
-- 5. Validation
-- ============================================================

SELECT
    COUNT(*) AS prediction_rows,
    MIN(success_probability) AS min_probability,
    MAX(success_probability) AS max_probability,
    AVG(success_probability) AS avg_probability
FROM model_success_predictions;

SELECT
    COUNT(*) AS scenario_rows
FROM model_success_predictions_scenario;

SELECT *
FROM model_success_predictions_scenario
ORDER BY success_probability DESC
LIMIT 20;