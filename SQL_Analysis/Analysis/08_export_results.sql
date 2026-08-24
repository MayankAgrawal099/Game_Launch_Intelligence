-- ============================================================
-- 06_export_results.sql
-- Gaming Launch Intelligence
-- FINAL SQL EXPORT LAYER
-- ============================================================
--
-- IMPORTANT:
--   This file is intentionally numbered 06 but MUST be executed
--   LAST in the SQL pipeline.
--
-- Purpose:
--   Export the final decision-support views produced by Phases 2-5.
--
-- The exports are written to a PostgreSQL-accessible directory.
-- Set psql variable `export_dir` before running, for example:
--
--   \set export_dir 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result'
--
-- Then run this file from psql/pgAdmin.
--
-- If your PostgreSQL server cannot write to the local project
-- directory, use the SELECT statements below as result sets or
-- run equivalent client-side COPY commands.
-- ============================================================

SET search_path TO analysis, public;

-- ------------------------------------------------------------
-- Create output directory:
-- PostgreSQL itself cannot create directories. The directory
-- must already exist on the machine where PostgreSQL runs.
-- ------------------------------------------------------------

-- Expected output files:
--
--   phase2_market_opportunity.csv
--   phase2_competitive_accessibility.csv
--   phase2_genre_platform_fit.csv
--   phase2_regional_opportunity.csv
--   phase4_launch_timing_scenarios.csv
--   phase4_release_competition_density.csv
--   phase4_platform_lifecycle.csv
--   phase5_scenario_score.csv
--   phase5_final_launch_decision.csv

-- ============================================================
-- OPTION A: psql client-side \copy
-- ============================================================
--
-- `\copy` writes on the CLIENT machine, which is normally the
-- safest option for a portfolio project.
--
-- Set the variable before executing this file:
--
-- \set export_dir 'C:/path/to/Python_Analysis/results/sql_exports'
--
-- ============================================================

COPY (
    SELECT *
    FROM v_phase2_market_opportunity
    ORDER BY opportunity_score DESC
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase2_market_opportunity.csv'
WITH (FORMAT CSV, HEADER TRUE);

-- ============================================================
-- Phase 2: Competitive Accessibility
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_phase2_competitive_accessibility
    ORDER BY competitive_accessibility_score DESC NULLS LAST
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase2_competitive_accessibility.csv'
WITH (FORMAT CSV, HEADER TRUE);


-- ============================================================
-- Phase 2: Genre × Platform Fit
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_phase2_genre_platform_fit
    ORDER BY genre, genre_platform_fit_score DESC
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase2_genre_platform_fit.csv'
WITH (FORMAT CSV, HEADER TRUE);


-- ============================================================
-- Phase 2: Regional Opportunity
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_phase2_regional_opportunity
    ORDER BY genre, regional_opportunity_score DESC
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase2_regional_opportunity.csv'
WITH (FORMAT CSV, HEADER TRUE);


-- ============================================================
-- Phase 4: Launch Timing Scenarios
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_launch_timing_scenarios
    ORDER BY genre, historical_timing_score DESC
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase4_launch_timing_scenarios.csv'
WITH (FORMAT CSV, HEADER TRUE);


-- ============================================================
-- Phase 4: Release Competition Density
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_release_competition_density
    ORDER BY comparable_releases_30d DESC
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase4_release_competition_density.csv'
WITH (FORMAT CSV, HEADER TRUE);


-- ============================================================
-- Phase 4: Platform Lifecycle
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_platform_lifecycle
    ORDER BY platform, release_year
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase4_platform_lifecycle.csv'
WITH (FORMAT CSV, HEADER TRUE);


-- ============================================================
-- Phase 5: Final Scenario Score
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_final_scenario_score
    ORDER BY strategic_scenario_score DESC
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase5_scenario_score.csv'
WITH (FORMAT CSV, HEADER TRUE);


-- ============================================================
-- Phase 5: Final Launch Decision
-- ============================================================

COPY (
    SELECT *
    FROM analysis.v_final_launch_decision
    ORDER BY
        CASE final_decision
            WHEN 'GO' THEN 1
            WHEN 'CONDITIONAL' THEN 2
            WHEN 'AVOID' THEN 3
            ELSE 4
        END,
        strategic_scenario_score DESC
) TO 'C:/Users/USER/Desktop/Resume Projects/Game_Launch_Intelligence/SQL_Analysis/Result/phase5_final_launch_decision.csv'
WITH (FORMAT CSV, HEADER TRUE);

-- ------------------------------------------------------------
-- Final verification
-- ------------------------------------------------------------
SELECT
    'v_phase2_market_opportunity' AS output,
    COUNT(*) AS rows
FROM v_phase2_market_opportunity

UNION ALL
SELECT
    'v_phase2_competitive_accessibility',
    COUNT(*)
FROM v_phase2_competitive_accessibility

UNION ALL
SELECT
    'v_phase2_genre_platform_fit',
    COUNT(*)
FROM v_phase2_genre_platform_fit

UNION ALL
SELECT
    'v_phase2_regional_opportunity',
    COUNT(*)
FROM v_phase2_regional_opportunity

UNION ALL
SELECT
    'v_launch_timing_scenarios',
    COUNT(*)
FROM v_launch_timing_scenarios

UNION ALL
SELECT
    'v_release_competition_density',
    COUNT(*)
FROM v_release_competition_density

UNION ALL
SELECT
    'v_platform_lifecycle',
    COUNT(*)
FROM v_platform_lifecycle

UNION ALL
SELECT
    'v_final_scenario_score',
    COUNT(*)
FROM v_final_scenario_score

UNION ALL
SELECT
    'v_final_launch_decision',
    COUNT(*)
FROM v_final_launch_decision
ORDER BY output;
