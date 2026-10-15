-- 02_clean.sql
-- Turns layoffs_raw into layoffs_clean: one typed row per layoff event.
-- The raw table is never modified. Every step writes how many rows it touched
-- to cleaning_log, so the cleaning can be audited after the fact.

USE world_layoffs;

DROP TABLE IF EXISTS cleaning_log;
CREATE TABLE cleaning_log (
    step_no       INT AUTO_INCREMENT PRIMARY KEY,
    step          VARCHAR(120),
    rows_affected INT
);

-- ---------------------------------------------------------------------------
-- 1. Typed working table, exact duplicates removed on the way in.
--    Company names are trimmed first so " Included Health" and "Included Health"
--    are compared as the same value. A row is a duplicate only if every column matches.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS layoffs_clean;
CREATE TABLE layoffs_clean (
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    company               VARCHAR(100),
    location              VARCHAR(100),
    industry              VARCHAR(50),
    total_laid_off        INT,
    percentage_laid_off   DECIMAL(5,4),
    event_date            DATE,
    stage                 VARCHAR(30),
    country               VARCHAR(60),
    funds_raised_millions DECIMAL(12,2)
);

INSERT INTO layoffs_clean (company, location, industry, total_laid_off, percentage_laid_off,
                           event_date, stage, country, funds_raised_millions)
SELECT company, location, industry, total_laid_off, percentage_laid_off,
       STR_TO_DATE(`date`, '%m/%d/%Y'), stage, country, funds_raised_millions
FROM (
    SELECT TRIM(r.company) AS company, r.location, r.industry, r.total_laid_off,
           r.percentage_laid_off, r.`date`, r.stage, r.country, r.funds_raised_millions,
           ROW_NUMBER() OVER (
               PARTITION BY TRIM(r.company), r.location, industry, total_laid_off, percentage_laid_off,
                            `date`, stage, country, funds_raised_millions
               ORDER BY r.company) AS rn
    FROM layoffs_raw r
) d
WHERE rn = 1;

INSERT INTO cleaning_log (step, rows_affected)
SELECT 'Company names with stray spaces (trimmed on load)', COUNT(*) FROM layoffs_raw WHERE company <> TRIM(company);

INSERT INTO cleaning_log (step, rows_affected)
SELECT 'Exact duplicate rows removed', (SELECT COUNT(*) FROM layoffs_raw) - (SELECT COUNT(*) FROM layoffs_clean);

-- ---------------------------------------------------------------------------
-- 2. Text standardisation
-- ---------------------------------------------------------------------------
UPDATE layoffs_clean SET industry = NULL WHERE industry = '';
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Blank industry set to NULL', ROW_COUNT());

-- "Crypto", "CryptoCurrency" and "Crypto Currency" are the same category
UPDATE layoffs_clean SET industry = 'Crypto' WHERE industry LIKE 'Crypto%' AND industry <> 'Crypto';
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Crypto spellings merged', ROW_COUNT());

-- "Fin-Tech" appears 3 times against 280+ "Finance" rows; the source uses Finance for fintech firms
UPDATE layoffs_clean SET industry = 'Finance' WHERE industry = 'Fin-Tech';
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Fin-Tech merged into Finance', ROW_COUNT());

UPDATE layoffs_clean SET country = TRIM(TRAILING '.' FROM country) WHERE country LIKE '%.';
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Trailing full stop removed from country', ROW_COUNT());

UPDATE layoffs_clean SET stage = 'Unknown' WHERE stage IS NULL;
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Missing stage set to Unknown', ROW_COUNT());

-- Spelling variants that differ only by case or accents ("ByteDance" / "Bytedance",
-- "Malmo" / "Malmö"). The default collation already groups them together, but the
-- stored text should be consistent, so each group takes its most common spelling.
WITH forms AS (
    SELECT company COLLATE utf8mb4_bin AS form, COUNT(*) AS n
    FROM layoffs_clean GROUP BY company COLLATE utf8mb4_bin
), ranked AS (
    SELECT form, ROW_NUMBER() OVER (PARTITION BY form COLLATE utf8mb4_0900_ai_ci ORDER BY n DESC, form) AS rn
    FROM forms
)
UPDATE layoffs_clean c
JOIN ranked k ON k.rn = 1 AND c.company = k.form COLLATE utf8mb4_0900_ai_ci
SET c.company = k.form
WHERE c.company COLLATE utf8mb4_bin <> k.form;
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Company case variants unified', ROW_COUNT());

-- Locations: prefer the accented spelling (Düsseldorf, Malmö), which is the correct name
WITH forms AS (
    SELECT location COLLATE utf8mb4_bin AS form, COUNT(*) AS n
    FROM layoffs_clean GROUP BY location COLLATE utf8mb4_bin
), ranked AS (
    SELECT form, ROW_NUMBER() OVER (PARTITION BY form COLLATE utf8mb4_0900_ai_ci
                                    ORDER BY form REGEXP '[^ -~]' DESC, n DESC, form) AS rn
    FROM forms
)
UPDATE layoffs_clean c
JOIN ranked k ON k.rn = 1 AND c.location = k.form COLLATE utf8mb4_0900_ai_ci
SET c.location = k.form
WHERE c.location COLLATE utf8mb4_bin <> k.form;
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Location accent variants unified', ROW_COUNT());

-- ---------------------------------------------------------------------------
-- 3. Fill missing industry from another row of the SAME company in the SAME location.
--    Matching on name alone is unsafe: e.g. "Bolt" is three different companies
--    (US, Estonia and others) with different industries.
-- ---------------------------------------------------------------------------
UPDATE layoffs_clean t1
JOIN layoffs_clean t2
  ON t1.company = t2.company
 AND t1.location = t2.location
 AND t2.industry IS NOT NULL
SET t1.industry = t2.industry
WHERE t1.industry IS NULL;
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Industry filled from same company + location', ROW_COUNT());

-- ---------------------------------------------------------------------------
-- 4. Flag rows that cannot support headcount analysis instead of deleting them.
--    A row with no layoff count and no percentage still records that a layoff
--    happened, so it stays in event counts but is excluded from headcount totals.
-- ---------------------------------------------------------------------------
ALTER TABLE layoffs_clean ADD COLUMN has_headcount TINYINT(1) NOT NULL DEFAULT 1;
UPDATE layoffs_clean SET has_headcount = 0
WHERE total_laid_off IS NULL AND percentage_laid_off IS NULL;
INSERT INTO cleaning_log (step, rows_affected) VALUES ('Flagged: no headcount or percentage (kept, excluded from totals)', ROW_COUNT());

-- Estimated workforce before the layoff, where both the count and the share are known.
-- e.g. 500 people at 5% implies roughly 10,000 staff.
ALTER TABLE layoffs_clean ADD COLUMN est_headcount_before INT
    AS (CASE WHEN total_laid_off IS NOT NULL AND percentage_laid_off > 0
             THEN ROUND(total_laid_off / percentage_laid_off) END) STORED;

SELECT * FROM cleaning_log ORDER BY step_no;
SELECT COUNT(*) AS clean_rows, SUM(has_headcount) AS rows_with_headcount FROM layoffs_clean;
