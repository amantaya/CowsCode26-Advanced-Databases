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

dbdir <- here::here("data", "databases.duckdb")

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

# TODO: load into duckdb as SPATIAL tables
paddocks <- data.frame(
  paddock_name = c("North", "South"),
  wkt = c(
    "POLYGON ((0 0, 0 10, 10 10, 10 0, 0 0))",
    "POLYGON ((0 -10, 0 0, 10 0, 10 -10, 0 -10))"
  ),
  stringsAsFactors = FALSE
)

# TODO: load gps_fixes from duckdb table

dbWriteTable(con, "paddocks_raw", paddocks, overwrite = TRUE)


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
