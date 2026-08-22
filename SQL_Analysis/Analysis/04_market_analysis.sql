-- =============================================================
-- 04_market_analysis.sql
-- Full market-analysis layer: genre attractiveness, market trends,
-- publisher concentration, new-entrant benchmarks, platform fit,
-- regional opportunity, and genre-platform fit.
-- =============================================================


-- -----------------------------------------------
-- Genre attractiveness
-- Scores each genre on sales productivity and title-level
-- concentration (HHI + top-N share).
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_genre_attractiveness CASCADE;

CREATE VIEW analysis.v_genre_attractiveness AS
WITH scoped AS (
    SELECT gs.*
    FROM analysis.v_game_sales gs
    CROSS JOIN analysis.parameters p
    WHERE gs.year BETWEEN p.analysis_start_year AND p.analysis_end_year
),
game_sales AS (
    SELECT
        genre,
        game_title,
        SUM(total_sales) AS title_sales
    FROM scoped
    WHERE genre IS NOT NULL
    GROUP BY genre, game_title
),
shares AS (
    SELECT
        genre,
        game_title,
        title_sales,
        title_sales / NULLIF(SUM(title_sales) OVER (PARTITION BY genre),0) AS sales_share,
        ROW_NUMBER() OVER (PARTITION BY genre ORDER BY title_sales DESC) AS title_rank
    FROM game_sales
),
stats AS (
    SELECT
        genre,
        COUNT(*) AS title_count,
        AVG(title_sales) AS avg_sales_per_title,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY title_sales) AS median_sales_per_title,
        SUM(sales_share) FILTER (
            WHERE title_rank <= (SELECT top_n_titles FROM analysis.parameters)
        ) AS top10_share,
        SUM(POWER(sales_share,2)) AS title_hhi
    FROM shares
    GROUP BY genre
),
minmax AS (
    SELECT
        MIN(title_hhi) AS min_hhi,
        MAX(title_hhi) AS max_hhi,
        MIN(median_sales_per_title) AS min_median_sales,
        MAX(median_sales_per_title) AS max_median_sales
    FROM stats
),
scored AS (
    SELECT
        s.*,
        (s.title_hhi - m.min_hhi) / NULLIF(m.max_hhi - m.min_hhi,0) AS concentration_norm,
        (s.median_sales_per_title - m.min_median_sales) /
            NULLIF(m.max_median_sales - m.min_median_sales,0) AS sales_norm
    FROM stats s
    CROSS JOIN minmax m
),
weights AS (
    -- Adaptive weighting: HHI vs top-10 share, proportional to each metric's cross-genre dispersion
    SELECT
        STDDEV(1 - concentration_norm) AS dispersion_hhi,
        STDDEV(1 - top10_share) AS dispersion_top10
    FROM scored
),
final AS (
    SELECT
        s.*,
        CASE
            WHEN (w.dispersion_hhi + w.dispersion_top10) = 0 THEN 0.5
            ELSE w.dispersion_hhi / (w.dispersion_hhi + w.dispersion_top10)
        END AS hhi_weight,
        CASE
            WHEN (w.dispersion_hhi + w.dispersion_top10) = 0 THEN 0.5
            ELSE w.dispersion_top10 / (w.dispersion_hhi + w.dispersion_top10)
        END AS top10_weight
    FROM scored s
    CROSS JOIN weights w
)
SELECT
    genre,
    title_count,
    ROUND(avg_sales_per_title::NUMERIC,4) AS avg_sales_per_title,
    ROUND(median_sales_per_title::NUMERIC,4) AS median_sales_per_title,
    ROUND((top10_share*100)::NUMERIC,2) AS top10_share_pct,
    ROUND(title_hhi::NUMERIC,5) AS title_hhi,
    ROUND(concentration_norm::NUMERIC,4) AS concentration_norm,
    ROUND(sales_norm::NUMERIC,4) AS sales_norm,
    ROUND((median_sales_per_title *
        (hhi_weight * (1-concentration_norm) + top10_weight * (1-top10_share)))::NUMERIC,4)
        AS attractiveness_raw,
    ROUND(((sales_norm * 0.60 + (1-concentration_norm) * 0.40) * 100)::NUMERIC,2)
        AS attractiveness_score
FROM final;

SELECT *
FROM analysis.v_genre_attractiveness
ORDER BY attractiveness_score DESC;


