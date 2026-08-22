-- =============================================================
-- 01_setup_and_load.sql
-- Initialize schemas, reset dependent objects, and load the
-- raw VGChartz CSV into untouched staging.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS analysis;

-- Drop dependent views and tables in reverse-dependency order
-- so the pipeline can be rerun idempotently.
DROP VIEW IF EXISTS analysis.v_game_sales CASCADE;
DROP VIEW IF EXISTS analysis.v_market_share CASCADE;
DROP VIEW IF EXISTS analysis.v_genre_attractiveness CASCADE;
DROP VIEW IF EXISTS analysis.v_market_trend CASCADE;
DROP VIEW IF EXISTS analysis.v_publisher_concentration CASCADE;
DROP VIEW IF EXISTS analysis.v_new_entrant_performance CASCADE;
DROP VIEW IF EXISTS analysis.v_active_platforms CASCADE;
DROP VIEW IF EXISTS analysis.v_platform_fit CASCADE;
DROP VIEW IF EXISTS analysis.v_platform_lifecycle CASCADE;
DROP VIEW IF EXISTS analysis.v_regional_opportunity CASCADE;
DROP VIEW IF EXISTS analysis.v_regional_correlation CASCADE;
DROP VIEW IF EXISTS analysis.v_genre_best_region CASCADE;
DROP VIEW IF EXISTS analysis.v_genre_platform_fit CASCADE;
DROP VIEW IF EXISTS analysis.v_launch_simulator CASCADE;
DROP VIEW IF EXISTS analysis.v_marketing_allocation CASCADE;

DROP TABLE IF EXISTS analysis.launch_config CASCADE;
DROP TABLE IF EXISTS analysis.parameters CASCADE;
DROP TABLE IF EXISTS core.sales CASCADE;
DROP TABLE IF EXISTS core.game_releases CASCADE;
DROP TABLE IF EXISTS core.games CASCADE;
DROP TABLE IF EXISTS core.platforms CASCADE;
DROP TABLE IF EXISTS core.publishers CASCADE;
DROP TABLE IF EXISTS staging.vgchartz_clean CASCADE;
DROP TABLE IF EXISTS staging.vgchartz_raw CASCADE;


-- -----------------------------------------------
-- Staging tables
-- -----------------------------------------------

CREATE TABLE staging.vgchartz_raw (
    source_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    img TEXT,
    title TEXT,
    console TEXT,
    genre TEXT,
    publisher TEXT,
    developer TEXT,
    critic_score TEXT,
    total_sales TEXT,
    na_sales TEXT,
    jp_sales TEXT,
    pal_sales TEXT,
    other_sales TEXT,
    release_date TEXT,
    last_update TEXT
);

CREATE TABLE staging.vgchartz_clean (
    source_row_id BIGINT PRIMARY KEY,
    title TEXT NOT NULL,
    console TEXT NOT NULL,
    genre TEXT,
    publisher TEXT NOT NULL,
    developer TEXT,
    critic_score NUMERIC(4,2),
    total_sales NUMERIC(10,2) NOT NULL,
    na_sales NUMERIC(10,2),
    jp_sales NUMERIC(10,2),
    pal_sales NUMERIC(10,2),
    other_sales NUMERIC(10,2),
    release_date DATE,
    last_update DATE
);


-- -----------------------------------------------
-- Core normalized tables
-- -----------------------------------------------

CREATE TABLE core.publishers (
    publisher_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    publisher_name TEXT NOT NULL UNIQUE
);

CREATE TABLE core.platforms (
    platform_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    platform_code TEXT NOT NULL UNIQUE
);

CREATE TABLE core.games (
    game_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title TEXT NOT NULL,
    genre TEXT,
    publisher_id BIGINT NOT NULL REFERENCES core.publishers(publisher_id),
    developer TEXT,
    UNIQUE(title, publisher_id)
);

CREATE TABLE core.game_releases (
    release_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    game_id BIGINT NOT NULL REFERENCES core.games(game_id) ON DELETE CASCADE,
    platform_id BIGINT NOT NULL REFERENCES core.platforms(platform_id),
    release_date DATE,
    critic_score NUMERIC(4,2),
    release_year INT GENERATED ALWAYS AS (EXTRACT(YEAR FROM release_date)::INT) STORED,
    source_row_id BIGINT NOT NULL,
    UNIQUE(game_id, platform_id, release_date, source_row_id)
);

CREATE TABLE core.sales (
    release_id BIGINT PRIMARY KEY REFERENCES core.game_releases(release_id) ON DELETE CASCADE,
    total_sales NUMERIC(10,2) NOT NULL,
    na_sales NUMERIC(10,2),
    jp_sales NUMERIC(10,2),
    pal_sales NUMERIC(10,2),
    other_sales NUMERIC(10,2)
);


-- -----------------------------------------------
-- Analysis configuration tables
-- -----------------------------------------------

-- Singleton row holds the tunable parameters that scope every downstream view.
CREATE TABLE analysis.parameters (
    parameter_id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (parameter_id = 1),
    analysis_start_year INT NOT NULL DEFAULT 2006,
    analysis_end_year INT NOT NULL DEFAULT 2018,
    min_year_rows INT NOT NULL DEFAULT 100,
    top_n_titles INT NOT NULL DEFAULT 10,
    top_n_publishers INT NOT NULL DEFAULT 5,
    min_platform_releases INT NOT NULL DEFAULT 25,
    min_genre_platform_releases INT NOT NULL DEFAULT 20
);

INSERT INTO analysis.parameters DEFAULT VALUES;

-- Holds the planned launch scenario; NULL columns default to "evaluate all".
CREATE TABLE analysis.launch_config (
    scenario_id SMALLINT PRIMARY KEY DEFAULT 1,
    target_title TEXT,
    target_genre TEXT,
    target_platform TEXT,
    primary_region TEXT,
    marketing_budget_millions NUMERIC(12,2),
    notes TEXT
);

INSERT INTO analysis.launch_config
(target_title, target_genre, target_platform, primary_region, marketing_budget_millions, notes)
VALUES
(NULL, NULL, NULL, 'global', NULL,
 'Replace target_genre/target_platform with the planned launch. Budget is optional; outputs remain percentage-based when NULL.');


-- -----------------------------------------------
-- Load raw CSV
-- -----------------------------------------------

TRUNCATE TABLE staging.vgchartz_raw RESTART IDENTITY;

COPY staging.vgchartz_raw (img,title,console,genre,publisher,developer,critic_score,total_sales,na_sales,jp_sales,pal_sales,other_sales,release_date,last_update)
FROM 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\Game_Data\vgchartz-2024.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- Confirm load
SELECT COUNT(*) AS raw_rows FROM staging.vgchartz_raw;
