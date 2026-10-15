-- 04_analysis.sql
-- Five questions about the 2020-2023 tech layoff wave, answered from layoffs_clean.
-- Data covers 11 Mar 2020 to 6 Mar 2023, so Q1 2023 is a partial quarter.
-- Headcount totals only use rows where total_laid_off is known (about 69% of rows);
-- event counts use every row.

USE world_layoffs;

-- ===========================================================================
-- Q1. When did layoffs peak, and was the wave easing when the data ends?
-- ===========================================================================
SELECT CONCAT(YEAR(event_date), '-Q', QUARTER(event_date)) AS quarter,
       COUNT(*)                                            AS events,
       SUM(total_laid_off)                                 AS people_laid_off,
       SUM(SUM(total_laid_off)) OVER (ORDER BY CONCAT(YEAR(event_date), '-Q', QUARTER(event_date)))
                                                           AS running_total
FROM layoffs_clean
WHERE event_date IS NOT NULL
GROUP BY quarter
ORDER BY quarter;

-- Month-level view of the second wave (Sep 2022 onwards)
SELECT DATE_FORMAT(event_date, '%Y-%m') AS month,
       COUNT(*)                         AS events,
       SUM(total_laid_off)              AS people_laid_off
FROM layoffs_clean
WHERE event_date >= '2022-09-01'
GROUP BY month
ORDER BY month;

-- ===========================================================================
-- Q2. Which industries cut the biggest share of their workforce?
--     Absolute totals favour industries with a few giant employers, so this
--     also estimates the share cut: people laid off / estimated headcount before,
--     using only rows where both the count and the percentage are reported.
--     Industries with fewer than 15 such rows are left out as too thin to compare.
-- ===========================================================================
SELECT industry,
       SUM(total_laid_off)                                         AS people_laid_off,
       COUNT(est_headcount_before)                                 AS rows_with_both_figures,
       ROUND(100 * SUM(CASE WHEN est_headcount_before IS NOT NULL THEN total_laid_off END)
                 / SUM(est_headcount_before), 1)                   AS pct_of_workforce_cut,
       RANK() OVER (ORDER BY SUM(total_laid_off) DESC)             AS rank_by_people,
       RANK() OVER (ORDER BY SUM(CASE WHEN est_headcount_before IS NOT NULL THEN total_laid_off END)
                           / SUM(est_headcount_before) DESC)       AS rank_by_share
FROM layoffs_clean
WHERE industry IS NOT NULL
GROUP BY industry
HAVING COUNT(est_headcount_before) >= 15
ORDER BY pct_of_workforce_cut DESC;

-- ===========================================================================
-- Q3. Were early-stage startups more likely to shut down completely?
--     A shutdown is a layoff of 100% of staff. The rate is calculated over
--     rows that report a percentage, so missing percentages do not count as "not shut down".
-- ===========================================================================
SELECT CASE
           WHEN stage IN ('Seed', 'Series A', 'Series B')             THEN '1. Early (Seed to Series B)'
           WHEN stage IN ('Series C', 'Series D')                     THEN '2. Growth (Series C to D)'
           WHEN stage REGEXP '^Series [E-J]$'                         THEN '3. Late private (Series E+)'
           WHEN stage = 'Post-IPO'                                    THEN '4. Public'
           WHEN stage IN ('Acquired', 'Subsidiary', 'Private Equity') THEN '5. Acquired, PE or subsidiary'
           ELSE '6. Unknown'
       END                                                             AS funding_stage,
       COUNT(*)                                                        AS events,
       SUM(percentage_laid_off IS NOT NULL)                            AS events_with_percentage,
       SUM(percentage_laid_off = 1)                                    AS full_shutdowns,
       ROUND(100 * SUM(percentage_laid_off = 1)
                 / SUM(percentage_laid_off IS NOT NULL), 1)            AS shutdown_rate_pct,
       ROUND(100 * AVG(percentage_laid_off), 1)                        AS avg_share_cut_pct
FROM layoffs_clean
GROUP BY funding_stage
ORDER BY funding_stage;

-- The best-funded companies that still shut down
SELECT company, country, stage, funds_raised_millions, event_date
FROM layoffs_clean
WHERE percentage_laid_off = 1
ORDER BY funds_raised_millions DESC
LIMIT 5;

-- ===========================================================================
-- Q4. How common were repeat layoffs, and how quickly did the second round come?
--     A company is identified by name AND country, because names repeat across
--     unrelated firms (e.g. three different "Bolt"s).
-- ===========================================================================
WITH rounds AS (
    SELECT company, country, event_date, total_laid_off,
           LAG(event_date) OVER (PARTITION BY company, country ORDER BY event_date) AS previous_round
    FROM layoffs_clean
    WHERE event_date IS NOT NULL
)
SELECT COUNT(DISTINCT company, country)                                    AS companies,
       COUNT(DISTINCT CASE WHEN previous_round IS NOT NULL
                           THEN CONCAT(company, '|', country) END)         AS companies_with_repeat_rounds,
       SUM(previous_round IS NOT NULL)                                     AS repeat_rounds,
       ROUND(AVG(DATEDIFF(event_date, previous_round)))                    AS avg_days_between_rounds,
       ROUND(100 * SUM(DATEDIFF(event_date, previous_round) <= 180)
                 / SUM(previous_round IS NOT NULL), 1)                     AS pct_within_6_months
FROM rounds;

-- Share of all people laid off who worked at companies that cut more than once
WITH per_company AS (
    SELECT company, country, COUNT(*) AS rounds, SUM(total_laid_off) AS people
    FROM layoffs_clean
    GROUP BY company, country
)
SELECT ROUND(100 * SUM(CASE WHEN rounds > 1 THEN people END) / SUM(people), 1) AS pct_from_repeat_companies
FROM per_company;

-- ===========================================================================
-- Q5. What does the data show for Nigeria and the rest of Africa?
-- ===========================================================================
SELECT country,
       COUNT(*)                    AS events,
       COUNT(DISTINCT company)     AS companies,
       SUM(total_laid_off)         AS people_laid_off_reported,
       SUM(total_laid_off IS NULL) AS events_without_a_count
FROM layoffs_clean
WHERE country IN ('Nigeria', 'Kenya', 'Ghana', 'South Africa', 'Egypt', 'Senegal', 'Seychelles')
GROUP BY country
ORDER BY events DESC;

-- Every Nigerian event, in order
SELECT event_date, company, location, industry, stage,
       total_laid_off, percentage_laid_off, funds_raised_millions
FROM layoffs_clean
WHERE country = 'Nigeria'
ORDER BY event_date;
