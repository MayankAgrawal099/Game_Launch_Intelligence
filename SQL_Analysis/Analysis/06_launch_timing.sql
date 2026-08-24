-- ============================================================
-- 06_launch_timing.sql
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
-- ============================================================

SET search_path TO analysis, public;

DROP VIEW IF EXISTS v_launch_timing_scenarios CASCADE;
DROP VIEW IF EXISTS v_genre_timing_opportunity CASCADE;
DROP VIEW IF EXISTS v_release_competition_density CASCADE;
DROP VIEW IF EXISTS v_platform_lifecycle CASCADE;
DROP VIEW IF EXISTS v_release_cohorts CASCADE;

-- ------------------------------------------------------------
-- 1. Release cohorts
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
            (g.release_year - p.first_observed_year)::numeric
            / NULLIF(
                (p.last_observed_year - p.first_observed_year)::numeric,
                0
            )
        ) AS lifecycle_position
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
        WHEN lifecycle_position IS NULL THEN 'SINGLE_PERIOD'
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
-- Comparable releases are defined as:
--   same genre + same platform + within +/- 30 days.
--
-- IMPORTANT:
--   is_console is NOT used here. It only distinguishes broad
--   console/non-console categories and would incorrectly treat
--   different platforms as direct launch competitors.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_release_competition_density AS
SELECT
    a.game_id,
    a.game_title,
    a.genre,
    a.platform,
    a.release_date,
    COUNT(b.game_id) AS comparable_releases_30d
FROM v_phase4_game_base a
LEFT JOIN v_phase4_game_base b
  ON a.genre = b.genre
 AND a.platform = b.platform
 AND b.release_date BETWEEN
        a.release_date - INTERVAL '30 days'
        AND a.release_date + INTERVAL '30 days'
 AND a.game_id <> b.game_id
WHERE a.release_date IS NOT NULL
  AND a.platform IS NOT NULL
GROUP BY
    a.game_id,
    a.game_title,
    a.genre,
    a.platform,
    a.release_date;

-- ------------------------------------------------------------
-- 4. Genre timing opportunity
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
            median_sales_pct * 0.60
            + avg_sales_pct * 0.40
        )::numeric * 100,
        2
    ) AS historical_timing_score
FROM scored;

-- ------------------------------------------------------------
-- 5. Launch timing scenarios
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
-- 6. Validation result
-- ------------------------------------------------------------
SELECT
    genre,
    recommended_historical_month,
    historical_timing_score,
    evidence_quality
FROM v_launch_timing_scenarios
ORDER BY historical_timing_score DESC;