-- -----------------------------------------------
-- Market trends
-- OLS slope of annual market share per genre to identify
-- growing vs. declining segments.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_market_trend CASCADE;

CREATE VIEW analysis.v_market_trend AS
WITH genre_stats AS (
    SELECT
        genre,
        AVG(year) AS avg_year,
        AVG(market_share_pct) AS avg_share
    FROM analysis.v_market_share
    WHERE genre IS NOT NULL
    GROUP BY genre
),
slopes AS (
    SELECT
        m.genre,
        SUM((m.year - g.avg_year) * (m.market_share_pct - g.avg_share)) /
            NULLIF(SUM(POWER(m.year - g.avg_year,2)),0) AS trend_slope
    FROM analysis.v_market_share m
    JOIN genre_stats g ON g.genre = m.genre
    GROUP BY m.genre
),
minmax AS (
    SELECT MIN(trend_slope) AS min_slope, MAX(trend_slope) AS max_slope
    FROM slopes
)
SELECT
    s.genre,
    ROUND(s.trend_slope::NUMERIC,5) AS trend_slope,
    ROUND(((s.trend_slope-m.min_slope) /
        NULLIF(m.max_slope-m.min_slope,0) * 100)::NUMERIC,2) AS trend_score
FROM slopes s
CROSS JOIN minmax m;

-- Year-over-year market share with z-scores for outlier detection
SELECT
    genre,
    year,
    ROUND(market_share_pct::NUMERIC,2) AS market_share_pct,
    ROUND(((market_share_pct - AVG(market_share_pct) OVER (PARTITION BY genre)) /
        NULLIF(STDDEV(market_share_pct) OVER (PARTITION BY genre),0))::NUMERIC,4) AS genre_z_score
FROM analysis.v_market_share
ORDER BY genre, year;

SELECT *
FROM analysis.v_market_trend
ORDER BY trend_score DESC;


-- -----------------------------------------------
-- Publisher concentration
-- HHI and top-5 publisher share per genre to gauge
-- competitive openness for a new entrant.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_publisher_concentration CASCADE;

CREATE VIEW analysis.v_publisher_concentration AS
WITH scoped AS (
    SELECT gs.*
    FROM analysis.v_game_sales gs
    CROSS JOIN analysis.parameters p
    WHERE gs.year BETWEEN p.analysis_start_year AND p.analysis_end_year
      AND gs.genre IS NOT NULL
), publisher_sales AS (
    SELECT genre, publisher_name, SUM(total_sales) AS publisher_sales
    FROM scoped
    GROUP BY genre, publisher_name
), shares AS (
    SELECT
        genre,
        publisher_name,
        publisher_sales,
        publisher_sales / NULLIF(SUM(publisher_sales) OVER (PARTITION BY genre),0) AS sales_share,
        ROW_NUMBER() OVER (PARTITION BY genre ORDER BY publisher_sales DESC) AS publisher_rank
    FROM publisher_sales
), stats AS (
    SELECT
        genre,
        SUM(publisher_sales) FILTER (WHERE publisher_rank <= (SELECT top_n_publishers FROM analysis.parameters)) AS top5_sales,
        SUM(sales_share) FILTER (WHERE publisher_rank <= (SELECT top_n_publishers FROM analysis.parameters)) AS top5_share,
        SUM(POWER(sales_share,2)) AS publisher_hhi
    FROM shares
    GROUP BY genre
), minmax AS (
    SELECT MIN(publisher_hhi) AS min_hhi, MAX(publisher_hhi) AS max_hhi
    FROM stats
)
SELECT
    s.genre,
    ROUND(s.top5_sales::NUMERIC,2) AS top5_publisher_sales,
    ROUND((s.top5_share*100)::NUMERIC,2) AS top5_publisher_share_pct,
    ROUND(s.publisher_hhi::NUMERIC,5) AS publisher_hhi,
    ROUND(((s.publisher_hhi-m.min_hhi) /
        NULLIF(m.max_hhi-m.min_hhi,0))::NUMERIC,4) AS concentration_norm,
    ROUND(((1-((s.publisher_hhi-m.min_hhi) /
        NULLIF(m.max_hhi-m.min_hhi,0))) * 100)::NUMERIC,2) AS publisher_opportunity_score
FROM stats s
CROSS JOIN minmax m;

SELECT *
FROM analysis.v_publisher_concentration
ORDER BY publisher_opportunity_score DESC;


