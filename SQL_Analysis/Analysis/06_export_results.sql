-- =============================================================
-- 06_export_results.sql
-- Export final analytical outputs as CSV for Power BI / Excel.
-- =============================================================

COPY (SELECT * FROM analysis.v_genre_attractiveness ORDER BY attractiveness_score DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\genre_attractiveness.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_market_trend ORDER BY trend_score DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\market_trend.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_publisher_concentration ORDER BY publisher_opportunity_score DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\publisher_concentration.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_new_entrant_performance) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\new_entrant_performance.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_platform_fit ORDER BY platform_fit_score DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\platform_fit.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_platform_lifecycle ORDER BY platform DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\platform_lifecycle.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_regional_opportunity ORDER BY genre, skew_pct DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\regional_opportunity.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_regional_correlation) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\regional_correlation.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_genre_platform_fit ORDER BY genre, rank_in_genre) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\genre_platform_fit.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_launch_simulator ORDER BY launch_score DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\launch_simulator.csv' WITH (FORMAT csv, HEADER true);
COPY (SELECT * FROM analysis.v_marketing_allocation ORDER BY genre, recommended_budget_pct DESC) TO 'C:\Users\USER\Desktop\Resume Projects\Game_Launch_Intelligence\SQL_Analysis\Result\marketing_allocation.csv' WITH (FORMAT csv, HEADER true);
