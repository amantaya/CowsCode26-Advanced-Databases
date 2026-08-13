required_packages <- c("DBI", "duckdb", "here")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_packages) > 0) {
  stop(
    paste(
      "Install required packages before running this script:",
      paste(missing_packages, collapse = ", ")
    ),
    call. = FALSE
  )
}

library(DBI)
library(duckdb)

dbdir <- here::here("data", "advanced.duckdb")

con <- dbConnect(duckdb(), dbdir = dbdir)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

ensure_duckdb_connection <- function(con) {
  # Source runs in an interactive session, so recreate stale connections on rerun.
  if (inherits(con, "DBIConnection") && dbIsValid(con)) {
    return(con)
  }

  dbConnect(duckdb(), dbdir = dbdir)
}

con <- ensure_duckdb_connection(con)

if (!dbExistsTable(con, "accel")) {
  stop(
    "Missing required table in DuckDB: accel. Run scripts/00_setup_duckdb.R first.",
    call. = FALSE
  )
}

# change to a 5 second epoch aggregation
with_gaps <- dbGetQuery(
  con,
  "
  SELECT
    animal_id,
    ts,
    activity_count,
    LAG(ts) OVER (PARTITION BY animal_id ORDER BY ts) AS previous_ts,
    epoch(ts) - epoch(LAG(ts) OVER (PARTITION BY animal_id ORDER BY ts)) AS gap_seconds
  FROM accel
  ORDER BY animal_id, ts
  "
)

week_of_data <- dbGetQuery(
  con,
  "
  SELECT
    animal_id,
    ts,
    activity_count
  FROM accel
  WHERE ts >= TIMESTAMP '2026-06-01 00:00:00'
    AND ts < TIMESTAMP '2026-06-08 00:00:00'
  ORDER BY animal_id, ts
  "
)

hourly_summary <- dbGetQuery(
  con,
  "
  SELECT
    animal_id,
    date_trunc('hour', ts) AS hour_start,
    COUNT(*) AS n_windows,
    AVG(activity_count) AS mean_activity_count,
    SUM(activity_count) AS total_activity_count
  FROM accel
  GROUP BY animal_id, hour_start
  ORDER BY animal_id, hour_start
  "
)

print(with_gaps)
print(week_of_data)
print(hourly_summary)
