# SQL Analysis

This folder contains the PostgreSQL pipeline that transforms raw VGChartz sales data into the analytical outputs powering the launch decision engine. The pipeline is structured as six sequential SQL modules, each building on the previous.

---

## Folder Structure

```
SQL_Analysis/
├── Analysis/                                  SQL pipeline modules
│   ├── 01_setup_and_load.sql                  Schema, tables, and CSV ingestion
│   ├── 02_data_quality_and_cleaning.sql       Profiling, cleaning, deduplication, validation
│   ├── 03_data_model.sql                      Star schema normalisation and base views
│   ├── 04_market_analysis.sql                 Six scored analytical dimensions
│   ├── 05_launch_decision.sql                 Composite launch score and marketing allocation
│   ├── 06_export_results.sql                  CSV exports for reporting / Power BI
│   └── run_pipeline.sql                       Execution order reference
│
├── Result/                                    Exported analytical outputs
│   ├── genre_attractiveness.csv
│   ├── market_trend.csv
│   ├── publisher_concentration.csv
│   ├── new_entrant_performance.csv
│   ├── platform_fit.csv
│   ├── platform_lifecycle.csv
│   ├── regional_opportunity.csv
│   ├── regional_correlation.csv
│   ├── genre_platform_fit.csv
│   ├── launch_simulator.csv
│   └── marketing_allocation.csv
│
└── README.md
```

---

## Execution

Run each file in order via pgAdmin's query tool:

| Step | File | Notes |
|---|---|---|
| 1 | `01_setup_and_load.sql` | Use pgAdmin Import/Export for the CSV load (exclude `source_row_id`) |
| 2 | `02_data_quality_and_cleaning.sql` | Profiles and cleans raw data |
| 3 | `03_data_model.sql` | Builds star schema and base views |
| 4 | `04_market_analysis.sql` | Computes six analytical dimensions |
| 5 | `05_launch_decision.sql` | Computes composite launch scores and marketing budget allocation |
| 6 | `06_export_results.sql` | Exports 11 CSV result files to the `Result/` directory |

The pipeline is idempotent — every module drops and recreates its objects, so it can be re-executed cleanly at any time.

---

## What Each Module Does

### 01 — Setup & Load

Creates three schemas (`staging`, `core`, `analysis`), defines all tables with constraints and foreign keys, and loads the raw CSV into `staging.vgchartz_raw`. Also initialises two configuration tables:

- **`analysis.parameters`** — Tunable thresholds (analysis window 2006–2018, minimum observations, top-N cutoffs) that scope every downstream view.
- **`analysis.launch_config`** — The planned launch scenario. NULL values evaluate all genre-platform combinations; specific values filter to a single scenario.

### 02 — Data Quality & Cleaning

**Profiling:** Row counts, sales coverage, platform distribution, duplicate detection, missing-value analysis, and year-over-year observation density.

**Cleaning rules:**
- Retains only sales-populated commercial observations
- Excludes roll-up/storefront records (ALL, SERIES, XBL, PSN, etc.)
- Standardises text casing and casts numerics with null-safe handling
- Removes negative sales values
- Deduplicates scrape records per (title, console, publisher, release_date) — highest `total_sales` wins

**Validation:** Confirms zero nulls in required fields, zero negative sales, zero excluded records remaining, and regional sales reconciliation within 0.02M tolerance.

~18,900 observations are retained from the original ~64,000 rows.

### 03 — Data Model

Normalises the cleaned staging layer into a star schema:

- **Dimensions:** `publishers`, `platforms`, `games` (deduplicated at the title + publisher grain)
- **Facts:** `game_releases` (one row per game × platform × release), `sales` (regional and global)
- **Base views:** `v_game_sales` (flattened join of all entities — foundation for every analysis) and `v_market_share` (annual genre share within the analysis window)

### 04 — Market Analysis

Scores genres and platforms across six analytical dimensions, each normalised to 0–100:

