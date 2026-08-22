-- =============================================================
-- 05_launch_decision.sql
-- Combines historical signals into a weighted launch-decision
-- score, generates marketing allocation recommendations, and
-- builds a full scenario comparison matrix.
-- =============================================================


-- -----------------------------------------------
-- Launch simulator
-- Weighted composite of six analytical dimensions:
--   market attractiveness (25%), trend (15%),
--   publisher opportunity (15%), entrant accessibility (20%),
--   platform fit (15%), regional opportunity (10%).
-- Classifies each genre-platform pair as GO / CONDITIONAL / AVOID.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_launch_simulator CASCADE;

CREATE VIEW analysis.v_launch_simulator AS
WITH entrant AS (
    SELECT
        genre,
        COUNT(*) AS first_entrants,
        COUNT(*) FILTER (WHERE entry_performance IN ('strong breakout','above median')) * 100.0 /
            NULLIF(COUNT(*),0) AS entrant_accessibility_score
    FROM analysis.v_new_entrant_performance
    GROUP BY genre
),
best_region AS (
    -- Sourced from analysis.v_genre_best_region: scores each genre's
    -- best-region skew against other genres, rather than against its
    -- own 4 regions (which always maxed out at 100 -- see that view's
    -- comment for the full explanation).
    SELECT
        genre,
        recommended_region,
        regional_opportunity_score AS regional_score,
        recommended_region_skew_pct
    FROM analysis.v_genre_best_region
),
gp AS (
    SELECT
        genre,
        platform,
        median_sales_per_release,
        avg_sales_per_release,
        rank_in_genre
    FROM analysis.v_genre_platform_fit
),
scenario_base AS (
    SELECT
        ga.genre,
        gp.platform,
        gp.rank_in_genre AS platform_rank_in_genre,
        ga.attractiveness_score AS market_attractiveness_score,
        COALESCE(mt.trend_score,50) AS trend_score,
        COALESCE(pc.publisher_opportunity_score,50) AS publisher_opportunity_score,
        COALESCE(e.entrant_accessibility_score,50) AS entrant_accessibility_score,
        COALESCE(pf.platform_fit_score,50) AS platform_fit_score,
        COALESCE(br.regional_score,50) AS regional_opportunity_score,
        br.recommended_region,
        br.recommended_region_skew_pct,
        gp.median_sales_per_release,
        gp.avg_sales_per_release
    FROM analysis.v_genre_attractiveness ga
    JOIN gp ON gp.genre = ga.genre
    LEFT JOIN analysis.v_market_trend mt ON mt.genre = ga.genre
    LEFT JOIN analysis.v_publisher_concentration pc ON pc.genre = ga.genre
    LEFT JOIN entrant e ON e.genre = ga.genre
    LEFT JOIN analysis.v_platform_fit pf ON pf.platform = gp.platform
    LEFT JOIN best_region br ON br.genre = ga.genre
),
scored AS (
    SELECT
        *,
        ROUND((
            market_attractiveness_score * 0.25 +
            trend_score * 0.15 +
            publisher_opportunity_score * 0.15 +
            entrant_accessibility_score * 0.20 +
            platform_fit_score * 0.15 +
            regional_opportunity_score * 0.10
        )::NUMERIC,2) AS launch_score
    FROM scenario_base
)
SELECT
    genre,
    platform AS platform,
    platform_rank_in_genre,
    recommended_region,
    market_attractiveness_score,
    trend_score,
    publisher_opportunity_score,
    entrant_accessibility_score,
    platform_fit_score,
    regional_opportunity_score,
    recommended_region_skew_pct,
    launch_score,
    CASE
        WHEN launch_score >= 70 THEN 'GO'
        WHEN launch_score >= 55 THEN 'CONDITIONAL'
        ELSE 'AVOID'
    END AS launch_decision,
    CASE
        WHEN entrant_accessibility_score < 20 THEN 'High entry risk'
        WHEN publisher_opportunity_score < 30 THEN 'High publisher concentration'
        WHEN platform_fit_score < 40 THEN 'Weak platform fit'
        WHEN trend_score < 35 THEN 'Weak/declining market trend'
        ELSE 'No single dominant red flag'
    END AS primary_risk
FROM scored;

-- All scenarios ranked by launch score
SELECT *
FROM analysis.v_launch_simulator
ORDER BY launch_score DESC;

-- Filtered to the user's configured launch scenario (if set)
SELECT ls.*,
       lc.target_title,
       lc.primary_region,
       lc.marketing_budget_millions,
       lc.notes
FROM analysis.v_launch_simulator ls
CROSS JOIN analysis.launch_config lc
WHERE (lc.target_genre IS NULL OR LOWER(ls.genre) = LOWER(lc.target_genre))
  AND (lc.target_platform IS NULL OR UPPER(ls.platform) = UPPER(lc.target_platform));


-- -----------------------------------------------
-- Marketing allocation
-- Translates regional demand skew into a recommended
-- budget split, with optional absolute dollar amounts.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_marketing_allocation CASCADE;

