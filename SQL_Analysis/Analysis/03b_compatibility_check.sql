
-- ============================================================
-- 03b_phase4_compatibility.sql
-- Ensures Phase 4 has standardized launch-time columns.
-- ============================================================

SET search_path TO analysis, public;

DROP VIEW IF EXISTS v_phase4_game_base CASCADE;

CREATE OR REPLACE VIEW v_phase4_game_base AS
SELECT
    *,
    EXTRACT(MONTH FROM release_date)::integer AS release_month,
    EXTRACT(YEAR FROM release_date)::integer AS release_year
FROM v_game_sales_conformed;
