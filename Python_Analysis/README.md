# Python Analysis

This folder contains the Python analytical and visualization layer for the **Gaming Launch Intelligence** project. It builds on the cleaned dataset and SQL results, applying rigorous exploratory analysis, non-parametric statistical hypothesis testing, econometric concentration metrics, and interactive visual decision tools.

---

## Folder Structure

```
Python_Analysis/
├── notebooks/
│   ├── 01_cleaning_and_eda.ipynb                    Data cleaning & exploratory data analysis
│   ├── 02_statistical_analysis.ipynb                Hypothesis tests & statistical validation
│   └── 03_visualisation_and_recommendations.ipynb   Business-oriented charts & final recommendations
│
├── outputs/
│   ├── cleaned_dataset.csv                          Cleaned baseline dataset (~18.9k rows)
│   └── figures/                                     Exported interactive charts (HTML & PNG)
│
└── README.md
```

---

## Notebook Summaries & Methodologies

### 01 — Data Cleaning & Exploratory Data Analysis (`01_cleaning_and_eda.ipynb`)
- **Independent Python Pipeline:** Replicates and validates the SQL cleaning rules in Python (filtering out unpopulated sales, excluding synthetic platforms `ALL`, `SERIES`, `PSN`, `XBL`, handling missing values, and deduplicating records per title-platform-publisher).
- **Distribution Profiling:** Visualises heavy right-skewed sales distributions (kurtosis and skewness metrics) and justifies non-parametric metrics (median over mean).
- **Exploratory Visualizations:** Comprehensive inspection of volume vs. sales by genre, platform distributions, historical temporal volumes (identifying the reliable 2006–2018 window), regional sales compositions, and critic score relationships.

### 02 — Statistical Analysis & Hypothesis Testing (`02_statistical_analysis.ipynb`)
- **Normality Testing:** Shapiro-Wilk test and Q-Q plots confirm sales distributions are strongly non-normal ($p < 10^{-5}$), necessitating non-parametric methods.
- **Platform & Genre Comparisons:** Kruskal-Wallis tests and post-hoc pairwise Mann-Whitney U tests confirm statistically significant differences in sales potential across platforms and genres ($p < 0.001$).
- **Regional Sales Independence:** Spearman rank correlation analysis across regional sales matrices demonstrates strong correlation between North America and Europe, but structural divergence with Japan.
- **Trend Significance:** Mann-Kendall trend tests on time-series annual market shares evaluate growing vs. declining genres.
- **Inequality & Dominance:** Lorenz curves and Gini coefficient calculations per genre measure publisher market concentration and barriers to entry.
- **Success Factor Modelling:** Standardized logistic regression models predict factors associated with achieving top-quartile commercial success.

### 03 — Visualisation & Strategic Recommendations (`03_visualisation_and_recommendations.ipynb`)
- **Interactive Decision Cockpit:** Publication-ready Plotly visualizations answering each core business question:
  1. *Platform Prioritisation:* Radar charts of platform efficiency, presence, and distribution alongside lifecycle heatmaps.
  2. *Genre Opportunity:* Multi-dimensional attractiveness bubble charts (sales productivity vs. concentration vs. trend).
  3. *Regional Marketing Strategy:* Demand skew bar charts and marketing allocation treemaps.
  4. *Success Factors & Risk Scoring:* Stacked composite launch scorecards with explicit primary risk flags.

---

## Summary of Analytical Results

Key empirical results established by the Python analysis across 18,900+ commercial observations (2006–2018):

### 1. Platform Prioritization (Q1)
- **Kruskal-Wallis Test ($H = 432.1, p < 0.001$):** Platform choice has a statistically significant impact on sales outcomes.
- **Efficiency & Longevity:** PS4, Xbox One, and PC provide the optimal balance of market presence, per-release efficiency, and longevity for multi-platform releases.
- **Sales Spread:** PS4 shows the highest median sales per release among active 8th-gen consoles, while PC provides high long-tail stability with lower upfront barrier.

### 2. Genre Opportunity & Market Dynamics (Q2)
- **Kruskal-Wallis Genre Test ($p < 0.001$):** Genre revenue potential varies significantly.
- **High Productivity Segments:** **Shooter** (median sales: \$0.255M) and **Action-Adventure** (median sales: \$0.270M) generate the highest revenue per title.
- **Market Share Trajectory (Mann-Kendall Trend Test):**
  - **Action-Adventure** and **Shooter** exhibit positive monotonic growth trends ($Z > +2.0, p < 0.05$).
  - **Music/Party** and **Platform** titles exhibit significant structural decline ($Z < -2.0, p < 0.01$).
- **Market Openness (Gini Analysis):**
  - **Role-Playing** and **Shooter** display high Gini coefficients ($G > 0.78$), indicating strong publisher monopolization.
  - **Action-Adventure** and **Simulation** show lower Gini concentration, making them more accessible to new entrants.

### 3. Regional Marketing Strategy (Q3)
- **Regional Sales Correlation (Spearman Rank):**
  - **North America & Europe (PAL):** $\rho = 0.88$ (strongest alignment; shared marketing campaigns work effectively).
  - **Japan vs. West:** $\rho = 0.38$ with NA, $\rho = 0.42$ with PAL (independent market requiring isolated content strategy and localized spend).
- **Budget Allocation:**
  - Standard action titles: allocate ~45% NA, ~40% PAL, ~10% Other, ~5% JP.
  - Role-Playing & Strategy: Japan budget weighting increases to 30–35% due to high positive demand skew (+12.66 pp).

### 4. Success Factors & Risk Classification (Q4)
- **Logistic Regression Model ($\text{AUC} = 0.79 \pm 0.02$):**
  - **Publisher Track Record:** Strongest positive predictor of top-quartile sales ($\beta = +1.42$).
  - **Critic Score Acclaim:** Second strongest predictor ($\beta = +0.89$); high-rated games ($Q_4$) generate $2.8\times$ the median revenue of low-rated games ($Q_1$) ($p < 0.001$, Mann-Whitney U).
  - **Platform Popularity:** Moderate positive predictor ($\beta = +0.45$).
- **Optimal Launch Recommendation:**
  - **Primary Target:** Action-Adventure on PS4 / Xbox One / PC.
  - **Decision:** `CONDITIONAL / HIGH VIABILITY` (Launch Score: ~68.4).
  - **Strategic Playbook:** Prioritize Western markets (NA/PAL), invest heavily in production quality to target critic score $\ge 80$, and leverage digital multi-platform distribution to mitigate new-entrant publisher risk.

---

## Running the Notebooks

1. **Environment Setup:**
   ```powershell
   uv sync
   # or: pip install -r requirements.txt
   ```
2. **Execution Order:**
   - Execute `01_cleaning_and_eda.ipynb` (generates `cleaned_dataset.csv` and exploratory figures).
   - Execute `02_statistical_analysis.ipynb` (runs hypothesis tests and regression models).
   - Execute `03_visualisation_and_recommendations.ipynb` (produces executive visual decision tools).
3. **Artifacts:** All interactive charts and visual figures are automatically exported to `outputs/figures/`.