CREATE VIEW analysis.v_marketing_allocation AS
WITH cfg AS (
    SELECT * FROM analysis.launch_config WHERE scenario_id = 1
),
regional AS (
    SELECT
        ro.genre,
        ro.region,
        ro.region_genre_share_pct,
        ro.global_genre_share_pct,
        ro.skew_pct,
        ro.region_mix_of_genre_pct,
        100 * PERCENT_RANK() OVER (PARTITION BY ro.genre ORDER BY ro.skew_pct) AS skew_score
    FROM analysis.v_regional_opportunity ro
),
scored AS (
    SELECT
        r.*,
        -- Allocation index blends absolute regional demand (60%) with over-indexing signal (40%)
        (r.region_mix_of_genre_pct * 0.60 + r.skew_score * 0.40) AS allocation_index
    FROM regional r
    CROSS JOIN cfg
    WHERE cfg.target_genre IS NULL OR LOWER(r.genre) = LOWER(cfg.target_genre)
),
normalised AS (
    SELECT
        *,
        allocation_index / NULLIF(SUM(allocation_index) OVER (PARTITION BY genre),0) * 100 AS recommended_budget_pct
    FROM scored
)
SELECT
    genre,
    region,
    ROUND(region_genre_share_pct::NUMERIC,2) AS region_genre_share_pct,
    ROUND(global_genre_share_pct::NUMERIC,2) AS global_genre_share_pct,
    ROUND(skew_pct::NUMERIC,2) AS skew_pct,
    ROUND(allocation_index::NUMERIC,2) AS allocation_index,
    ROUND(recommended_budget_pct::NUMERIC,2) AS recommended_budget_pct,
    CASE
        WHEN (SELECT marketing_budget_millions FROM cfg) IS NULL THEN NULL
        ELSE ROUND(((recommended_budget_pct/100) *
            (SELECT marketing_budget_millions FROM cfg))::NUMERIC,2)
    END AS recommended_budget_millions
FROM normalised;

SELECT *
FROM analysis.v_marketing_allocation
ORDER BY genre, recommended_budget_pct DESC;

-- Platform fit cross-referenced with genre-platform rankings for the configured scenario
SELECT
    pf.platform,
    pf.platform_fit_score,
    pf.sales_per_release,
    pf.release_share_pct,
    pf.distribution_score,
    gp.rank_in_genre AS genre_platform_rank,
    gp.median_sales_per_release
FROM analysis.v_platform_fit pf
JOIN analysis.v_genre_platform_fit gp
  ON gp.platform = pf.platform
CROSS JOIN analysis.launch_config lc
WHERE lc.target_genre IS NULL OR LOWER(gp.genre) = LOWER(lc.target_genre)
ORDER BY pf.platform_fit_score DESC, gp.median_sales_per_release DESC;


-- -----------------------------------------------
-- Scenario comparison matrix
-- Ranks all viable genre-platform scenarios so management
-- can compare the planned launch with alternatives.
-- -----------------------------------------------

WITH genre_scores AS (
    SELECT * FROM analysis.v_genre_attractiveness
),
trend AS (
    SELECT * FROM analysis.v_market_trend
),
publisher AS (
    SELECT * FROM analysis.v_publisher_concentration
),
entrant AS (
    SELECT
        genre,
        COUNT(*) AS first_entrants,
        COUNT(*) FILTER (WHERE entry_performance IN ('strong breakout','above median')) * 100.0 /
            NULLIF(COUNT(*),0) AS entrant_score
    FROM analysis.v_new_entrant_performance
    GROUP BY genre
),
platform AS (
    SELECT * FROM analysis.v_platform_fit
),
gp AS (
    SELECT * FROM analysis.v_genre_platform_fit
),
region AS (
    -- Same fix as v_launch_simulator's best_region CTE above --
    -- sourced from analysis.v_genre_best_region instead of an inline
    -- PERCENT_RANK-per-genre pattern that always scored 100.
    SELECT
        genre,
        recommended_region AS best_region,
        regional_opportunity_score AS region_score,
        recommended_region_skew_pct AS skew_pct
    FROM analysis.v_genre_best_region
)
SELECT
    gp.genre,
    gp.platform,
    ROUND((
        COALESCE(gs.attractiveness_score,50)*0.25 +
        COALESCE(t.trend_score,50)*0.15 +
        COALESCE(pub.publisher_opportunity_score,50)*0.15 +
        COALESCE(e.entrant_score,50)*0.20 +
        COALESCE(p.platform_fit_score,50)*0.15 +
        COALESCE(r.region_score,50)*0.10
    )::NUMERIC,2) AS scenario_score,
    r.best_region,
    ROUND(r.skew_pct::NUMERIC,2) AS best_region_skew_pct,
    CASE
        WHEN (
            COALESCE(gs.attractiveness_score,50)*0.25 +
            COALESCE(t.trend_score,50)*0.15 +
            COALESCE(pub.publisher_opportunity_score,50)*0.15 +
            COALESCE(e.entrant_score,50)*0.20 +
            COALESCE(p.platform_fit_score,50)*0.15 +
            COALESCE(r.region_score,50)*0.10
        ) >= 70 THEN 'GO'
        WHEN (
            COALESCE(gs.attractiveness_score,50)*0.25 +
            COALESCE(t.trend_score,50)*0.15 +
            COALESCE(pub.publisher_opportunity_score,50)*0.15 +
            COALESCE(e.entrant_score,50)*0.20 +
            COALESCE(p.platform_fit_score,50)*0.15 +
            COALESCE(r.region_score,50)*0.10
        ) >= 55 THEN 'CONDITIONAL'
        ELSE 'AVOID'
    END AS decision
FROM gp
LEFT JOIN genre_scores gs ON gs.genre = gp.genre
LEFT JOIN trend t ON t.genre = gp.genre
LEFT JOIN publisher pub ON pub.genre = gp.genre
LEFT JOIN entrant e ON e.genre = gp.genre
LEFT JOIN platform p ON p.platform = gp.platform
LEFT JOIN region r ON r.genre = gp.genre
ORDER BY scenario_score DESC;
