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

install_result <- try(dbExecute(con, "INSTALL spatial"), silent = TRUE)
if (inherits(install_result, "try-error") || !dbIsValid(con)) {
  if (dbIsValid(con)) {
    dbDisconnect(con, shutdown = TRUE)
  }
  con <- dbConnect(duckdb(), dbdir = dbdir)
}
dbExecute(con, "LOAD spatial")

paddocks <- data.frame(
  paddock_name = c("North", "South"),
  wkt = c(
    "POLYGON ((-103.0 35.3, -103.0 37.0, -94.4 37.0, -94.4 35.3, -103.0 35.3))",
    "POLYGON ((-103.0 33.6, -103.0 35.3, -94.4 35.3, -94.4 33.6, -103.0 33.6))"
  ),
  stringsAsFactors = FALSE
)

if (!dbExistsTable(con, "gps_fixes")) {
  stop("Missing required table in DuckDB: gps_fixes. Run scripts/00_setup_duckdb.R first.", call. = FALSE)
}

dbWriteTable(con, "paddocks_raw", paddocks, overwrite = TRUE)

dbExecute(
  con,
  "
  CREATE OR REPLACE TABLE gps_points_raw AS
  SELECT
    animal_id,
    ts,
    lon AS longitude,
    lat AS latitude
  FROM gps_fixes
  "
)


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
