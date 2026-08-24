-- ============================================================
-- 07_final_decision_engine.sql
-- Gaming Launch Intelligence
-- Phase 5: Final Strategic Decision Engine
-- ============================================================
--
-- Purpose:
--   Combine the outputs of Phases 1-4 into a transparent,
--   evidence-aware launch decision framework.
--
-- SUCCESS PROBABILITY
--   Statistical estimate from the pre-launch model.
--
-- OPPORTUNITY SCORE
--   Strategic attractiveness of the market/scenario.
--
-- EVIDENCE QUALITY
--   Strength of the historical evidence supporting the scenario.
--
-- COMPETITION PRESSURE
--   Historical release density around comparable launches.
--
-- These dimensions remain separate. The strategic score is a
-- decision score, not a probability.
-- ============================================================

SET search_path TO analysis, public;

DROP VIEW IF EXISTS v_final_launch_decision CASCADE;
DROP VIEW IF EXISTS v_final_scenario_score CASCADE;
DROP VIEW IF EXISTS v_final_scenario_inputs CASCADE;
DROP VIEW IF EXISTS v_scenario_competition_pressure CASCADE;


-- ============================================================
-- 1. Scenario inputs
--
-- Unit:
--   genre x platform x region x recommended launch month
-- ============================================================

CREATE OR REPLACE VIEW v_final_scenario_inputs AS

WITH genre_market AS (

    SELECT
        genre,
        opportunity_score,
        evidence_quality_final AS evidence_quality,
        demand_potential_score,
        momentum_score,
        competitive_accessibility_score

    FROM v_phase2_market_opportunity
),

platform_fit AS (

    SELECT
        f.genre,
        f.platform,
        f.genre_platform_fit_score,
        f.title_count AS platform_fit_title_count

    FROM analysis.v_phase2_genre_platform_fit f

    INNER JOIN core.strategic_platform_universe spu
        ON f.platform = spu.platform_code
       AND spu.strategic_status = 'IN_SCOPE'
),

regional_fit AS (

    SELECT
        genre,
        region,
        regional_opportunity_score

    FROM v_phase2_regional_opportunity
),

timing_fit AS (

    SELECT
        genre,
        recommended_historical_month,
        historical_timing_score,
        evidence_quality AS timing_evidence_quality,
        supporting_title_count

    FROM v_launch_timing_scenarios
),

base AS (

    SELECT
        g.genre,
        p.platform,
        r.region,
        t.recommended_historical_month,

        g.opportunity_score AS market_opportunity_score,
        g.evidence_quality AS market_evidence_quality,

        g.demand_potential_score,
        g.momentum_score,
        g.competitive_accessibility_score,

        p.genre_platform_fit_score AS platform_fit_score,

        r.regional_opportunity_score AS regional_score,

        t.historical_timing_score AS timing_score,

        p.platform_fit_title_count,

        t.supporting_title_count AS timing_title_count,

        t.timing_evidence_quality

    FROM genre_market g

    JOIN platform_fit p
        ON g.genre = p.genre

    JOIN regional_fit r
        ON g.genre = r.genre

    JOIN timing_fit t
        ON g.genre = t.genre
)

SELECT
    *,

    CASE
        WHEN market_evidence_quality = 'HIGH'
         AND platform_fit_title_count >= 20
         AND timing_title_count >= 20
            THEN 'HIGH'

        WHEN platform_fit_title_count >= 10
         AND timing_title_count >= 10
            THEN 'MEDIUM'

        ELSE 'LOW'
    END AS scenario_evidence_quality

FROM base;


-- ============================================================
-- 2. Strategic scenario score
--
-- Market opportunity       35%
-- Platform fit             25%
-- Regional opportunity     15%
-- Timing opportunity       15%
-- Evidence quality         10%
--
-- Competition is NOT added directly to this score.
-- It is treated as a separate decision-risk overlay.
-- ============================================================

CREATE OR REPLACE VIEW v_final_scenario_score AS

