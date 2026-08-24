# SQL Analysis

## Purpose

The `SQL_Analysis` layer is the PostgreSQL analytical layer of the **Game Launch Intelligence** project. It takes the prepared gaming datasets through data-quality checks, modelling, market analysis, launch-timing analysis, model-output integration, strategic scenario scoring, final launch-decision logic, and CSV export.

## Folder Structure

```text
SQL_Analysis/
│
├── 01_setup_and_load.sql
├── 02_data_quality_and_cleaning.sql
├── 03_data_model.sql
├── 03a_source_architecture.sql
├── 03b_compatibility_check.sql
├── 04_market_analysis.sql
├── 05_launch_decision.sql
├── 06_launch_timing.sql
├── 06a_load_model_predictions.sql
├── 07_final_decision_engine.sql
├── 08_export_results.sql
├── run_pipeline.sql
│
└── Result/
    ├── phase2_market_opportunity.csv
    ├── phase2_competitive_accessibility.csv
    ├── phase2_genre_platform_fit.csv
    ├── phase2_regional_opportunity.csv
    ├── phase4_launch_timing_scenarios.csv
    ├── phase4_release_competition_density.csv
    ├── phase4_platform_lifecycle.csv
    ├── phase5_scenario_score.csv
    └── phase5_final_launch_decision.csv
```

## Execution Order

The numbered SQL files represent the manual execution order:

```text
01_setup_and_load.sql
        ↓
02_data_quality_and_cleaning.sql
        ↓
03_data_model.sql
        ↓
03a_source_architecture.sql
        ↓
03b_compatibility_check.sql
        ↓
04_market_analysis.sql
        ↓
05_launch_decision.sql
        ↓
06_launch_timing.sql
        ↓
06a_load_model_predictions.sql
        ↓
07_final_decision_engine.sql
        ↓
08_export_results.sql
```

`run_pipeline.sql` is the orchestration/runner script. It is **not an additional numbered analytical phase**. Use it when you want to run the pipeline through the project's runner rather than executing the numbered scripts manually.

## SQL Pipeline

### 01_setup_and_load.sql

Initial database setup and source-data loading layer. It prepares the database environment and loads the source data required by downstream analysis.

### 02_data_quality_and_cleaning.sql

Data-quality and cleaning layer. It prepares consistent analytical inputs by addressing source-data quality and cleaning requirements.

### 03_data_model.sql

Core analytical data-model layer. It establishes the database structures used by the downstream analytical views.

### 03a_source_architecture.sql

Source-architecture layer for organising the different source datasets within the PostgreSQL analytical environment.

### 03b_compatibility_check.sql

Compatibility and validation layer used before the main analytical stages.

### 04_market_analysis.sql

Phase 2 market-analysis layer. It produces the market opportunity, competitive accessibility, genre × platform fit, and regional opportunity views.

Outputs:

- `phase2_market_opportunity.csv`
- `phase2_competitive_accessibility.csv`
- `phase2_genre_platform_fit.csv`
- `phase2_regional_opportunity.csv`

### 05_launch_decision.sql

Launch-decision preparation layer used by the later timing and strategic decision stages.

### 06_launch_timing.sql

Phase 4 launch-timing and competitive-analysis layer. It produces historical launch timing, release competition density, and platform lifecycle analysis.

Outputs:

- `phase4_launch_timing_scenarios.csv`
- `phase4_release_competition_density.csv`
- `phase4_platform_lifecycle.csv`

### 06a_load_model_predictions.sql

Python → PostgreSQL model-output bridge.

The Python layer produces `model_success_predictions.csv`. This file loads those game-level predictions into PostgreSQL, aggregates them to the `genre × platform` scenario level, and exposes the result through `v_model_success_predictions`.

This step must run **before `07_final_decision_engine.sql`**, because the final decision engine joins to `v_model_success_predictions`.

### 07_final_decision_engine.sql

Phase 5 strategic decision engine.

The scenario unit is:

```text
genre × platform × region × recommended launch month
```

The strategic scenario score combines:

