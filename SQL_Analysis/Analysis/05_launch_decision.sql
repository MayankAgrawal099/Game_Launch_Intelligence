-- ============================================================
-- 05_launch_decision.sql
-- Gaming Launch Intelligence
-- Phase 2: Evidence-aware Market Decision Framework
-- ============================================================
--
-- Opportunity Score is NOT the probability that a specific game
-- will succeed. It measures market attractiveness.
--
-- Phase 5 will combine this with the pre-launch success model.
-- ============================================================

DROP VIEW IF EXISTS analysis.v_phase2_launch_decision CASCADE;
DROP VIEW IF EXISTS analysis.v_phase2_opportunity_ranked CASCADE;

-- ------------------------------------------------------------
-- 1. Relative opportunity ranking
--
-- Top 20%       -> GO
-- Next 50%      -> CONDITIONAL
-- Bottom 30%    -> AVOID
--
-- This is a preliminary market-level decision only.
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_opportunity_ranked AS
WITH ranked AS (
    SELECT
        *,
        CUME_DIST() OVER (ORDER BY opportunity_score DESC) AS rank_from_top,
        PERCENT_RANK() OVER (ORDER BY opportunity_score) AS score_percentile
    FROM analysis.v_phase2_market_opportunity
)
SELECT
    *,
    ROUND((score_percentile * 100)::numeric, 2) AS opportunity_rank_percentile,
    CASE
        WHEN rank_from_top <= 0.20 THEN 'GO'
        WHEN rank_from_top <= 0.70 THEN 'CONDITIONAL'
        ELSE 'AVOID'
    END AS preliminary_decision
FROM ranked;

-- ------------------------------------------------------------
-- 2. Decision card
-- ------------------------------------------------------------
CREATE VIEW analysis.v_phase2_launch_decision AS
SELECT
    genre,
    ROUND(opportunity_score::numeric, 2) AS opportunity_score,
    opportunity_rank_percentile,
    demand_potential_score,
    momentum_score,
    momentum_direction,
    competitive_accessibility_score,
    best_platform_fit_score,
    best_historical_platform,
    best_regional_score,
    best_historical_region,
    title_count,
    evidence_quality_final AS evidence_quality,
    preliminary_decision AS decision,
    CASE
        WHEN demand_potential_score >= 75
             AND competitive_accessibility_score >= 75
            THEN 'Strong demand with relatively accessible competition'
        WHEN demand_potential_score >= 75
            THEN 'Strong historical commercial demand'
        WHEN competitive_accessibility_score >= 75
            THEN 'Relatively accessible competitive environment'
        WHEN momentum_score >= 75
            THEN 'Positive historical market momentum'
        ELSE 'No single dominant opportunity signal'
    END AS primary_opportunity,
    CASE
        WHEN demand_potential_score < 40
            THEN 'Weak historical demand'
        WHEN competitive_accessibility_score < 40
            THEN 'High publisher concentration or entrant risk'
        WHEN momentum_score < 40
            THEN 'Negative historical momentum'
        WHEN best_platform_fit_score < 40
            THEN 'Weak historical genre-platform fit'
        WHEN best_regional_score < 40
            THEN 'Weak regional opportunity'
        ELSE 'No dominant risk identified'
    END AS primary_risk,
    CASE
        WHEN evidence_quality_final = 'LOW'
            THEN 'Insufficient evidence for a high-confidence market decision'
        WHEN preliminary_decision = 'GO'
            THEN 'Proceed to game-specific commercial validation'
        WHEN preliminary_decision = 'CONDITIONAL'
            THEN 'Proceed only after validating game-specific risks'
        ELSE 'Do not prioritize without a material strategic change'
    END AS recommendation
FROM analysis.v_phase2_opportunity_ranked;

SELECT *
FROM analysis.v_phase2_launch_decision
ORDER BY opportunity_score DESC;
