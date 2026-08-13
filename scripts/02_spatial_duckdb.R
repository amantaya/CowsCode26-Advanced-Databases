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

pastures <- data.frame(
  pastures_name = c("North", "South"),
  wkt = c(
    "POLYGON ((-103.0 35.3, -103.0 37.0, -94.4 37.0, -94.4 35.3, -103.0 35.3))",
    "POLYGON ((-103.0 33.6, -103.0 35.3, -94.4 35.3, -94.4 33.6, -103.0 33.6))"
  ),
  stringsAsFactors = FALSE
)

if (!dbExistsTable(con, "gps_tbl")) {
  stop("Missing required table in DuckDB: gps_tbl. Run scripts/00_setup_duckdb.R first.", call. = FALSE)
}

dbWriteTable(con, "pastures", pastures, overwrite = TRUE)


dbExecute(
  con,
  "
  CREATE OR REPLACE TABLE pastures AS
  SELECT
    pastures_name,
    ST_GeomFromText(wkt) AS geom
  FROM pastures
  "
)

dbExecute(
  con,
  "
  CREATE OR REPLACE TABLE gps_tbl_points AS
  SELECT
    animal_id,
    ts,
    ST_Point(longitude, latitude) AS geom
  FROM gps_tbl
  "
)

classified_points <- dbGetQuery(
  con,
  "
  SELECT
    gps_tbl.animal_id,
    gps_tbl.ts,
    pastures.pastures_name
  FROM gps_tbl_points AS gps_tbl
  JOIN pastures
    ON ST_Within(gps_tbl.geom, pastures.geom)
  ORDER BY gps_tbl.ts
  "
)

fix_counts <- dbGetQuery(
  con,
  "
  SELECT
    pastures.pastures_name,
    COUNT(*) AS fixes_in_pastures
  FROM gps_tbl_points AS gps_tbl
  JOIN pastures
    ON ST_Within(gps_tbl.geom, pastures.geom)
  GROUP BY pastures.pastures_name
  ORDER BY pastures.pastures_name
  "
)

print(classified_points)
print(fix_counts)