-- -----------------------------------------------
-- New-entrant performance
-- Benchmarks first-time publisher entries against the
-- genre-year median to estimate accessibility.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_new_entrant_performance CASCADE;

CREATE VIEW analysis.v_new_entrant_performance AS
WITH publisher_genre_titles AS (
    SELECT
        publisher_name,
        genre,
        game_title,
        MIN(year) AS first_year
    FROM analysis.v_game_sales
    WHERE genre IS NOT NULL
    GROUP BY publisher_name, genre, game_title
),
ranked AS (
    SELECT
        publisher_name,
        genre,
        game_title,
        first_year,
        ROW_NUMBER() OVER (
            PARTITION BY publisher_name, genre
            ORDER BY first_year, game_title
        ) AS entry_rank
    FROM publisher_genre_titles
),
genre_year_median AS (
    SELECT
        genre,
        year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_sales) AS median_sales
    FROM analysis.v_game_sales
    WHERE genre IS NOT NULL AND year IS NOT NULL
    GROUP BY genre, year
),
entry_sales AS (
    SELECT
        r.publisher_name,
        r.genre,
        r.game_title,
        r.first_year AS year,
        SUM(gs.total_sales) AS total_sales
    FROM ranked r
    JOIN analysis.v_game_sales gs
      ON gs.publisher_name = r.publisher_name
     AND gs.genre = r.genre
     AND gs.game_title = r.game_title
     AND gs.year = r.first_year
    CROSS JOIN analysis.parameters p
    WHERE r.entry_rank = 1
      AND r.first_year >= p.analysis_start_year
      AND r.first_year <= p.analysis_end_year
    GROUP BY r.publisher_name, r.genre, r.game_title, r.first_year
)
SELECT
    e.publisher_name,
    e.genre,
    e.game_title,
    e.year,
    ROUND(e.total_sales::NUMERIC,4) AS total_sales,
    ROUND(m.median_sales::NUMERIC,4) AS genre_year_median,
    ROUND((e.total_sales / NULLIF(m.median_sales,0))::NUMERIC,2) AS vs_median_ratio,
    CASE
        WHEN e.total_sales >= m.median_sales * 2 THEN 'strong breakout'
        WHEN e.total_sales >= m.median_sales THEN 'above median'
        WHEN e.total_sales >= m.median_sales * 0.5 THEN 'below median'
        ELSE 'weak entry'
    END AS entry_performance
FROM entry_sales e
JOIN genre_year_median m
  ON m.genre = e.genre
 AND m.year = e.year;

-- Aggregated entrant success rate by genre
SELECT
    genre,
    COUNT(*) AS first_entrants,
    COUNT(*) FILTER (WHERE entry_performance IN ('strong breakout','above median')) AS successful_entries,
    ROUND((COUNT(*) FILTER (WHERE entry_performance IN ('strong breakout','above median')) * 100.0 /
        NULLIF(COUNT(*),0))::NUMERIC,2) AS breakout_rate_pct,
    ROUND(AVG(vs_median_ratio)::NUMERIC,2) AS avg_vs_median
FROM analysis.v_new_entrant_performance
GROUP BY genre
ORDER BY breakout_rate_pct DESC;


-- -----------------------------------------------
-- Active platforms
-- Platforms that received releases in the last two years of the
-- analysis window. Extracted as its own view (was previously
-- inlined only in v_platform_fit) so every downstream view that
-- needs to scope itself to currently-relevant platforms -- notably
-- v_genre_platform_fit, which feeds the launch simulator -- uses
-- the same definition instead of silently including retired
-- hardware like PS2/DS/PSP.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_active_platforms CASCADE;

CREATE VIEW analysis.v_active_platforms AS
SELECT DISTINCT gs.platform
FROM analysis.v_game_sales gs
CROSS JOIN analysis.parameters p
WHERE gs.year BETWEEN p.analysis_end_year - 1 AND p.analysis_end_year;


-- -----------------------------------------------
-- Platform fit & lifecycle
-- Scores platforms on sales efficiency, release share,
-- and title-sales distribution breadth.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_platform_fit CASCADE;
DROP VIEW IF EXISTS analysis.v_platform_lifecycle CASCADE;

