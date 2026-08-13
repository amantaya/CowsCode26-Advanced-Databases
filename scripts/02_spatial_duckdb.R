required_packages <- c("DBI", "duckdb", "here", "ggplot2", "sf")
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

# This query demonstrates how to create a new table with a geometry column using the ST_Point function.
dbExecute(
  con,
  "
  CREATE OR REPLACE TABLE gps_tbl AS
  SELECT
    animal_id,
    ts,
    lat,
    lon,
    ST_Point(lon, lat) AS geom
  FROM gps_tbl
  "
)

# This query demonstrates how to perform a spatial intersect using the ST_Within function.
# It returns all GPS fixes that fall within the defined pastures.
classified_points <- dbGetQuery(
  con,
  "
  SELECT
    gps_tbl.animal_id,
    gps_tbl.ts,
    gps_tbl.lat,
    gps_tbl.lon,
    pastures.pastures_name
  FROM gps_tbl AS gps_tbl
  JOIN pastures
    ON ST_Within(gps_tbl.geom, pastures.geom)
  ORDER BY gps_tbl.ts
  "
)

View(classified_points)

# Plotting data for ggplot2 maps.
pastures_wkt <- dbGetQuery(
  con,
  "
  SELECT
    pastures_name,
    ST_AsText(geom) AS wkt
  FROM pastures
  "
)

pastures_sf <- sf::st_as_sf(pastures_wkt, wkt = "wkt", crs = 4326)

# Map 1: pasture polygons + all GPS fixes colored by pasture class.
ggplot2::ggplot() +
  ggplot2::geom_sf(data = pastures_sf, ggplot2::aes(fill = pastures_name), alpha = 0.18, color = "grey30") +
  ggplot2::geom_point(
    data = classified_points,
    ggplot2::aes(x = lon, y = lat, color = pastures_name),
    size = 0.9,
    alpha = 0.45,
    na.rm = TRUE
  ) +
  ggplot2::coord_sf(expand = FALSE) +
  ggplot2::labs(
    title = "GPS Fixes Classified by Pasture",
    x = "Longitude",
    y = "Latitude",
    fill = "Pasture",
    color = "Pasture"
  ) +
  ggplot2::theme_minimal(base_size = 12)