| Dimension | View | What It Measures |
|---|---|---|
| Genre Attractiveness | `v_genre_attractiveness` | Per-title revenue productivity balanced against title-level concentration (HHI + top-10 share with adaptive weighting) |
| Market Trends | `v_market_trend` | OLS slope of annual market share — identifies growing vs. declining genres |
| Publisher Concentration | `v_publisher_concentration` | Publisher-level HHI and top-5 share — gauges competitive openness for a new entrant |
| New-Entrant Performance | `v_new_entrant_performance` | Benchmarks first-time publisher entries against genre-year median — measures real-world entry accessibility |
| Platform Fit | `v_platform_fit` | Composite of sales efficiency (50%), catalog presence (25%), and title-sales distribution (25%) — scoped to currently active platforms |
| Regional Opportunity | `v_regional_opportunity` | Regional demand skew — where a genre over- or under-indexes vs. its global share |

Additional supporting views:
- `v_active_platforms` — Platforms with releases in the final two years of the analysis window (2017–2018). Shared across all platform-filtered views to prevent retired hardware (PS2, PSP, DS) from surfacing in launch recommendations.
- `v_platform_lifecycle` — Platform release share over time for lifecycle and timing analysis.
- `v_regional_correlation` — Pairwise Pearson correlation matrix across the four sales regions.
- `v_genre_platform_fit` — Best platform choices within each genre, ranked by median sales per release.
- `v_genre_best_region` — Picks each genre's single strongest regional skew, then ranks that skew's magnitude against every *other* genre's best skew (cross-genre ranking).

### 05 — Launch Decision

**Launch Simulator (`v_launch_simulator`):** Combines all six dimensions into a weighted composite score for every genre-platform combination:

| Dimension | Weight | Rationale |
|---|---|---|
| Market Attractiveness | 25% | Commercial ceiling & title productivity |
| Entrant Accessibility | 20% | Historical probability of a new publisher hitting above-median sales |
| Market Trend | 15% | Genre momentum and market share trajectory |
| Publisher Opportunity | 15% | Fragmented landscape vs. incumbent monopoly |
| Platform Fit | 15% | Platform monetization efficiency and health |
| Regional Opportunity | 10% | Geographic over-indexing potential |

Decision classification:

| Score | Decision | Interpretation |
|---|---|---|
| ≥ 70 | **GO** | Strong historical signals across all dimensions |
| 55–69 | **CONDITIONAL** | Viable with mitigation — check `primary_risk` |
| < 55 | **AVOID** | Multiple adverse signals |

**Marketing Allocation (`v_marketing_allocation`):** Converts regional demand skew into a recommended budget split — 60% weighted on absolute regional demand, 40% on over-indexing signal.

### 06 — Export

Writes all analytical views to CSV in the `Result/` directory. 11 files are generated.

---

## Summary of Analytical Results

Key empirical results produced by the SQL pipeline across 18,900+ commercial observations (2006–2018):

### 1. Platform Prioritisation
- **Top Active Platforms by Fit Score:**
  - **PS4 / Xbox One / PC** represent the core target ecosystem for modern multi-platform releases.
  - Across the 7th/8th generation transition window, **X360** (95.54) and **PS3** (93.75) exhibited peak historical commercial efficiency, followed by **PS4** (72.25) as the primary 8th-gen driver.

### 2. Genre Attractiveness & Accessibility
- **Top Commercial Genres:**
  - **Shooter** (Attractiveness Score: 43.89, Median Sales: $0.255M) and **Action-Adventure** (Score: 42.78, Median Sales: $0.270M) exhibit the highest per-title commercial productivity.
- **New-Entrant Opportunity:**
  - **Visual Novel** (59.18% breakout rate) and **Action-Adventure** (53.85% breakout rate) offer the highest historical success rates for first-time publishers.
  - **Shooter** (17.28% breakout rate) and **Role-Playing** (22.43% breakout rate) impose the steepest barriers to entry due to high incumbent domination.

