-- =============================================================
-- 02_data_quality_and_cleaning.sql
-- Profile the raw dataset, apply cleaning rules, deduplicate,
-- and validate before promoting into the normalized model.
-- =============================================================


-- -----------------------------------------------
-- Data profiling on raw staging
-- -----------------------------------------------

SELECT COUNT(*) AS raw_rows FROM staging.vgchartz_raw;

-- Break down sales-populated vs. empty rows and excluded roll-up/storefront records
SELECT
    COUNT(*) FILTER (WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL) AS rows_with_total_sales,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(total_sales), '') IS NULL) AS rows_without_total_sales,
    COUNT(*) FILTER (
        WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
          AND UPPER(TRIM(console)) IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS')
    ) AS excluded_rollup_rows
FROM staging.vgchartz_raw;

-- Platform-level row counts and aggregate sales
SELECT
    console,
    COUNT(*) AS rows_with_sales,
    SUM(CAST(NULLIF(TRIM(total_sales), '') AS NUMERIC)) AS total_sales
FROM staging.vgchartz_raw
WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
GROUP BY console
ORDER BY rows_with_sales DESC;

-- Distinct genre / publisher / platform cardinalities (excluding roll-ups)
SELECT
    COUNT(DISTINCT NULLIF(LOWER(TRIM(genre)), '')) AS genres,
    COUNT(DISTINCT NULLIF(LOWER(TRIM(publisher)), '')) AS publishers,
    COUNT(DISTINCT NULLIF(LOWER(TRIM(console)), '')) AS platforms
FROM staging.vgchartz_raw
WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
  AND UPPER(TRIM(console)) NOT IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS');

-- Release-year distribution to expose sparse tail years
SELECT
    EXTRACT(YEAR FROM TO_DATE(NULLIF(TRIM(release_date), ''), 'DD-MM-YYYY'))::INT AS release_year,
    COUNT(*) AS rows_with_sales
FROM staging.vgchartz_raw
WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
  AND UPPER(TRIM(console)) NOT IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS')
GROUP BY 1
ORDER BY 1;

-- Duplicate business-key groups (title + console + publisher + release_date)
SELECT
    COUNT(*) AS duplicate_groups,
    SUM(group_count - 1) AS duplicate_extra_rows
FROM (
    SELECT
        LOWER(TRIM(title)) AS title,
        LOWER(TRIM(console)) AS console,
        LOWER(TRIM(publisher)) AS publisher,
        TO_DATE(NULLIF(TRIM(release_date), ''), 'DD-MM-YYYY') AS release_date,
        COUNT(*) AS group_count
    FROM staging.vgchartz_raw
    WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
      AND UPPER(TRIM(console)) NOT IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS')
    GROUP BY 1,2,3,4
    HAVING COUNT(*) > 1
) d;

-- Missing-value counts for core fields
SELECT
    SUM(CASE WHEN NULLIF(TRIM(title),'') IS NULL THEN 1 ELSE 0 END) AS null_title,
    SUM(CASE WHEN NULLIF(TRIM(console),'') IS NULL THEN 1 ELSE 0 END) AS null_console,
    SUM(CASE WHEN NULLIF(TRIM(genre),'') IS NULL THEN 1 ELSE 0 END) AS null_genre,
    SUM(CASE WHEN NULLIF(TRIM(publisher),'') IS NULL THEN 1 ELSE 0 END) AS null_publisher,
    SUM(CASE WHEN NULLIF(TRIM(developer),'') IS NULL THEN 1 ELSE 0 END) AS null_developer,
    SUM(CASE WHEN NULLIF(TRIM(critic_score),'') IS NULL THEN 1 ELSE 0 END) AS null_critic_score,
    SUM(CASE WHEN NULLIF(TRIM(release_date),'') IS NULL THEN 1 ELSE 0 END) AS null_release_date
FROM staging.vgchartz_raw
WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
  AND UPPER(TRIM(console)) NOT IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS');

-- Years meeting the minimum-observations threshold (analysis.parameters.min_year_rows)
SELECT
    EXTRACT(YEAR FROM TO_DATE(NULLIF(TRIM(release_date), ''), 'DD-MM-YYYY'))::INT AS year,
    COUNT(*) AS row_count
FROM staging.vgchartz_raw
WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
  AND UPPER(TRIM(console)) NOT IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS')
GROUP BY 1
HAVING COUNT(*) >= (SELECT min_year_rows FROM analysis.parameters)
ORDER BY year;


-- -----------------------------------------------
-- Cleaning: standardize, filter, deduplicate
-- -----------------------------------------------

TRUNCATE TABLE staging.vgchartz_clean;