SELECT
    *,

    ROUND(
        (
            market_opportunity_score::numeric * 0.35

            + COALESCE(
                platform_fit_score,
                50
              )::numeric * 0.25

            + COALESCE(
                regional_score,
                50
              )::numeric * 0.15

            + COALESCE(
                timing_score,
                50
              )::numeric * 0.15

            + CASE scenario_evidence_quality
                WHEN 'HIGH'
                    THEN 100::numeric

                WHEN 'MEDIUM'
                    THEN 70::numeric

                ELSE 40::numeric
              END * 0.10

        )::numeric,
        2
    ) AS strategic_scenario_score

FROM v_final_scenario_inputs;


-- ============================================================
-- 3. Competition pressure summary
--
-- Source:
--   v_release_competition_density
--
-- Grain:
--   genre x platform
--
-- Thresholds are based on the observed historical distribution:
--
--   0-1  average comparable releases -> LOW
--   >1-7 average comparable releases -> MEDIUM
--   >7   average comparable releases -> HIGH
--
-- Competition is deliberately kept separate from the strategic
-- scenario score. It acts as a risk overlay in the final
-- launch decision.
-- ============================================================

CREATE OR REPLACE VIEW v_scenario_competition_pressure AS

SELECT
    genre,

    platform,

    ROUND(
        AVG(comparable_releases_30d)::numeric,
        2
    ) AS avg_competition_30d,

    MAX(comparable_releases_30d)
        AS max_competition_30d,

    CASE
        WHEN AVG(comparable_releases_30d) <= 1
            THEN 'LOW'

        WHEN AVG(comparable_releases_30d) <= 7
            THEN 'MEDIUM'

        ELSE 'HIGH'
    END AS competition_pressure

FROM analysis.v_release_competition_density

WHERE genre IS NOT NULL
  AND platform IS NOT NULL
  AND comparable_releases_30d IS NOT NULL

GROUP BY
    genre,
    platform;


-- ============================================================
-- 4. Final launch decision
-- ============================================================

CREATE OR REPLACE VIEW v_final_launch_decision AS

SELECT

    s.genre,
    s.platform,
    s.region,
    s.recommended_historical_month,

    ROUND(
        s.strategic_scenario_score::numeric,
        2
    ) AS strategic_scenario_score,

    m.success_probability,

    c.avg_competition_30d,
    c.max_competition_30d,
    c.competition_pressure,

    s.market_opportunity_score,
    s.platform_fit_score,
    s.regional_score,
    s.timing_score,

    s.market_evidence_quality,
    s.scenario_evidence_quality,


    -- ========================================================
    -- Decision confidence
    -- ========================================================

    CASE

        WHEN s.scenario_evidence_quality = 'LOW'
            THEN 'LOW'

        WHEN m.success_probability IS NULL
            THEN 'MEDIUM'

        WHEN s.strategic_scenario_score >= 75
         AND m.success_probability >= 0.65
         AND COALESCE(
                c.competition_pressure,
                'MEDIUM'
             ) = 'LOW'
            THEN 'HIGH'

        WHEN s.strategic_scenario_score >= 60
         AND m.success_probability >= 0.50
         AND COALESCE(
                c.competition_pressure,
                'MEDIUM'
             ) <> 'HIGH'
            THEN 'MEDIUM'

        WHEN c.competition_pressure = 'HIGH'
            THEN 'LOW'

        ELSE 'LOW'

    END AS decision_confidence,


    -- ========================================================
    -- Final decision
    --
    -- GO requires:
    --   Strategic score >= 75
    --   Model probability >= 65%
    --   Competition pressure LOW
    -- ========================================================

    CASE

        WHEN s.scenario_evidence_quality = 'LOW'
            THEN 'CONDITIONAL'

        WHEN m.success_probability IS NULL
            THEN 'CONDITIONAL'

        WHEN s.strategic_scenario_score >= 75
         AND m.success_probability >= 0.65
         AND COALESCE(
                c.competition_pressure,
                'MEDIUM'
             ) = 'LOW'
            THEN 'GO'

        WHEN s.strategic_scenario_score < 45
         AND COALESCE(
                m.success_probability,
                0
             )::numeric < 0.40
            THEN 'AVOID'

        ELSE 'CONDITIONAL'

    END AS final_decision,


    -- ========================================================
    -- Primary opportunity
    -- ========================================================

    CASE

        WHEN s.market_opportunity_score >= 75
            THEN 'Strong market opportunity'

        WHEN s.platform_fit_score >= 75
            THEN 'Strong historical platform fit'

        WHEN s.regional_score >= 75
            THEN 'Strong regional opportunity'

        WHEN s.timing_score >= 75
            THEN 'Historically attractive timing'

        ELSE 'No dominant strategic advantage'

    END AS primary_opportunity,


    -- ========================================================
    -- Primary risk
    -- ========================================================

    CASE

        WHEN s.scenario_evidence_quality = 'LOW'
            THEN 'Insufficient evidence'

        WHEN COALESCE(
                m.success_probability,
                0
             )::numeric < 0.40
            THEN 'Low predicted commercial success'

        WHEN c.competition_pressure = 'HIGH'
            THEN 'High competitive release density'

        WHEN s.market_opportunity_score < 45
            THEN 'Weak market opportunity'

        WHEN s.platform_fit_score < 45
            THEN 'Weak historical platform fit'

        WHEN s.timing_score < 45
            THEN 'Weak historical timing'

        ELSE 'Execution risk requires validation'

    END AS primary_risk,


    -- ========================================================
    -- Recommended action
    -- ========================================================

    CASE

        WHEN s.scenario_evidence_quality = 'LOW'
            THEN
                'Collect additional market evidence before committing investment'

        WHEN m.success_probability IS NULL
            THEN
                'Run the pre-launch model and validate the scenario before investment approval'

        WHEN s.strategic_scenario_score >= 75
         AND m.success_probability >= 0.65
         AND c.competition_pressure = 'HIGH'
            THEN
                'Validate launch-window differentiation and consider shifting the release window'

        WHEN s.strategic_scenario_score >= 75
         AND m.success_probability >= 0.65
         AND c.competition_pressure = 'MEDIUM'
            THEN
                'Proceed with competitive positioning and validate launch-window differentiation'

        WHEN s.strategic_scenario_score >= 75
         AND m.success_probability >= 0.65
         AND COALESCE(
                c.competition_pressure,
                'MEDIUM'
             ) = 'LOW'
            THEN
                'Proceed to commercial planning and detailed financial validation'

        WHEN s.strategic_scenario_score < 45
         AND COALESCE(
                m.success_probability,
                0
             )::numeric < 0.40
            THEN
                'Do not prioritize this scenario without a material strategic change'

        ELSE
            'Proceed only after validating the identified risk'

    END AS recommended_action


