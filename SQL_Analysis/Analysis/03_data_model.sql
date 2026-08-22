-- =============================================================
-- 03_data_model.sql
-- Populate the normalized star schema (dimensions → facts) and
-- create common analytical views used by all downstream modules.
-- =============================================================


-- -----------------------------------------------
-- Dimension tables
-- -----------------------------------------------

TRUNCATE TABLE core.sales, core.game_releases, core.games, core.platforms, core.publishers RESTART IDENTITY CASCADE;

INSERT INTO core.publishers (publisher_name)
SELECT DISTINCT publisher
FROM staging.vgchartz_clean
ORDER BY publisher;

INSERT INTO core.platforms (platform_code)
SELECT DISTINCT console
FROM staging.vgchartz_clean
ORDER BY console;

-- Deduplicate games on (title, publisher) keeping the best-selling variant
INSERT INTO core.games (title, genre, publisher_id, developer)
SELECT DISTINCT ON (LOWER(c.title), p.publisher_id)
    c.title,
    c.genre,
    p.publisher_id,
    c.developer
FROM staging.vgchartz_clean c
JOIN core.publishers p ON p.publisher_name = c.publisher
ORDER BY LOWER(c.title), p.publisher_id,
         c.total_sales DESC,
         c.critic_score DESC NULLS LAST,
         c.source_row_id;

CREATE INDEX IF NOT EXISTS idx_games_publisher ON core.games(publisher_id);
CREATE INDEX IF NOT EXISTS idx_releases_game ON core.game_releases(game_id);
CREATE INDEX IF NOT EXISTS idx_releases_platform ON core.game_releases(platform_id);


-- -----------------------------------------------
-- Fact tables
-- -----------------------------------------------

INSERT INTO core.game_releases (game_id, platform_id, release_date, critic_score, source_row_id)
SELECT
    g.game_id,
    p.platform_id,
    c.release_date,
    c.critic_score,
    c.source_row_id
FROM staging.vgchartz_clean c
JOIN core.publishers pub ON pub.publisher_name = c.publisher
JOIN core.games g
  ON g.title = c.title
 AND g.publisher_id = pub.publisher_id
JOIN core.platforms p ON p.platform_code = c.console;

INSERT INTO core.sales (
    release_id, total_sales, na_sales, jp_sales, pal_sales, other_sales
)
SELECT
    gr.release_id,
    c.total_sales,
    c.na_sales,
    c.jp_sales,
    c.pal_sales,
    c.other_sales
FROM core.game_releases gr
JOIN staging.vgchartz_clean c ON c.source_row_id = gr.source_row_id;

CREATE INDEX IF NOT EXISTS idx_sales_total ON core.sales(total_sales);
CREATE INDEX IF NOT EXISTS idx_releases_year ON core.game_releases(release_year);

ANALYZE core.publishers;
ANALYZE core.platforms;
ANALYZE core.games;
ANALYZE core.game_releases;
ANALYZE core.sales;


-- -----------------------------------------------
-- Common analytical views
-- -----------------------------------------------

DROP VIEW IF EXISTS analysis.v_game_sales CASCADE;
DROP VIEW IF EXISTS analysis.v_market_share CASCADE;

-- Flattened game-level sales view joining all normalized entities
CREATE VIEW analysis.v_game_sales AS
SELECT
    gr.release_id,
    gr.source_row_id,
    g.game_id,
    g.title AS game_title,
    g.genre,
    g.developer,
    pub.publisher_id,
    pub.publisher_name,
    pl.platform_id,
    pl.platform_code AS platform,
    gr.release_date,
    gr.critic_score,
    gr.release_year AS year,
    s.total_sales,
    s.na_sales,
    s.jp_sales,
    s.pal_sales,
    s.other_sales
FROM core.game_releases gr
JOIN core.games g ON g.game_id = gr.game_id
JOIN core.publishers pub ON pub.publisher_id = g.publisher_id
JOIN core.platforms pl ON pl.platform_id = gr.platform_id
JOIN core.sales s ON s.release_id = gr.release_id;

-- Annual genre market share within the configured analysis window
CREATE VIEW analysis.v_market_share AS
WITH scoped AS (
    SELECT gs.*
    FROM analysis.v_game_sales gs
    CROSS JOIN analysis.parameters p
    WHERE gs.year BETWEEN p.analysis_start_year AND p.analysis_end_year
      AND gs.year IS NOT NULL
), yearly_total AS (
    SELECT year, SUM(total_sales) AS market_total
    FROM scoped
    GROUP BY year
)
SELECT
    s.genre,
    s.year,
    SUM(s.total_sales) AS genre_sales,
    ROUND((SUM(s.total_sales) / NULLIF(y.market_total,0) * 100)::NUMERIC, 4) AS market_share_pct
FROM scoped s
JOIN yearly_total y ON y.year = s.year
GROUP BY s.genre, s.year, y.market_total;

CREATE INDEX IF NOT EXISTS idx_staging_clean_title_platform ON staging.vgchartz_clean(title, console);
