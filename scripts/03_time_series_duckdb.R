required_packages <- c("DBI", "duckdb")
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

con <- dbConnect(duckdb(), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

accel_events <- data.frame(
  animal_id = c("A01", "A01", "A01", "A02", "A02"),
  ts = as.POSIXct(
    c(
      "2026-06-01 06:00:00",
      "2026-06-01 06:05:00",
      "2026-06-01 06:30:00",
      "2026-06-01 06:02:00",
      "2026-06-01 06:07:00"
    ),
    tz = "UTC"
  ),
  activity_count = c(120, 140, 95, 180, 165)
)

dbWriteTable(con, "accel_events", accel_events, overwrite = TRUE)

with_gaps <- dbGetQuery(
  con,
  "
  SELECT
    animal_id,
    ts,
    activity_count,
    LAG(ts) OVER (PARTITION BY animal_id ORDER BY ts) AS previous_ts,
    epoch(ts) - epoch(LAG(ts) OVER (PARTITION BY animal_id ORDER BY ts)) AS gap_seconds
  FROM accel_events
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
  FROM accel_events
  GROUP BY animal_id, hour_start
  ORDER BY animal_id, hour_start
  "
)

print(with_gaps)
print(hourly_summary)