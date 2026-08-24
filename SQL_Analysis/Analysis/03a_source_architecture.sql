-- =============================================================
-- 03_source_architecture.sql
-- Gaming Launch Intelligence
-- Phase 3: Multi-Source Data Architecture
-- =============================================================
--
-- Purpose:
--   Establish a conformed architecture for console and PC sources
--   without forcing incompatible measures into one fact table.
--
-- Design principle:
--   A game identity can be shared across sources, but the commercial
--   measures remain source-specific.
--
--   VGChartz / VGSales -> unit/sales-oriented observations
--   Steam Store        -> price, discount, metadata, reviews
--   SteamSpy           -> estimated ownership, CCU, playtime
--
--   Steam ownership is NOT treated as console sales.
--   Steam reviews are NOT treated as unit sales.
--   Critic scores are retained as post-launch diagnostics only.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS analysis;

-- -------------------------------------------------------------
-- 1. Source registry
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.source_registry (
    source_id SMALLINT PRIMARY KEY,
    source_name TEXT NOT NULL UNIQUE,
    source_domain TEXT NOT NULL,
    analytical_role TEXT NOT NULL,
    commercial_measure TEXT,
    grain_description TEXT NOT NULL,
    notes TEXT
);

INSERT INTO core.source_registry
(source_id, source_name, source_domain, analytical_role, commercial_measure, grain_description, notes)
VALUES
(1, 'VGChartz', 'Console / multi-platform', 'Primary historical console sales layer', 'Estimated game/platform sales (millions)', 'One game/platform observation', 'Used for historical console market structure and regional sales.'),
(2, 'Video Games Sales', 'Console / multi-platform', 'Historical validation / secondary console layer', 'Global/regional sales (millions)', 'One game/platform observation', 'Used as a cross-check and historical enrichment source, not blindly unioned with VGChartz.'),
(3, 'Steam Store', 'PC', 'PC launch and pricing layer', 'Price / discount / review metadata', 'One Steam title observation', 'Used for launch timing, pricing and store metadata.'),
(4, 'SteamSpy', 'PC', 'PC engagement layer', 'Estimated owners / CCU / playtime', 'One Steam app observation', 'Ownership is an estimate and must not be treated as unit sales.'),
(5, 'Steam Cleaned 2026', 'PC', 'PC catalog / modern metadata layer', NULL, 'One Steam AppID observation', 'Modern Steam catalog fields, including release date, reviews, pricing, genres and platform support.')
ON CONFLICT (source_id) DO UPDATE SET
    source_name = EXCLUDED.source_name,
    source_domain = EXCLUDED.source_domain,
    analytical_role = EXCLUDED.analytical_role,
    commercial_measure = EXCLUDED.commercial_measure,
    grain_description = EXCLUDED.grain_description,
    notes = EXCLUDED.notes;

-- -------------------------------------------------------------
-- 2. Platform family / generation mapping
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.platform_map (
    platform_code TEXT PRIMARY KEY,
    platform_family TEXT NOT NULL,
    platform_generation TEXT,
    manufacturer TEXT,
    is_pc BOOLEAN NOT NULL DEFAULT FALSE,
    is_console BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT
);

