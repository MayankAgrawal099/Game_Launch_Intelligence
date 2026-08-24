-- ============================================================
-- 04_market_analysis.sql
-- Gaming Launch Intelligence
-- Phase 2: Business Framework & Market Opportunity Analysis
-- ============================================================
--
-- Phase 2 separates five business dimensions:
--   1) Demand Potential
--   2) Market Momentum
--   3) Competitive Accessibility
--   4) Historical Platform Opportunity
--   5) Regional Opportunity
--
-- Opportunity Score is NOT a probability of game success.
-- The leakage-free pre-launch success model is handled in Python.
--
-- Source layer used here:
--   analysis.v_game_sales_conformed
--
-- Evidence rules:
--   Genre scoring: >= 20 titles
--   Genre/platform scoring: >= 10 titles
--   Entrant accessibility: >= 10 entrants
-- ============================================================

DROP VIEW IF EXISTS analysis.v_phase2_market_opportunity CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_regional_opportunity CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_genre_platform_fit CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_platform_opportunity CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_competitive_accessibility CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_new_entrant_accessibility CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_publisher_concentration CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_market_momentum CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_demand_potential CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_genre_market CASCADE;

-- ------------------------------------------------------------
-- 1. Genre market base
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_genre_market AS
SELECT
    genre,
    COUNT(*) AS title_count,
    SUM(total_sales) AS total_sales,
    AVG(total_sales) AS avg_sales,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_sales) AS median_sales,
    MIN(year) AS first_release_year,
    MAX(year) AS last_release_year,
    CASE
        WHEN COUNT(*) >= 50 THEN 'HIGH'
        WHEN COUNT(*) >= 20 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS evidence_quality
FROM analysis.v_game_sales_conformed
WHERE genre IS NOT NULL
  AND total_sales IS NOT NULL
  AND total_sales >= 0
GROUP BY genre;

-- ------------------------------------------------------------
-- 2. Demand Potential
--
-- Business question:
--   Is there meaningful historical commercial demand?
--
-- 60% median sales percentile
-- 40% average sales percentile
--
-- Concentration is deliberately excluded here.
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_demand_potential AS
WITH eligible AS (
    SELECT *
    FROM analysis.v_phase2_genre_market
    WHERE title_count >= 20
), scored AS (
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY median_sales) AS median_sales_pct,
        PERCENT_RANK() OVER (ORDER BY avg_sales) AS avg_sales_pct
    FROM eligible
)
SELECT
    *,
    ROUND((median_sales_pct * 60 + avg_sales_pct * 40)::numeric, 2)
        AS demand_potential_score
FROM scored;

-- ------------------------------------------------------------
-- 3. Market Momentum
--
-- Compare the first three and latest three observed yearly
-- average-sales observations for each genre.
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_market_momentum AS
WITH yearly AS (
    SELECT
        genre,
        year,
        AVG(total_sales) AS avg_sales
    FROM analysis.v_game_sales_conformed
    WHERE genre IS NOT NULL
      AND total_sales IS NOT NULL
      AND year IS NOT NULL
    GROUP BY genre, year
), ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY genre ORDER BY year) AS rn_asc,
        ROW_NUMBER() OVER (PARTITION BY genre ORDER BY year DESC) AS rn_desc
    FROM yearly
), endpoints AS (
    SELECT
        genre,
        AVG(CASE WHEN rn_asc <= 3 THEN avg_sales END) AS early_avg_sales,
        AVG(CASE WHEN rn_desc <= 3 THEN avg_sales END) AS recent_avg_sales
    FROM ranked
    GROUP BY genre
), growth AS (
    SELECT
        *,
        CASE
            WHEN early_avg_sales > 0
            THEN (recent_avg_sales - early_avg_sales) / early_avg_sales
            ELSE NULL
        END AS growth_rate
    FROM endpoints
)
SELECT
    *,
    CASE
        WHEN growth_rate IS NULL THEN 'INSUFFICIENT'
        WHEN growth_rate > 0.10 THEN 'POSITIVE'
        WHEN growth_rate < -0.10 THEN 'NEGATIVE'
        ELSE 'STABLE'
    END AS momentum_direction,
    CASE
        WHEN growth_rate IS NULL THEN NULL
        ELSE ROUND((PERCENT_RANK() OVER (ORDER BY growth_rate) * 100)::numeric, 2)
    END AS momentum_score
