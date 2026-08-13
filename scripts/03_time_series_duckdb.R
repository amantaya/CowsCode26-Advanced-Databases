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

if (!dbExistsTable(con, "accel_tbl")) {
  stop(
    "Missing required table in DuckDB: accel_tbl. Run scripts/00_setup_duckdb.R first.",
    call. = FALSE
  )
}

# Query that demonstrates 5 second epoch aggregation
epoch_5s <- dbGetQuery(
  con,
  "
SELECT
  animal_id,
  time_bucket(INTERVAL '5 seconds', ts) AS epoch_5s,
  COUNT(*) AS readings_in_window,
  SUM(activity_count) AS activity_sum,
  AVG(activity_count) AS activity_avg
FROM accel_tbl
GROUP BY
  animal_id,
  time_bucket(INTERVAL '5 seconds', ts)
ORDER BY
  animal_id,
  epoch_5s;
  "
)

View(epoch_5s)

# Common time series queries for the first week of data
week_of_data <- dbGetQuery(
  con,
  "
  SELECT
    animal_id,
    ts,
    activity_count
  FROM accel_tbl
  WHERE ts >= TIMESTAMP '2026-06-01 00:00:00'
    AND ts < TIMESTAMP '2026-06-08 00:00:00'
    AND animal_id = 'A1361'
  "
)

View(week_of_data)
