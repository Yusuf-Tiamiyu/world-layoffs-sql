-- 03_quality_checks.sql
-- Checks that should all return 0 failures before any analysis is trusted.
-- Each row is one rule; "failures" is the number of rows breaking it.

USE world_layoffs;

SELECT 'Exact duplicate rows'                       AS rule_checked, COUNT(*) AS failures
FROM (SELECT ROW_NUMBER() OVER (PARTITION BY company, location, industry, total_laid_off,
             percentage_laid_off, event_date, stage, country, funds_raised_millions) AS rn
      FROM layoffs_clean) d
WHERE rn > 1
UNION ALL
SELECT 'Unparseable or missing dates',               COUNT(*) FROM layoffs_clean WHERE event_date IS NULL
UNION ALL
SELECT 'Dates outside the published range',          COUNT(*) FROM layoffs_clean
WHERE event_date NOT BETWEEN '2020-03-01' AND '2023-03-31'
UNION ALL
SELECT 'Percentage outside 0-1',                     COUNT(*) FROM layoffs_clean
WHERE percentage_laid_off NOT BETWEEN 0 AND 1
UNION ALL
SELECT 'Non-positive layoff counts',                 COUNT(*) FROM layoffs_clean WHERE total_laid_off <= 0
UNION ALL
SELECT 'Countries ending in a full stop',            COUNT(*) FROM layoffs_clean WHERE country LIKE '%.'
UNION ALL
SELECT 'Untrimmed company names',                    COUNT(*) FROM layoffs_clean WHERE company <> TRIM(company)
UNION ALL
SELECT 'Industry still missing (no source to fill)', COUNT(*) FROM layoffs_clean WHERE industry IS NULL;

-- Two rules are expected to show 1, and both are known gaps in the source, left as-is:
--   * Missing dates: Blackbaud's row has no date in the published file.
--   * Missing industry: Bally's Interactive has no other row to borrow an industry from.
-- Guessing either value would make the data look cleaner than it is.