| Component | Weight |
|---|---:|
| Market opportunity | 35% |
| Platform fit | 25% |
| Regional opportunity | 15% |
| Timing opportunity | 15% |
| Evidence quality | 10% |

The strategic scenario score is a **decision score, not a probability**.

The final decision engine produces:

```text
v_final_scenario_inputs
v_final_scenario_score
v_final_launch_decision
```

The final decision categories are:

```text
GO
CONDITIONAL
AVOID
```

It also produces decision confidence, primary opportunity, primary risk, and recommended action.

### 08_export_results.sql

Final SQL export layer. This file should be executed **last**.

It exports the Phase 2, Phase 4, and Phase 5 analytical views into nine CSV datasets and performs final row-count verification.

The nine exports are:

```text
phase2_market_opportunity.csv
phase2_competitive_accessibility.csv
phase2_genre_platform_fit.csv
phase2_regional_opportunity.csv
phase4_launch_timing_scenarios.csv
phase4_release_competition_density.csv
phase4_platform_lifecycle.csv
phase5_scenario_score.csv
phase5_final_launch_decision.csv
```

## Analytical Views

The main decision-support views are:

```text
v_phase2_market_opportunity
v_phase2_competitive_accessibility
v_phase2_genre_platform_fit
v_phase2_regional_opportunity
v_launch_timing_scenarios
v_release_competition_density
v_platform_lifecycle
v_model_success_predictions
v_final_scenario_score
v_final_launch_decision
```

## SQL → Python → SQL → Power BI Flow

```text
PostgreSQL source/conformed data
          ↓
      SQL analysis
          ↓
     Python Analysis
          ↓
model_success_predictions.csv
          ↓
06a_load_model_predictions.sql
          ↓
v_model_success_predictions
          ↓
07_final_decision_engine.sql
          ↓
Final strategic scenario + launch decision views
          ↓
08_export_results.sql
          ↓
Nine analytical CSV exports
          ↓
Python / Power BI
```

This keeps statistical modelling in Python while keeping the final strategic decision framework transparent and queryable in PostgreSQL.

## Validation

Validation is included at important stages of the pipeline. The final export layer checks the row counts of the analytical views corresponding to the nine exported datasets.

The completed project currently contains nine validated analytical exports:

- 4 Phase 2 datasets
- 3 Phase 4 datasets
- 2 Phase 5 datasets

The final decision engine also validates decision categories and scenario/platform coverage.

## Reproduction Instructions

1. Make sure PostgreSQL is available and the project database/schemas are configured.
2. Make sure the source data required by `01_setup_and_load.sql` is available.
3. Run the numbered SQL files in the execution order documented above, or use `run_pipeline.sql` as the project runner.
4. Complete the Python analysis required to generate `model_success_predictions.csv`.
5. Run `06a_load_model_predictions.sql`.
6. Run `07_final_decision_engine.sql`.
7. Run `08_export_results.sql` last.
8. Confirm that all nine CSV exports exist in `SQL_Analysis/Result/`.
9. Use those exports for downstream Python analysis and Power BI.

## Important Assumptions and Limitations

- Historical game-sales and release data are the evidence base for the strategic analysis.
- Historical performance does not guarantee future commercial success.
- The strategic scenario score is a decision-support score, not a probability.
- Success probability and strategic opportunity are separate dimensions in the decision framework.
- Evidence quality affects the final decision logic.
- `GO`, `CONDITIONAL`, and `AVOID` are rule-based decision-support outputs, not automatic investment approvals.
- Missing model probabilities can lead to a `CONDITIONAL` decision rather than an automatic rejection.
- Final recommendations should be validated against current market conditions, financial assumptions, production constraints, and other information not represented in the historical datasets.

## Current Status

The SQL analytical layer is complete through the export stage. It contains the ordered SQL pipeline, Phase 2 market analysis, Phase 4 launch timing and competition analysis, Python-to-PostgreSQL model integration, Phase 5 strategic scenario scoring, final launch decision logic, nine CSV exports, and final validation.

The next downstream consumer of these SQL outputs is the Power BI dashboard layer.