INSERT INTO core.platform_map
(platform_code, platform_family, platform_generation, manufacturer, is_pc, is_console, notes)
VALUES
('PC', 'PC', 'PC', 'Multiple', TRUE, FALSE, 'Desktop PC gaming.'),
('PS2', 'PlayStation', 'PS2', 'Sony', FALSE, TRUE, NULL),
('PS3', 'PlayStation', 'PS3', 'Sony', FALSE, TRUE, NULL),
('PS4', 'PlayStation', 'PS4', 'Sony', FALSE, TRUE, NULL),
('PS5', 'PlayStation', 'PS5', 'Sony', FALSE, TRUE, NULL),
('PSP', 'PlayStation', 'PSP', 'Sony', FALSE, TRUE, 'Portable; retained for historical analysis.'),
('PSV', 'PlayStation', 'PS Vita', 'Sony', FALSE, TRUE, 'Portable; retained for historical analysis.'),
('X360', 'Xbox', 'Xbox 360', 'Microsoft', FALSE, TRUE, NULL),
('XONE', 'Xbox', 'Xbox One', 'Microsoft', FALSE, TRUE, NULL),
('XB', 'Xbox', 'Xbox', 'Microsoft', FALSE, TRUE, 'Legacy / source-specific Xbox code.'),
('XBOX', 'Xbox', 'Xbox', 'Microsoft', FALSE, TRUE, 'Source-specific Xbox code.'),
('WII', 'Nintendo', 'Wii', 'Nintendo', FALSE, TRUE, NULL),
('WIIU', 'Nintendo', 'Wii U', 'Nintendo', FALSE, TRUE, NULL),
('NS', 'Nintendo', 'Switch', 'Nintendo', FALSE, TRUE, NULL),
('DS', 'Nintendo', 'DS', 'Nintendo', FALSE, TRUE, NULL),
('3DS', 'Nintendo', '3DS', 'Nintendo', FALSE, TRUE, NULL),
('GBA', 'Nintendo', 'Game Boy Advance', 'Nintendo', FALSE, TRUE, NULL),
('GC', 'Nintendo', 'GameCube', 'Nintendo', FALSE, TRUE, NULL),
('N64', 'Nintendo', 'Nintendo 64', 'Nintendo', FALSE, TRUE, NULL),
('NES', 'Nintendo', 'NES', 'Nintendo', FALSE, TRUE, NULL),
('SNES', 'Nintendo', 'SNES', 'Nintendo', FALSE, TRUE, NULL),
('GEN', 'Sega', 'Genesis', 'Sega', FALSE, TRUE, 'Historical platform; outside current PC/PS/Xbox focus.'),
('SAT', 'Sega', 'Saturn', 'Sega', FALSE, TRUE, NULL),
('DC', 'Sega', 'Dreamcast', 'Sega', FALSE, TRUE, NULL),
('PSN', 'Other', 'Digital / roll-up', NULL, FALSE, FALSE, 'Excluded from commercial game-level analysis.'),
('XBL', 'Other', 'Digital / roll-up', NULL, FALSE, FALSE, 'Excluded from commercial game-level analysis.')
ON CONFLICT (platform_code) DO UPDATE SET
    platform_family = EXCLUDED.platform_family,
    platform_generation = EXCLUDED.platform_generation,
    manufacturer = EXCLUDED.manufacturer,
    is_pc = EXCLUDED.is_pc,
    is_console = EXCLUDED.is_console,
    notes = EXCLUDED.notes;

-- Preserve any currently observed platform code without losing it.
INSERT INTO core.platform_map (platform_code, platform_family, platform_generation, is_pc, is_console, notes)
SELECT
    p.platform_code,
    CASE
        WHEN p.platform_code = 'PC' THEN 'PC'
        WHEN p.platform_code LIKE 'PS%' THEN 'PlayStation'
        WHEN p.platform_code IN ('XB','X360','XONE','XBOX') THEN 'Xbox'
        WHEN p.platform_code IN ('WII','WIIU','NS','DS','3DS','GBA','GC','N64','NES','SNES') THEN 'Nintendo'
        ELSE 'Other'
    END,
    p.platform_code,
    p.platform_code = 'PC',
    p.platform_code <> 'PC',
    'Fallback mapping generated for an observed platform code.'
FROM core.platforms p
WHERE NOT EXISTS (
    SELECT 1 FROM core.platform_map m
    WHERE m.platform_code = p.platform_code
);

-- =============================================================
-- Strategic launch platform universe
-- =============================================================
--
-- Business scope for the final launch recommendation layer.
--
-- The historical dataset supports:
--   PC
--   PlayStation 4
--   Xbox One
--
-- These are treated as the strategic launch platforms for
-- scenario recommendations.
--
-- Older generations remain available for historical analysis
-- but are excluded from final launch recommendations.
-- =============================================================

CREATE TABLE IF NOT EXISTS core.strategic_platform_universe (
    platform_code TEXT PRIMARY KEY,
    platform_family TEXT NOT NULL,
    strategic_status TEXT NOT NULL,
    rationale TEXT
);