FROM growth;

-- ------------------------------------------------------------
-- 4. Publisher concentration / HHI
--
-- HHI is a competition metric, not a demand metric.
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_publisher_concentration AS
WITH publisher_sales AS (
    SELECT
        genre,
        publisher_name AS publisher,
        SUM(total_sales) AS publisher_sales
    FROM analysis.v_game_sales_conformed
    WHERE genre IS NOT NULL
      AND publisher_name IS NOT NULL
      AND total_sales IS NOT NULL
    GROUP BY genre, publisher_name
), ranked AS (
    SELECT
        *,
        SUM(publisher_sales) OVER (PARTITION BY genre) AS genre_sales,
        ROW_NUMBER() OVER (
            PARTITION BY genre
            ORDER BY publisher_sales DESC
        ) AS publisher_rank
    FROM publisher_sales
), concentration AS (
    SELECT
        genre,
        SUM(POWER(publisher_sales / NULLIF(genre_sales, 0), 2)) AS hhi,
        SUM(
            CASE
                WHEN publisher_rank <= 5
                THEN publisher_sales / NULLIF(genre_sales, 0)
                ELSE 0
            END
        ) AS top5_share
    FROM ranked
    GROUP BY genre
)
SELECT
    *,
    CASE
        WHEN hhi < 0.15 THEN 'LOW'
        WHEN hhi < 0.25 THEN 'MODERATE'
        ELSE 'HIGH'
    END AS concentration_level,
    ROUND(((1 - PERCENT_RANK() OVER (ORDER BY hhi)) * 100)::numeric, 2)
        AS concentration_accessibility_score
FROM concentration;

-- ------------------------------------------------------------
-- 5. New entrant accessibility
--
-- An entrant is the first observed title of a publisher within
-- a genre. Success is based on the historical genre + 3-year
-- cohort top-quartile definition used by the Phase 1 model.
--
-- The smoothed rate prevents small samples such as 1/1 from
-- becoming a misleading 100% entrant-success rate.
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_new_entrant_accessibility AS
WITH cohort_base AS (
    SELECT
        gs.*,
        FLOOR(year / 3.0) * 3 AS cohort_start
    FROM analysis.v_game_sales_conformed gs
    WHERE genre IS NOT NULL
      AND publisher_name IS NOT NULL
      AND total_sales IS NOT NULL
      AND year IS NOT NULL
), thresholds AS (
    SELECT
        genre,
        cohort_start,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_sales) AS success_threshold
    FROM cohort_base
    GROUP BY genre, cohort_start
), labelled AS (
    SELECT
        c.*,
        CASE
            WHEN c.total_sales >= t.success_threshold THEN 1
            ELSE 0
        END AS is_success
    FROM cohort_base c
    JOIN thresholds t
      ON c.genre = t.genre
     AND c.cohort_start = t.cohort_start
), publisher_genre_first AS (
    SELECT
        publisher_name AS publisher,
        genre,
        MIN(release_date) AS first_release_date
    FROM labelled
    GROUP BY publisher_name, genre
), entrants AS (
    SELECT l.*
    FROM labelled l
    JOIN publisher_genre_first f
      ON l.publisher_name = f.publisher
     AND l.genre = f.genre
     AND l.release_date = f.first_release_date
), summary AS (
    SELECT
        genre,
        COUNT(*) AS entrant_count,
        SUM(is_success) AS successful_entrants
    FROM entrants
    GROUP BY genre
), prior AS (
    SELECT AVG(is_success::numeric) AS prior_rate
    FROM entrants
), smoothed AS (
    SELECT
        s.*,
        p.prior_rate,
        (s.successful_entrants + 10 * p.prior_rate)
            / NULLIF(s.entrant_count + 10, 0) AS smoothed_success_rate
    FROM summary s
    CROSS JOIN prior p
)
SELECT
    *,
    CASE
        WHEN entrant_count < 10 THEN 'INSUFFICIENT'
        WHEN entrant_count < 25 THEN 'MEDIUM'
        ELSE 'HIGH'
    END AS evidence_quality,
    CASE
        WHEN entrant_count < 10 THEN NULL
        ELSE ROUND((PERCENT_RANK() OVER (ORDER BY smoothed_success_rate) * 100)::numeric, 2)
    END AS entrant_accessibility_score