CREATE VIEW analysis.v_platform_fit AS
WITH p AS (SELECT * FROM analysis.parameters),
scoped AS (
    SELECT gs.*
    FROM analysis.v_game_sales gs
    JOIN analysis.v_active_platforms ap ON ap.platform = gs.platform
    CROSS JOIN p
    WHERE gs.year BETWEEN p.analysis_start_year AND p.analysis_end_year
),
platform_stats AS (
    SELECT
        platform,
        COUNT(*) AS release_count,
        SUM(total_sales) AS total_sales,
        SUM(total_sales) / NULLIF(COUNT(*),0) AS sales_per_release,
        SUM(total_sales) / NULLIF(SUM(SUM(total_sales)) OVER (),0) AS sales_share,
        COUNT(*)::NUMERIC / NULLIF(SUM(COUNT(*)) OVER (),0) AS release_share
    FROM scoped
    GROUP BY platform
),
title_sales AS (
    SELECT platform, game_title, SUM(total_sales) AS title_sales
    FROM scoped
    GROUP BY platform, game_title
),
title_shares AS (
    SELECT
        platform,
        game_title,
        title_sales,
        title_sales / NULLIF(SUM(title_sales) OVER (PARTITION BY platform),0) AS sales_share
    FROM title_sales
),
platform_hhi AS (
    SELECT
        platform,
        SUM(POWER(sales_share,2)) AS title_hhi
    FROM title_shares
    GROUP BY platform
),
joined AS (
    SELECT s.*, h.title_hhi
    FROM platform_stats s
    JOIN platform_hhi h USING(platform)
    WHERE s.release_count >= (SELECT min_platform_releases FROM analysis.parameters)
),
mm AS (
    SELECT
        MIN(sales_per_release) min_spr, MAX(sales_per_release) max_spr,
        MIN(release_share) min_release_share, MAX(release_share) max_release_share,
        MIN(title_hhi) min_hhi, MAX(title_hhi) max_hhi
    FROM joined
)
SELECT
    j.platform,
    j.release_count,
    ROUND(j.total_sales::NUMERIC,2) AS total_sales,
    ROUND(j.sales_per_release::NUMERIC,4) AS sales_per_release,
    ROUND((j.release_share*100)::NUMERIC,2) AS release_share_pct,
    ROUND(j.title_hhi::NUMERIC,5) AS title_hhi,
    ROUND(((j.sales_per_release-mm.min_spr)/NULLIF(mm.max_spr-mm.min_spr,0)*100)::NUMERIC,2) AS efficiency_score,
    ROUND(((j.release_share-mm.min_release_share)/NULLIF(mm.max_release_share-mm.min_release_share,0)*100)::NUMERIC,2) AS presence_score,
    ROUND(((1-((j.title_hhi-mm.min_hhi)/NULLIF(mm.max_hhi-mm.min_hhi,0)))*100)::NUMERIC,2) AS distribution_score,
    ROUND((
        ((j.sales_per_release-mm.min_spr)/NULLIF(mm.max_spr-mm.min_spr,0))*0.50 +
        ((j.release_share-mm.min_release_share)/NULLIF(mm.max_release_share-mm.min_release_share,0))*0.25 +
        (1-((j.title_hhi-mm.min_hhi)/NULLIF(mm.max_hhi-mm.min_hhi,0)))*0.25
    )*100::NUMERIC,2) AS platform_fit_score
FROM joined j
CROSS JOIN mm;

CREATE VIEW analysis.v_platform_lifecycle AS
SELECT
    platform,
    year,
    COUNT(*) AS release_count,
    ROUND((COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER (PARTITION BY year) * 100),2) AS release_share_pct
FROM analysis.v_game_sales
WHERE year IS NOT NULL
GROUP BY platform, year
ORDER BY platform, year;

SELECT *
FROM analysis.v_platform_fit
ORDER BY platform_fit_score DESC;


-- -----------------------------------------------
-- Regional opportunity & correlation
-- Identifies genres that over-index in specific regions
-- and quantifies pairwise regional sales correlation.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_regional_opportunity CASCADE;
DROP VIEW IF EXISTS analysis.v_regional_correlation CASCADE;

