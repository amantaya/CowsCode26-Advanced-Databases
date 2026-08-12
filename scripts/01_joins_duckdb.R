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

dbdir <- here::here("data", "advanced-databases.duckdb")

con <- dbConnect(duckdb(), dbdir = dbdir)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

ensure_duckdb_connection <- function(con) {
    # Interactive reruns can leave `con` closed; recreate it when needed.
    if (inherits(con, "DBIConnection") && dbIsValid(con)) {
        return(con)
    }
    dbConnect(duckdb(), dbdir = dbdir)
}

animals <- data.frame(
    animal_id = c("A01", "A02", "A03"),
    treatment_group = c("control", "supplement", "control"),
    stringsAsFactors = FALSE
)

gps_fixes <- data.frame(
    animal_id = c("A01", "A01", "A02", "A03", "A03"),
    ts = as.POSIXct(
        c(
            "2026-06-01 06:00:00",
            "2026-06-01 12:00:00",
            "2026-06-01 06:05:00",
            "2026-06-01 06:10:00",
            "2026-06-01 12:10:00"
        ),
        tz = "UTC"
    ),
    speed_m_s = c(0.8, 1.1, 0.5, 0.7, 1.4)
)

  weights <- data.frame(
    animal_id = c("A01", "A01", "A02", "A03"),
    ts = as.POSIXct(
      c(
        "2026-06-01 05:50:00",
        "2026-06-01 11:50:00",
        "2026-06-01 05:55:00",
        "2026-06-01 06:00:00"
      ),
      tz = "UTC"
    ),
    weight_kg = c(542.2, 543.0, 498.5, 561.8)
  )

con <- ensure_duckdb_connection(con)

  # Recreate tables with relational constraints for ERD visualization.
  dbExecute(con, "DROP TABLE IF EXISTS weights")
  dbExecute(con, "DROP TABLE IF EXISTS gps_fixes")
  dbExecute(con, "DROP TABLE IF EXISTS animals")

  dbExecute(
    con,
    "
    CREATE TABLE animals (
      animal_id VARCHAR PRIMARY KEY,
      treatment_group VARCHAR NOT NULL
    )
    "
  )

  dbExecute(
    con,
    "
    CREATE TABLE gps_fixes (
      fix_id BIGINT PRIMARY KEY,
      animal_id VARCHAR NOT NULL,
      ts TIMESTAMP NOT NULL,
      speed_m_s DOUBLE NOT NULL,
      CONSTRAINT fk_gps_animal
        FOREIGN KEY (animal_id)
        REFERENCES animals(animal_id)
    )
    "
  )

  dbExecute(
    con,
    "
    CREATE TABLE weights (
      animal_id VARCHAR NOT NULL,
      ts TIMESTAMP NOT NULL,
      weight_kg DOUBLE NOT NULL,
      PRIMARY KEY (animal_id, ts),
      CONSTRAINT fk_weights_animal
        FOREIGN KEY (animal_id)
        REFERENCES animals(animal_id)
    )
    "
  )

  gps_fixes$fix_id <- seq_len(nrow(gps_fixes))
  gps_fixes <- gps_fixes[, c("fix_id", "animal_id", "ts", "speed_m_s")]

  dbAppendTable(con, "animals", animals)
  dbAppendTable(con, "gps_fixes", gps_fixes)
  dbAppendTable(con, "weights", weights)

joined <- dbGetQuery(
    con,
    "
  SELECT
    gps.animal_id,
    gps.ts,
    animals.treatment_group,
    gps.speed_m_s,
    w.weight_kg
  FROM gps_fixes AS gps
  LEFT JOIN animals
    ON gps.animal_id = animals.animal_id
  LEFT JOIN weights AS w
    ON gps.animal_id = w.animal_id
  ORDER BY gps.animal_id, gps.ts
  "
)

print(joined)

# Demo on viewing the Entity Relationship Diagram in DBeaver