-- Standardize text casing, cast numerics, and retain only
-- sales-populated commercial observations (excluding roll-ups).
INSERT INTO staging.vgchartz_clean (
    source_row_id, title, console, genre, publisher, developer, critic_score,
    total_sales, na_sales, jp_sales, pal_sales, other_sales, release_date, last_update
)
SELECT
    source_row_id,
    INITCAP(TRIM(title)) AS title,
    UPPER(TRIM(console)) AS console,
    NULLIF(INITCAP(TRIM(genre)), '') AS genre,
    COALESCE(NULLIF(INITCAP(TRIM(publisher)), ''), 'Unknown') AS publisher,
    NULLIF(TRIM(developer), '') AS developer,
    NULLIF(TRIM(critic_score), '')::NUMERIC,
    NULLIF(TRIM(total_sales), '')::NUMERIC,
    NULLIF(TRIM(na_sales), '')::NUMERIC,
    NULLIF(TRIM(jp_sales), '')::NUMERIC,
    NULLIF(TRIM(pal_sales), '')::NUMERIC,
    NULLIF(TRIM(other_sales), '')::NUMERIC,
    CASE
        WHEN NULLIF(TRIM(release_date), '') IS NOT NULL
        THEN TO_DATE(TRIM(release_date), 'DD-MM-YYYY')
    END,
    CASE
        WHEN NULLIF(TRIM(last_update), '') IS NOT NULL
        THEN TO_DATE(TRIM(last_update), 'DD-MM-YYYY')
    END
FROM staging.vgchartz_raw
WHERE NULLIF(TRIM(total_sales), '') IS NOT NULL
  AND UPPER(TRIM(console)) NOT IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS')
  AND NULLIF(TRIM(title), '') IS NOT NULL
  AND NULLIF(TRIM(console), '') IS NOT NULL;

-- Remove impossible negative sales values
DELETE FROM staging.vgchartz_clean
WHERE total_sales < 0
   OR COALESCE(na_sales,0) < 0
   OR COALESCE(jp_sales,0) < 0
   OR COALESCE(pal_sales,0) < 0
   OR COALESCE(other_sales,0) < 0;

-- Deduplicate scrape records: keep the row with the highest total_sales
-- per (title, console, publisher, release_date) group.
CREATE TEMP TABLE dedup_source_rows AS
SELECT source_row_id
FROM (
    SELECT
        source_row_id,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(title), console, LOWER(publisher), release_date
            ORDER BY total_sales DESC,
                     last_update DESC NULLS LAST,
                     critic_score DESC NULLS LAST,
                     source_row_id
        ) AS rn
    FROM staging.vgchartz_clean
) x
WHERE rn > 1;

DELETE FROM staging.vgchartz_clean c
USING dedup_source_rows d
WHERE c.source_row_id = d.source_row_id;

DROP TABLE dedup_source_rows;

ANALYZE staging.vgchartz_clean;


-- -----------------------------------------------
-- Post-cleaning validation
-- -----------------------------------------------

SELECT COUNT(*) AS clean_rows FROM staging.vgchartz_clean;

-- All required fields must be non-null with non-negative sales
SELECT
    COUNT(*) FILTER (WHERE total_sales IS NULL) AS null_total_sales,
    COUNT(*) FILTER (WHERE title IS NULL) AS null_title,
    COUNT(*) FILTER (WHERE console IS NULL) AS null_console,
    COUNT(*) FILTER (WHERE publisher IS NULL) AS null_publisher,
    COUNT(*) FILTER (WHERE total_sales < 0) AS negative_total_sales
FROM staging.vgchartz_clean;

-- Confirm no roll-up/storefront records survived
SELECT COUNT(*) AS excluded_rollup_rows_remaining
FROM staging.vgchartz_clean
WHERE console IN ('ALL','SERIES','XBL','PSN','DSIW','VC','MS');

-- Regional sales reconciliation check (0.02M tolerance)
SELECT COUNT(*) AS sales_reconciliation_mismatches
FROM staging.vgchartz_clean
WHERE na_sales IS NOT NULL
  AND jp_sales IS NOT NULL
  AND pal_sales IS NOT NULL
  AND other_sales IS NOT NULL
  AND ABS((na_sales + jp_sales + pal_sales + other_sales) - total_sales) > 0.02;

-- Temporal distribution after cleaning
SELECT
    EXTRACT(YEAR FROM release_date)::INT AS year,
    COUNT(*) AS releases
FROM staging.vgchartz_clean
WHERE release_date IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Final entity cardinalities
SELECT
    COUNT(DISTINCT title) AS titles,
    COUNT(DISTINCT console) AS platforms,
    COUNT(DISTINCT genre) AS genres,
    COUNT(DISTINCT publisher) AS publishers,
    COUNT(DISTINCT developer) AS developers
FROM staging.vgchartz_clean;