CREATE VIEW analysis.v_regional_opportunity AS
WITH genre_region AS (
    SELECT
        genre,
        SUM(na_sales) AS na_sales,
        SUM(jp_sales) AS jp_sales,
        SUM(pal_sales) AS pal_sales,
        SUM(other_sales) AS other_sales,
        SUM(total_sales) AS global_sales
    FROM analysis.v_game_sales
    WHERE genre IS NOT NULL
    GROUP BY genre
),
region_totals AS (
    SELECT
        SUM(na_sales) AS na_total,
        SUM(jp_sales) AS jp_total,
        SUM(pal_sales) AS pal_total,
        SUM(other_sales) AS other_total,
        SUM(global_sales) AS global_total
    FROM genre_region
),
long_form AS (
    SELECT genre, 'NA' AS region, na_sales AS region_sales, na_total AS region_total, global_sales, global_total FROM genre_region CROSS JOIN region_totals
    UNION ALL
    SELECT genre, 'JP', jp_sales, jp_total, global_sales, global_total FROM genre_region CROSS JOIN region_totals
    UNION ALL
    SELECT genre, 'PAL', pal_sales, pal_total, global_sales, global_total FROM genre_region CROSS JOIN region_totals
    UNION ALL
    SELECT genre, 'OTHER', other_sales, other_total, global_sales, global_total FROM genre_region CROSS JOIN region_totals
),
scored AS (
    SELECT
        genre,
        region,
        region_sales / NULLIF(region_total,0) * 100 AS region_genre_share_pct,
        global_sales / NULLIF(global_total,0) * 100 AS global_genre_share_pct,
        (region_sales / NULLIF(region_total,0) - global_sales / NULLIF(global_total,0)) * 100 AS skew_pct,
        region_sales / NULLIF(global_sales,0) * 100 AS region_mix_of_genre_pct
    FROM long_form
)
SELECT
    genre,
    region,
    ROUND(region_genre_share_pct::NUMERIC,2) AS region_genre_share_pct,
    ROUND(global_genre_share_pct::NUMERIC,2) AS global_genre_share_pct,
    ROUND(skew_pct::NUMERIC,2) AS skew_pct,
    ROUND(region_mix_of_genre_pct::NUMERIC,2) AS region_mix_of_genre_pct,
    CASE
        WHEN skew_pct >= 2 THEN 'strong regional over-index'
        WHEN skew_pct > 0 THEN 'regional over-index'
        WHEN skew_pct <= -2 THEN 'regional under-index'
        ELSE 'neutral'
    END AS regional_signal
FROM scored;

-- Pairwise Pearson correlation matrix across the four sales regions
CREATE VIEW analysis.v_regional_correlation AS
WITH corr AS (
    SELECT
        CORR(na_sales, na_sales) na,
        CORR(na_sales, jp_sales) na_jp,
        CORR(na_sales, pal_sales) na_pal,
        CORR(na_sales, other_sales) na_other,
        CORR(na_sales, total_sales) na_global,
        CORR(jp_sales, pal_sales) jp_pal,
        CORR(jp_sales, other_sales) jp_other,
        CORR(jp_sales, total_sales) jp_global,
        CORR(pal_sales, other_sales) pal_other,
        CORR(pal_sales, total_sales) pal_global,
        CORR(other_sales, total_sales) other_global
    FROM analysis.v_game_sales
)
SELECT 'NA' AS region, ROUND(na::NUMERIC,2) na, ROUND(na_jp::NUMERIC,2) jp, ROUND(na_pal::NUMERIC,2) pal, ROUND(na_other::NUMERIC,2) other, ROUND(na_global::NUMERIC,2) global FROM corr
UNION ALL
SELECT 'JP', ROUND(na_jp::NUMERIC,2), 1.00, ROUND(jp_pal::NUMERIC,2), ROUND(jp_other::NUMERIC,2), ROUND(jp_global::NUMERIC,2) FROM corr
UNION ALL
SELECT 'PAL', ROUND(na_pal::NUMERIC,2), ROUND(jp_pal::NUMERIC,2), 1.00, ROUND(pal_other::NUMERIC,2), ROUND(pal_global::NUMERIC,2) FROM corr
UNION ALL
SELECT 'OTHER', ROUND(na_other::NUMERIC,2), ROUND(jp_other::NUMERIC,2), ROUND(pal_other::NUMERIC,2), 1.00, ROUND(other_global::NUMERIC,2) FROM corr
UNION ALL
SELECT 'GLOBAL', ROUND(na_global::NUMERIC,2), ROUND(jp_global::NUMERIC,2), ROUND(pal_global::NUMERIC,2), ROUND(other_global::NUMERIC,2), 1.00 FROM corr;

SELECT *
FROM analysis.v_regional_opportunity
ORDER BY genre, skew_pct DESC;

SELECT * FROM analysis.v_regional_correlation;