FROM smoothed;

-- ------------------------------------------------------------
-- 6. Competitive Accessibility
--
-- 50% concentration accessibility
-- 50% entrant accessibility
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_competitive_accessibility AS
SELECT
    g.genre,
    g.title_count,
    g.evidence_quality AS genre_evidence_quality,
    c.hhi,
    c.top5_share,
    c.concentration_level,
    c.concentration_accessibility_score,
    e.entrant_count,
    e.successful_entrants,
    e.smoothed_success_rate,
    e.entrant_accessibility_score,
    CASE
        WHEN c.concentration_accessibility_score IS NULL
          OR e.entrant_accessibility_score IS NULL
        THEN NULL
        ELSE ROUND((
            c.concentration_accessibility_score * 0.50
            + e.entrant_accessibility_score * 0.50
        )::numeric, 2)
    END AS competitive_accessibility_score
FROM analysis.v_phase2_genre_market g
LEFT JOIN analysis.v_phase2_publisher_concentration c
    ON g.genre = c.genre
LEFT JOIN analysis.v_phase2_new_entrant_accessibility e
    ON g.genre = e.genre;

-- ------------------------------------------------------------
-- 7. Historical Platform Opportunity
--
-- This is deliberately named historical platform opportunity.
-- Current platform strategy is addressed after modern data and
-- platform-family mapping are incorporated.
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_platform_opportunity AS
WITH base AS (
    SELECT
        platform,
        COUNT(*) AS title_count,
        SUM(total_sales) AS total_sales,
        AVG(total_sales) AS avg_sales,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_sales) AS median_sales
    FROM analysis.v_game_sales_conformed
    WHERE platform IS NOT NULL
      AND total_sales IS NOT NULL
    GROUP BY platform
), eligible AS (
    SELECT * FROM base WHERE title_count >= 20
), scored AS (
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY median_sales) AS median_sales_pct,
        PERCENT_RANK() OVER (ORDER BY avg_sales) AS avg_sales_pct
    FROM eligible
)
SELECT
    *,
    ROUND(((median_sales_pct * 0.60 + avg_sales_pct * 0.40) * 100)::numeric, 2)
        AS historical_platform_opportunity_score
FROM scored;

-- ------------------------------------------------------------
-- 8. Genre × platform fit
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_genre_platform_fit AS
WITH base AS (
    SELECT
        genre,
        platform,
        COUNT(*) AS title_count,
        AVG(total_sales) AS avg_sales,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_sales) AS median_sales
    FROM analysis.v_game_sales_conformed
    WHERE genre IS NOT NULL
      AND platform IS NOT NULL
      AND total_sales IS NOT NULL
    GROUP BY genre, platform
), eligible AS (
    SELECT * FROM base WHERE title_count >= 10
), scored AS (
    SELECT
        *,
        PERCENT_RANK() OVER (PARTITION BY genre ORDER BY median_sales) AS median_sales_pct,
        PERCENT_RANK() OVER (PARTITION BY genre ORDER BY avg_sales) AS avg_sales_pct
    FROM eligible
)
SELECT
    *,
    ROUND(((median_sales_pct * 0.60 + avg_sales_pct * 0.40) * 100)::numeric, 2)
        AS genre_platform_fit_score
FROM scored;

