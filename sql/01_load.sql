-- 01_load.sql
-- Load the raw CSV exactly as published. Every column lands as text so that
-- nothing is silently converted or dropped on the way in; typing happens in 02_clean.sql.
--
-- Run from the repo root with:
--   mysql --local-infile=1 -u root -p < sql/01_load.sql

DROP DATABASE IF EXISTS world_layoffs;
CREATE DATABASE world_layoffs CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE world_layoffs;

CREATE TABLE layoffs_raw (
    company               TEXT,
    location              TEXT,
    industry              TEXT,
    total_laid_off        TEXT,
    percentage_laid_off   TEXT,
    `date`                TEXT,
    stage                 TEXT,
    country               TEXT,
    funds_raised_millions TEXT
);

LOAD DATA LOCAL INFILE 'data/layoffs.csv'
INTO TABLE layoffs_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'   -- the file uses Windows line endings
IGNORE 1 LINES;

SELECT COUNT(*) AS raw_rows FROM layoffs_raw;