-- -----------------------------------------------
-- Genre best-region fit
-- Picks each genre's single strongest regional skew, then scores
-- that skew's strength against every OTHER genre's best skew.
--
-- This replaces a pattern that used to live inline in
-- 05_launch_decision.sql: PERCENT_RANK() partitioned by genre over
-- just that genre's 4 regions, then DISTINCT ON to keep the top
-- row. That always selects the maximum of its own partition, and
-- PERCENT_RANK() of the maximum row in any partition is
-- mathematically always 1.0 -- so the resulting "regional
-- opportunity score" was a constant 100 for every genre, silently
-- contributing zero discriminative signal to the launch score
-- despite being weighted at 10%. Confirmed by running the pipeline:
-- COUNT(DISTINCT regional_opportunity_score) over all 130 launch
-- scenarios was 1.
--
-- The fix: pick the best region per genre first (ROW_NUMBER, not
-- PERCENT_RANK), then rank that one number per genre against the
-- other genres' best-region skew (PERCENT_RANK with no PARTITION
-- BY). Now a genre with a strongly skewed best region (e.g.
-- Role-Playing, JP +12.66pp) scores near 100, and a genre with a
-- barely-skewed best region (e.g. Music, JP +0.07pp) scores near 0
-- -- the score finally differentiates genres from each other.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_genre_best_region CASCADE;

CREATE VIEW analysis.v_genre_best_region AS
WITH best AS (
    SELECT
        genre,
        region,
        region_genre_share_pct,
        global_genre_share_pct,
        skew_pct,
        region_mix_of_genre_pct,
        ROW_NUMBER() OVER (PARTITION BY genre ORDER BY skew_pct DESC) AS region_rank
    FROM analysis.v_regional_opportunity
)
SELECT
    genre,
    region AS recommended_region,
    region_genre_share_pct,
    global_genre_share_pct,
    skew_pct AS recommended_region_skew_pct,
    region_mix_of_genre_pct,
    ROUND((100 * PERCENT_RANK() OVER (ORDER BY skew_pct))::NUMERIC, 2) AS regional_opportunity_score
FROM best
WHERE region_rank = 1;

SELECT *
FROM analysis.v_genre_best_region
ORDER BY regional_opportunity_score DESC;


-- -----------------------------------------------
-- Genre × platform fit
-- Identifies the strongest platform choices within each genre
-- ranked by median sales per release. Scoped to currently-active
-- platforms (via v_active_platforms) so retired hardware doesn't
-- surface as a launch recommendation.
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_genre_platform_fit CASCADE;

CREATE VIEW analysis.v_genre_platform_fit AS
WITH scoped AS (
    SELECT gs.*
    FROM analysis.v_game_sales gs
    JOIN analysis.v_active_platforms ap ON ap.platform = gs.platform
    CROSS JOIN analysis.parameters p
    WHERE gs.year BETWEEN p.analysis_start_year AND p.analysis_end_year
      AND gs.genre IS NOT NULL
),
stats AS (
    SELECT
        genre,
        platform,
        COUNT(*) AS release_count,
        SUM(total_sales) AS total_sales,
        AVG(total_sales) AS avg_sales_per_release,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_sales) AS median_sales_per_release
    FROM scoped
    GROUP BY genre, platform
    HAVING COUNT(*) >= (SELECT min_genre_platform_releases FROM analysis.parameters)
),
platform_totals AS (
    SELECT platform, SUM(total_sales) AS platform_total
    FROM stats
    GROUP BY platform
),
ranked AS (
    SELECT
        s.*,
        s.total_sales / NULLIF(pt.platform_total,0) AS genre_share_of_platform,
        ROW_NUMBER() OVER (PARTITION BY genre ORDER BY median_sales_per_release DESC) AS rank_in_genre
    FROM stats s
    JOIN platform_totals pt USING(platform)
)
SELECT
    genre,
    platform,
    release_count,
    ROUND(total_sales::NUMERIC,2) AS total_sales,
    ROUND(avg_sales_per_release::NUMERIC,4) AS avg_sales_per_release,
    ROUND(median_sales_per_release::NUMERIC,4) AS median_sales_per_release,
    ROUND((genre_share_of_platform*100)::NUMERIC,2) AS genre_share_of_platform_pct,
    rank_in_genre
FROM ranked;

SELECT *
FROM analysis.v_genre_platform_fit
WHERE rank_in_genre <= 5
ORDER BY genre, rank_in_genre;