INSERT INTO core.strategic_platform_universe (
    platform_code,
    platform_family,
    strategic_status,
    rationale
)
VALUES
(
    'PC',
    'PC',
    'IN_SCOPE',
    'Primary PC launch platform represented in the historical dataset.'
),
(
    'PS4',
    'PlayStation',
    'IN_SCOPE',
    'Primary PlayStation platform in the later historical launch period.'
),
(
    'XONE',
    'Xbox',
    'IN_SCOPE',
    'Primary Xbox platform in the later historical launch period.'
)
ON CONFLICT (platform_code) DO UPDATE SET
    platform_family = EXCLUDED.platform_family,
    strategic_status = EXCLUDED.strategic_status,
    rationale = EXCLUDED.rationale;

SELECT
    platform_code,
    platform_family,
    strategic_status,
    rationale
FROM core.strategic_platform_universe
ORDER BY platform_code;

-- -------------------------------------------------------------
-- 3. Enriched console view
-- -------------------------------------------------------------
DROP VIEW IF EXISTS analysis.v_game_sales_conformed CASCADE;

CREATE VIEW analysis.v_game_sales_conformed AS
SELECT
    gs.*,
    COALESCE(pm.platform_family, 'Other') AS platform_family,
    COALESCE(pm.platform_generation, gs.platform) AS platform_generation,
    pm.manufacturer,
    COALESCE(pm.is_pc, gs.platform = 'PC') AS is_pc,
    COALESCE(pm.is_console, gs.platform <> 'PC') AS is_console,
    1::SMALLINT AS source_id,
    'VGChartz'::TEXT AS source_name
FROM analysis.v_game_sales gs
LEFT JOIN core.platform_map pm
    ON pm.platform_code = gs.platform;

-- -------------------------------------------------------------
-- 4. Source-safe game identity key
-- -------------------------------------------------------------
-- This is intentionally a normalized key, not an automatic match.
-- Cross-source matching will use title + developer/publisher + year
-- evidence in Phase 3's Python audit before bridge records are created.
-- -------------------------------------------------------------
DROP VIEW IF EXISTS analysis.v_vgchartz_identity_candidates CASCADE;

CREATE VIEW analysis.v_vgchartz_identity_candidates AS
SELECT DISTINCT
    game_id,
    LOWER(REGEXP_REPLACE(TRIM(game_title), '[^a-z0-9]+', ' ', 'g')) AS normalized_title,
    LOWER(REGEXP_REPLACE(TRIM(COALESCE(publisher_name, '')), '[^a-z0-9]+', ' ', 'g')) AS normalized_publisher,
    LOWER(REGEXP_REPLACE(TRIM(COALESCE(developer, '')), '[^a-z0-9]+', ' ', 'g')) AS normalized_developer,
    year AS release_year,
    game_title,
    publisher_name,
    developer,
    genre
FROM analysis.v_game_sales_conformed;

-- -------------------------------------------------------------
-- 5. Data lineage / grain audit view
-- -------------------------------------------------------------
DROP VIEW IF EXISTS analysis.v_source_lineage_summary CASCADE;

CREATE VIEW analysis.v_source_lineage_summary AS
SELECT
    source_id,
    source_name,
    'game_platform_release' AS grain,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT game_id) AS game_count,
    COUNT(DISTINCT platform) AS platform_count,
    MIN(year) AS min_year,
    MAX(year) AS max_year
FROM analysis.v_game_sales_conformed
GROUP BY source_id, source_name;

-- -------------------------------------------------------------
-- 6. Phase 3 validation checks
-- -------------------------------------------------------------
SELECT *
FROM core.source_registry
ORDER BY source_id;

SELECT *
FROM analysis.v_source_lineage_summary;

SELECT
    platform_family,
    COUNT(*) AS observations,
    COUNT(DISTINCT platform) AS platform_count,
    SUM(total_sales) AS total_sales
FROM analysis.v_game_sales_conformed
GROUP BY platform_family
ORDER BY total_sales DESC;