FROM v_final_scenario_score s

LEFT JOIN v_model_success_predictions m
    ON s.genre = m.genre
   AND s.platform = m.platform

LEFT JOIN v_scenario_competition_pressure c
    ON s.genre = c.genre
   AND s.platform = c.platform

ORDER BY
    final_decision,
    strategic_scenario_score DESC;


-- ============================================================
-- 5. Validation
-- ============================================================

SELECT
    final_decision,
    decision_confidence,
    COUNT(*) AS scenario_count

FROM v_final_launch_decision

GROUP BY
    final_decision,
    decision_confidence

ORDER BY
    final_decision,
    decision_confidence;


-- Strategic platform validation

SELECT DISTINCT
    platform

FROM analysis.v_phase2_genre_platform_fit

ORDER BY platform;


SELECT DISTINCT
    platform

FROM analysis.v_final_scenario_score

ORDER BY platform;


SELECT DISTINCT
    platform

FROM analysis.v_final_launch_decision

ORDER BY platform;


-- Competition pressure validation

SELECT
    competition_pressure,
    COUNT(*) AS scenario_count

FROM v_scenario_competition_pressure

GROUP BY competition_pressure

ORDER BY competition_pressure;


-- Final decision distribution by platform

SELECT
    platform,
    final_decision,
    COUNT(*) AS scenario_count

FROM v_final_launch_decision

GROUP BY
    platform,
    final_decision

ORDER BY
    platform,
    final_decision;

-- ============================================================
-- 6. Final Checks
-- ============================================================

SELECT *
FROM analysis.v_model_success_predictions
LIMIT 20;

SELECT
    COUNT(*) AS prediction_rows,
    COUNT(success_probability) AS rows_with_probability,
    COUNT(*) FILTER (
        WHERE success_probability IS NULL
    ) AS rows_without_probability
FROM analysis.v_model_success_predictions;

