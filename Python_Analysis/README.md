# Python Analysis

## Gaming Launch Intelligence

This folder contains the Python analytical and visualisation layer of the Gaming Launch Intelligence project.

Python is used for statistical analysis, pre-launch commercial success modeling, analytical validation, visualisation, and business recommendations.

The Python layer works alongside the PostgreSQL analytical layer and prepares the outputs required for the final decision-support dashboard.

---

## 1. Purpose of the Python Layer

The Python layer is responsible for:

- Statistical analysis
- Exploratory analytical validation
- Feature engineering
- Pre-launch success modeling
- Model evaluation
- Model predictions
- Visualisation
- Business recommendation support
- Preparing decision-ready outputs for Power BI

The Python analysis is designed to answer business questions rather than simply generate charts or model metrics.

---

## 2. Required Dataset Before Running the Analysis

### `steam_cleaned_2026.csv`

Before running the Python notebooks, download the cleaned Steam 2026 dataset from its original source.

**Source:** [Steam Dataset 2026 cleaned — Kaggle](https://www.kaggle.com/datasets/stefanotriscali/steam-database-2026-fixed)

The dataset is published by Stefano Triscali and is described as a structurally corrected and enhanced Steam games dataset containing information on more than 114,000 games.

### Required file location

After downloading the dataset, place the CSV file here:

```text
Game_Launch_Intelligence/
└── Game_Data/
    └── steam_cleaned_2026.csv
```

The Python notebooks expect this exact filename and location.

> **Important:** The dataset is not included in this repository. Download it from the Kaggle source before running the Python analysis.

---

## 3. Notebook Structure

The Python analysis is organised into notebooks covering:

- Data and analytical setup
- Statistical analysis
- Visualisation and recommendations
- Supporting analytical workflows
- Final output preparation

The current visualisation notebook is:

```text
03_visualisation_and_recommendations_fixed.ipynb
```

The exact notebook filenames present in `Python_Analysis/notebooks/` should be treated as the source of truth for the current implementation.

---

## 4. Statistical Analysis Workflow

The statistical analysis establishes the evidence used to understand historical commercial performance and support downstream modeling.

The analysis focuses on relationships between variables such as:

- Genre
- Platform
- Release timing
- Regional performance
- Historical sales
- Commercial success

The purpose is to identify statistically useful patterns before building the predictive layer.

---

## 5. Pre-Launch Success Modeling

The Python model estimates the probability that a game will achieve the project's defined commercial success condition.

The model produces game-level predictions containing:

```text
title
genre
console
platform_family
release_date
release_year
total_sales
is_success
success_probability
predicted_success
decision_threshold
```

The resulting predictions are exported for loading into PostgreSQL.

The current prediction dataset contains:

```text
646 game-level predictions
```

The model probabilities currently span approximately:

```text
0.03 → 0.89
```

These predictions are not treated as guaranteed commercial outcomes.

They provide a statistical signal that is combined with the strategic scenario analysis in PostgreSQL.

---

## 6. Python → SQL Analytical Flow

The model predictions are loaded into PostgreSQL through the SQL layer.

The prediction data is aggregated to:

```text
Genre × Platform
```

before being joined with the final strategic scenarios.

The current integration produces:

```text
164 total strategic scenarios
148 scenarios with model probability
16 scenarios without model probability
```

The 16 scenarios without a matching probability are retained rather than receiving an artificial estimate.

---

## 7. Visualisation and Business Recommendations

The visualisation notebook turns the final SQL analytical outputs into decision-ready visualisations and recommendations.

The notebook is aligned with the current SQL export layer and does not depend on retired analytical exports.

The current business questions are:

1. **Which platform should we prioritise?**
2. **Which genre/platform combinations represent the strongest opportunities?**
3. **Which regions and launch windows deserve attention?**
4. **Which scenarios should management prioritise, conditionally validate, or avoid?**

The goal is to communicate analytical findings and support business interpretation rather than simply display raw data.

---

## 8. Nine SQL Datasets Consumed

The visualisation layer consumes nine validated SQL exports:

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

These files are produced in:

```text
SQL_Analysis/Result/
```

The Python visualisation layer therefore uses the validated SQL outputs as its analytical input.

---

## 9. Current Visualisation Questions

### Q1 — Which platform should we prioritise?

The analysis combines:

- Platform lifecycle
- Historical platform presence
- Strategic scenario scores
- Evidence strength

The objective is not to declare one platform universally superior, but to identify platforms with strong historical evidence and strategic relevance.

### Q2 — Which genre/platform combinations represent the strongest opportunities?

This combines genre-level opportunity with platform fit to identify strategically attractive combinations.

### Q3 — Which regions and launch windows deserve attention?

This evaluates:

- Regional opportunity
- Historical launch timing
- Supporting evidence
- Competitive context

### Q4 — Which scenarios should management prioritise, conditionally validate, or avoid?

This uses the final strategic scenario score and final launch decision output to support management prioritisation.

---

## 10. Generated Visualisations

The visualisation layer produces charts addressing the project's business questions.

Examples include:

- Platform lifecycle analysis
- Platform prioritisation
- Genre × platform opportunity
- Regional opportunity
- Launch timing opportunity
- Competition pressure
- Strategic scenario scores
- Final launch decisions

The visualisations are intended to communicate findings and support business interpretation.

---

## 11. Figure Output Structure

All generated figures are saved to exactly one location:

```text
Python_Analysis/
└── outputs/
    └── figures/
```

No additional figure or result directories should be created by the Python visualisation notebook.

The figure output provides a clean handoff to the reporting and dashboard layer.

---

## 12. Python → SQL → Python Analytical Flow

```text
Python
  │
  ├── Statistical analysis
  ├── Feature engineering
  └── Success model
        │
        ▼
Game-level predictions
        │
        ▼
PostgreSQL
        │
        ├── Strategic analysis
        ├── Scenario scoring
        └── Final launch decisions
        │
        ▼
SQL_Analysis/Result/
        │
        ▼
Python visualisation
        │
        ▼
Business recommendations
        │
        ▼
Power BI
```

This separation keeps statistical modeling, relational analytical logic, and dashboard presentation distinct.

---

## 13. Dependencies

The Python notebooks use libraries including:

```text
Python
Pandas
NumPy
Plotly
```

Additional libraries may be required by individual notebooks.

For PNG export of Plotly figures, the environment may also require:

```text
Kaleido
```

If Plotly cannot export PNG files, install or enable Kaleido in the project environment.

---

## 14. Execution Instructions

Before running the notebooks:

1. Clone or download the project.
2. Install the required Python dependencies.
3. Download `steam_cleaned_2026.csv` from the Kaggle source.
4. Place it in `Game_Data/steam_cleaned_2026.csv`.
5. Ensure the nine SQL exports exist in `SQL_Analysis/Result/`.
6. Open the notebooks in `Python_Analysis/notebooks/`.
7. Run the notebooks in their intended dependency order.
8. Confirm that model predictions are generated successfully.
9. Confirm that the visualisation notebook loads all nine SQL exports.
10. Confirm that generated figures appear only in `Python_Analysis/outputs/figures/`.

---

## 15. Validation

The current Python and SQL handoff has been validated at several levels.

### Model predictions

```text
646 game-level predictions
```

### Model-to-scenario integration

```text
164 strategic scenarios
148 with model probability
16 without model probability
```

### Final decision distribution

```text
GO            2
CONDITIONAL 157
AVOID         5
```

### Final scenario uniqueness

```text
164 total scenarios
164 unique scenarios
```

### Platform coverage

```text
PC     52
PS4    60
XONE   52
```

### SQL export validation

All nine SQL CSV exports have been validated against their PostgreSQL source views and currently match their expected row counts.

---

## 16. Important Analytical Limitations

The Python analysis should be interpreted as decision support rather than certainty.

Important limitations include:

- Historical patterns may not continue into future releases.
- Model probabilities are estimates.
- The success model depends on the features available in the historical data.
- Missing model probabilities are retained rather than imputed artificially.
- The model is intended for pre-launch scenario support, not guaranteed revenue forecasting.
- Historical sales data can contain market, platform, publisher, and era effects that may not generalise.
- Visualisations communicate analytical outputs but do not independently establish causality.
- Final launch decisions should be supplemented with financial, operational, market, and product-specific validation.

---

## 17. Relationship to Power BI

Python is not the final presentation layer.

Its role is to provide:

- Statistical evidence
- Model predictions
- Analytical visualisations
- Business recommendations
- Validated analytical outputs

These outputs are then used by the Power BI dashboard to provide an interactive decision-support experience.

The dashboard should therefore be treated as the presentation and stakeholder-consumption layer built on top of the SQL and Python analytical foundation.