### 3. Launch Simulator Rankings
- **Top Recommended Scenarios:**
  - **Action-Adventure on PS4 / Xbox One / PC** (Launch Score: 64.94 – 68.44, CONDITIONAL / Strong Viability) — Driven by strong market momentum (Trend Score: 100.0), high entrant breakout rate (53.85%), and balanced publisher concentration.
  - **Strategy / Role-Playing** on core platforms show strong regional viability but carry genre-specific risks (e.g. niche audience or high incumbent control).
- **Primary Risk Flags:**
  - Shooter scenarios trigger **"High entry risk"** due to low entrant breakout rates.
  - Saturated segments trigger **"High publisher concentration"**.

### 4. Regional Skew & Marketing Allocation
- **North America (NA) & Europe (PAL)** drive over 70% of total revenue for Action, Shooter, and Sports titles.
- **Japan (JP)** exhibits extreme over-indexing for **Role-Playing (+12.66 pp skew)** and **Strategy (+3.61 pp skew)**, requiring isolated regional go-to-market strategies.
- **Regional Correlation:** NA and PAL sales are tightly correlated (r = 0.88), while JP exhibits low correlation with Western markets (r = 0.35–0.45).

---

## Output Files

| File | Grain | Key Columns |
|---|---|---|
| `genre_attractiveness.csv` | One row per genre | `attractiveness_score`, `median_sales_per_title`, `title_hhi` |
| `market_trend.csv` | One row per genre | `trend_slope`, `trend_score` |
| `publisher_concentration.csv` | One row per genre | `publisher_hhi`, `publisher_opportunity_score` |
| `new_entrant_performance.csv` | One row per entry event | `vs_median_ratio`, `entry_performance` |
| `platform_fit.csv` | One row per platform | `platform_fit_score`, `sales_per_release`, `distribution_score` |
| `platform_lifecycle.csv` | One row per platform × year | `release_count`, `release_share_pct` |
| `regional_opportunity.csv` | One row per genre × region | `skew_pct`, `regional_signal` |
| `regional_correlation.csv` | Correlation matrix | NA, JP, PAL, Other, Global pairwise correlations |
| `genre_platform_fit.csv` | One row per genre × platform | `median_sales_per_release`, `rank_in_genre` |
| `launch_simulator.csv` | One row per genre × platform | `launch_score`, `launch_decision`, `primary_risk` |
| `marketing_allocation.csv` | One row per genre × region | `recommended_budget_pct`, `allocation_index` |

---

## Configuration Reference

All thresholds are driven by `analysis.parameters`, not hard-coded in queries:

| Parameter | Default | Controls |
|---|---|---|
| `analysis_start_year` | 2006 | Start of the analysis window |
| `analysis_end_year` | 2018 | End of the analysis window |
| `min_year_rows` | 100 | Minimum observations for a year to be included |
| `top_n_titles` | 10 | Top-N titles in concentration metrics |
| `top_n_publishers` | 5 | Top-N publishers in concentration metrics |
| `min_platform_releases` | 25 | Minimum releases for a platform to be scored |
| `min_genre_platform_releases` | 20 | Minimum releases for a genre-platform pair to be scored |

---

## Technical Notes

- **Normalised scoring:** All dimension scores are min-max normalised to 0–100 for cross-dimension comparability.
- **Adaptive weighting:** Genre attractiveness uses variance-based weighting between HHI and top-10 share.
- **NULL-safe defaults:** When a dimension score is unavailable for a scenario, the launch simulator defaults to 50 (neutral).
- **Recency filter:** Uses `v_active_platforms` (2017–2018 active releases) to exclude obsolete hardware.
- **Cross-genre regional scoring:** `v_genre_best_region` ranks the single highest regional skew of each genre across all genres to ensure discriminatory signal.
- **PostgreSQL 18 compatible:** All queries use standard PostgreSQL syntax executable in pgAdmin.
