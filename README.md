# Advanced Databases Workshop

Reveal.js slides for a 1-hour workshop on advanced databases for precision livestock research, with an emphasis on GPS and accelerometer wearables.

## Live slides

After GitHub Pages is enabled, the published deck should be available at:

- [https://YOUR_GITHUB_USERNAME.github.io/Advanced-Databases/](https://YOUR_GITHUB_USERNAME.github.io/Advanced-Databases/)

Replace `YOUR_GITHUB_USERNAME` after you push this repository to GitHub if your account or organization name differs.

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

## Publish with GitHub Pages

This repository includes a GitHub Actions workflow that renders the Quarto site and deploys it to GitHub Pages.

1. Push the repository to GitHub.
2. In the repository settings, enable GitHub Pages and set the source to `GitHub Actions`.
3. Update the live slide URL above if needed.