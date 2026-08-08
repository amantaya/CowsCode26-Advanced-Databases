# Advanced Databases Workshop

Reveal.js slides for a 1-hour workshop on advanced databases for precision livestock research, with an emphasis on GPS and accelerometer wearables.

## Live slides

The slides for this workshop are available at:

- [https://amantaya.github.io/CowsCode26-Advanced-Databases/](https://amantaya.github.io/CowsCode26-Advanced-Databases/)

## Topics included

- relational joins for sensor and metadata tables
- spatial analysis with DuckDB
- time-series architecture for wearable pipelines
- practical R workflows using `DBI` with `duckdb`

## Example scripts

- `scripts/01_joins_duckdb.R`
- `scripts/02_spatial_duckdb.R`
- `scripts/03_time_series_duckdb.R`

## Local preview

```bash
quarto preview
```

## Run the R examples

Install the required R packages first:

```bash
Rscript -e "install.packages(c('DBI', 'duckdb'), repos = 'https://cloud.r-project.org')"
```

The examples use `DBI` and `duckdb`. The spatial example also uses DuckDB's spatial extension and may download it the first time it runs.

```bash
Rscript scripts/01_joins_duckdb.R
Rscript scripts/02_spatial_duckdb.R
Rscript scripts/03_time_series_duckdb.R
```