-- ------------------------------------------------------------
-- 9. Regional Opportunity
--
-- 50% absolute regional share
-- 50% over-indexing relative to overall regional share
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_regional_opportunity AS
WITH genre_region AS (
    SELECT
        genre,
        SUM(na_sales) AS na_sales,
        SUM(pal_sales) AS pal_sales,
        SUM(jp_sales) AS jp_sales,
        SUM(other_sales) AS other_sales,
        SUM(total_sales) AS total_sales
    FROM analysis.v_game_sales_conformed
    WHERE genre IS NOT NULL
    GROUP BY genre
), long_region AS (
    SELECT genre, 'North America' AS region, na_sales AS regional_sales, total_sales AS genre_total
    FROM genre_region
    UNION ALL
    SELECT genre, 'PAL' AS region, pal_sales AS regional_sales, total_sales AS genre_total
    FROM genre_region
    UNION ALL
    SELECT genre, 'Japan' AS region, jp_sales AS regional_sales, total_sales AS genre_total
    FROM genre_region
    UNION ALL
    SELECT genre, 'Other' AS region, other_sales AS regional_sales, total_sales AS genre_total
    FROM genre_region
), region_totals AS (
    SELECT
        region,
        SUM(regional_sales) AS region_sales
    FROM long_region
    GROUP BY region
), global_total AS (
    SELECT SUM(total_sales) AS global_sales
    FROM analysis.v_game_sales_conformed
    WHERE total_sales IS NOT NULL
), indexed AS (
    SELECT
        l.genre,
        l.region,
        l.regional_sales,
        l.genre_total,
        l.regional_sales / NULLIF(l.genre_total, 0) AS regional_share,
        rt.region_sales / NULLIF(gt.global_sales, 0) AS overall_region_share,
        (
            l.regional_sales / NULLIF(l.genre_total, 0)
        ) / NULLIF(
            rt.region_sales / NULLIF(gt.global_sales, 0),
            0
        ) AS over_index
    FROM long_region l
    JOIN region_totals rt ON l.region = rt.region
    CROSS JOIN global_total gt
)
SELECT
    *,
    ROUND((PERCENT_RANK() OVER (PARTITION BY genre ORDER BY regional_share) * 100)::numeric, 2)
        AS demand_component,
    ROUND((PERCENT_RANK() OVER (PARTITION BY genre ORDER BY over_index) * 100)::numeric, 2)
        AS over_index_component,
    ROUND((
        PERCENT_RANK() OVER (PARTITION BY genre ORDER BY regional_share) * 50
        + PERCENT_RANK() OVER (PARTITION BY genre ORDER BY over_index) * 50
    )::numeric, 2) AS regional_opportunity_score
FROM indexed;

-- ------------------------------------------------------------
-- 10. Unified genre opportunity score
--
-- Weights:
--   Demand Potential            25%
--   Market Momentum             15%
--   Competitive Accessibility   25%
--   Best Genre×Platform Fit     20%
--   Best Regional Opportunity   15%
--
-- Missing evidence is represented as NULL and only receives a
-- neutral fallback in the aggregate score. Evidence quality is
-- retained explicitly so the dashboard does not hide uncertainty.
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_market_opportunity AS
WITH platform_by_genre AS (
    SELECT DISTINCT ON (genre)
        genre,
        genre_platform_fit_score AS best_platform_fit_score,
        platform AS best_historical_platform
    FROM analysis.v_phase2_genre_platform_fit
    ORDER BY genre, genre_platform_fit_score DESC
), regional_by_genre AS (
    SELECT DISTINCT ON (genre)
        genre,
        regional_opportunity_score AS best_regional_score,
        region AS best_historical_region
    FROM analysis.v_phase2_regional_opportunity
    ORDER BY genre, regional_opportunity_score DESC
), base AS (
    SELECT
        d.genre,
        d.title_count,
        d.evidence_quality,
        d.demand_potential_score,
        m.momentum_score,
        m.momentum_direction,
        c.competitive_accessibility_score,
        p.best_platform_fit_score,
        p.best_historical_platform,
        r.best_regional_score,
        r.best_historical_region
    FROM analysis.v_phase2_demand_potential d
    LEFT JOIN analysis.v_phase2_market_momentum m ON d.genre = m.genre
    LEFT JOIN analysis.v_phase2_competitive_accessibility c ON d.genre = c.genre
    LEFT JOIN platform_by_genre p ON d.genre = p.genre
    LEFT JOIN regional_by_genre r ON d.genre = r.genre
)
SELECT
    *,
    ROUND((
        demand_potential_score * 0.25
        + COALESCE(momentum_score, 50) * 0.15
        + COALESCE(competitive_accessibility_score, 50) * 0.25
        + COALESCE(best_platform_fit_score, 50) * 0.20
        + COALESCE(best_regional_score, 50) * 0.15
    )::numeric, 2) AS opportunity_score,
    CASE
        WHEN title_count >= 50 THEN 'HIGH'
        WHEN title_count >= 20 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS evidence_quality_final
FROM base;
