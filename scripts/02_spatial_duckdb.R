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

install_result <- try(dbExecute(con, "INSTALL spatial"), silent = TRUE)
if (inherits(install_result, "try-error") || !dbIsValid(con)) {
  if (dbIsValid(con)) {
    dbDisconnect(con, shutdown = TRUE)
  }
  con <- dbConnect(duckdb(), dbdir = ":memory:")
}
dbExecute(con, "LOAD spatial")

paddocks <- data.frame(
  paddock_name = c("North", "South"),
  wkt = c(
    "POLYGON ((0 0, 0 10, 10 10, 10 0, 0 0))",
    "POLYGON ((0 -10, 0 0, 10 0, 10 -10, 0 -10))"
  ),
  stringsAsFactors = FALSE
)

gps_points <- data.frame(
  animal_id = c("A01", "A01", "A02", "A03"),
  ts = as.POSIXct(
    c(
      "2026-06-01 06:00:00",
      "2026-06-01 06:05:00",
      "2026-06-01 06:10:00",
      "2026-06-01 06:15:00"
    ),
    tz = "UTC"
  ),
  longitude = c(2, 4, 7, 8),
  latitude = c(2, -4, 3, -6)
)

dbWriteTable(con, "paddocks_raw", paddocks, overwrite = TRUE)
dbWriteTable(con, "gps_points_raw", gps_points, overwrite = TRUE)

dbExecute(
  con,
  "
  CREATE OR REPLACE TABLE paddocks AS
  SELECT
    paddock_name,
    ST_GeomFromText(wkt) AS geom
  FROM paddocks_raw
  "
)

dbExecute(
  con,
  "
  CREATE OR REPLACE TABLE gps_points AS
  SELECT
    animal_id,
    ts,
    ST_Point(longitude, latitude) AS geom
  FROM gps_points_raw
  "
)

classified_points <- dbGetQuery(
  con,
  "
  SELECT
    gps.animal_id,
    gps.ts,
    paddocks.paddock_name
  FROM gps_points AS gps
  JOIN paddocks
    ON ST_Within(gps.geom, paddocks.geom)
  ORDER BY gps.ts
  "
)

fix_counts <- dbGetQuery(
  con,
  "
  SELECT
    paddocks.paddock_name,
    COUNT(*) AS fixes_in_paddock
  FROM gps_points AS gps
  JOIN paddocks
    ON ST_Within(gps.geom, paddocks.geom)
  GROUP BY paddocks.paddock_name
  ORDER BY paddocks.paddock_name
  "
)

print(classified_points)
print(fix_counts)
