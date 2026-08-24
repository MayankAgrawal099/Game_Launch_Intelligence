-- ============================================================
-- 07_launch_timing.sql
-- Gaming Launch Intelligence
-- Phase 4: Time & Launch Methodology
-- ============================================================
--
-- Purpose:
--   Convert historical release timing into decision-grade,
--   pre-launch features.
--
-- Core principle:
--   A launch recommendation must only use information that
--   could have been known at the decision date.
--
-- This file creates:
--   1. Release cohorts
--   2. Seasonal launch windows
--   3. Platform lifecycle indicators
--   4. Competitive release density
--   5. Historical timing opportunity
--   6. Pre-launch-safe timing features
--
-- Important:
--   These are historical indicators, not 2026 forecasts.
--   Modern/current platform intelligence will be refined after
--   the source-bridge audit.
-- ============================================================

SET search_path TO analysis, public;

DROP VIEW IF EXISTS v_launch_timing_scenarios CASCADE;
DROP VIEW IF EXISTS v_genre_timing_opportunity CASCADE;
DROP VIEW IF EXISTS v_release_competition_density CASCADE;
DROP VIEW IF EXISTS v_platform_lifecycle CASCADE;
DROP VIEW IF EXISTS v_release_cohorts CASCADE;

-- ------------------------------------------------------------
-- 1. Release cohorts
--
-- 3-year cohorts provide a more stable comparison than raw
-- calendar years while preserving broad market eras.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_release_cohorts AS
SELECT
    game_id,
    game_title,
    genre,
    platform,
    platform_family,
    release_date,
    release_year,
    release_month,
    total_sales,
    ((release_year / 3) * 3) AS cohort_start,
    ((release_year / 3) * 3) + 2 AS cohort_end
FROM v_phase4_game_base
WHERE release_date IS NOT NULL
  AND release_year IS NOT NULL;

-- ------------------------------------------------------------
-- 2. Platform lifecycle
--
-- Approximate lifecycle stage using the platform's observed
-- release distribution:
--
--   Early     = first 20% of observed releases
--   Growth    = 20-50%
--   Mature    = 50-80%
--   Late      = final 20%
--
-- This is intentionally empirical rather than based on
-- external launch dates.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_platform_lifecycle AS
WITH platform_years AS (
    SELECT
        platform,
        MIN(release_year) AS first_observed_year,
        MAX(release_year) AS last_observed_year
    FROM v_phase4_game_base
    WHERE platform IS NOT NULL
      AND release_year IS NOT NULL
    GROUP BY platform
),
base AS (
    SELECT
        g.platform,
        g.release_year,
        COUNT(*) AS releases,
        p.first_observed_year,
        p.last_observed_year,
        (
            g.release_year - p.first_observed_year
        )
        /
        NULLIF(
            p.last_observed_year - p.first_observed_year,
            0
        )::numeric AS lifecycle_position
    FROM v_phase4_game_base g
    JOIN platform_years p
      ON g.platform = p.platform
    WHERE g.release_year IS NOT NULL
    GROUP BY
        g.platform,
        g.release_year,
        p.first_observed_year,
        p.last_observed_year
)
SELECT
    *,
    CASE
        WHEN lifecycle_position <= 0.20 THEN 'EARLY'
        WHEN lifecycle_position <= 0.50 THEN 'GROWTH'
        WHEN lifecycle_position <= 0.80 THEN 'MATURE'
        ELSE 'LATE'
    END AS lifecycle_stage
FROM base;

-- ------------------------------------------------------------
-- 3. Competitive release density
--
-- Business question:
--   How crowded is the launch window?
--
-- We measure the number of comparable releases within:
--   +/- 30 days
--
-- Comparables:
--   Same genre + same platform.
--
-- The current game's own row is excluded.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_release_competition_density AS
SELECT
    a.game_id,
    a.game_title,
    a.genre,
    a.is_console,
    a.release_date,
    COUNT(b.game_id) AS comparable_releases_30d
FROM v_phase4_game_base a
LEFT JOIN v_phase4_game_base b
  ON a.genre = b.genre
 AND a.is_console = b.is_console
 AND b.release_date BETWEEN
        a.release_date - INTERVAL '30 days'
        AND
        a.release_date + INTERVAL '30 days'
 AND a.game_id <> b.game_id
WHERE a.release_date IS NOT NULL
GROUP BY
    a.game_id,
    a.game_title,
    a.genre,
    a.is_console,
    a.release_date;

-- ------------------------------------------------------------
-- 4. Genre timing opportunity
--
-- Historical question:
--   Which launch months have historically produced stronger
--   performance for a genre?
--
-- We require >= 10 releases per genre/month.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_genre_timing_opportunity AS
WITH monthly AS (
    SELECT
        genre,
        release_month,
        COUNT(*) AS title_count,
        AVG(total_sales) AS avg_sales,
        PERCENTILE_CONT(0.50)
            WITHIN GROUP (ORDER BY total_sales) AS median_sales
    FROM v_phase4_game_base
    WHERE genre IS NOT NULL
      AND release_month IS NOT NULL
      AND total_sales IS NOT NULL
    GROUP BY genre, release_month
),
eligible AS (
    SELECT *
    FROM monthly
    WHERE title_count >= 10
),
scored AS (
    SELECT
        *,
        PERCENT_RANK() OVER (
            PARTITION BY genre
            ORDER BY median_sales
        ) AS median_sales_pct,
        PERCENT_RANK() OVER (
            PARTITION BY genre
            ORDER BY avg_sales
        ) AS avg_sales_pct
    FROM eligible
)
SELECT
    *,
    ROUND(
        (
            (
                median_sales_pct * 0.60
                + avg_sales_pct * 0.40
            ) * 100
        )::numeric,
        2
    ) AS historical_timing_score
FROM scored;

-- ------------------------------------------------------------
-- 5. Launch timing scenarios
--
-- This produces a decision-ready timing table.
--
-- It does not say:
--   "November is always best."
--
-- It says:
--   "Historically, for this genre, this month ranked X
--    relative to other months with sufficient evidence."
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_launch_timing_scenarios AS
WITH best_month AS (
    SELECT
        genre,
        release_month,
        title_count,
        avg_sales,
        median_sales,
        historical_timing_score,
        ROW_NUMBER() OVER (
            PARTITION BY genre
            ORDER BY historical_timing_score DESC
        ) AS rn
    FROM v_genre_timing_opportunity
)
SELECT
    genre,
    release_month AS recommended_historical_month,
    title_count AS supporting_title_count,
    avg_sales AS historical_avg_sales,
    median_sales AS historical_median_sales,
    historical_timing_score,
    CASE
        WHEN title_count >= 50 THEN 'HIGH'
        WHEN title_count >= 20 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS evidence_quality
FROM best_month
WHERE rn = 1;

-- ------------------------------------------------------------
-- 6. Timing interpretation
--
-- Combine:
--   timing opportunity
--   competitive release density
--   platform lifecycle
--
-- This remains descriptive in Phase 4. Phase 5 will combine
-- it with the commercial success probability and strategic
-- opportunity score.
-- ------------------------------------------------------------
SELECT
    t.genre,
    t.recommended_historical_month,
    t.historical_timing_score,
    t.evidence_quality
FROM v_launch_timing_scenarios t
ORDER BY t.historical_timing_score DESC;
