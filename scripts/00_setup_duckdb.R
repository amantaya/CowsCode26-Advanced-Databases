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
csv_dir <- here::here("data", "csv")

if (!dir.exists(csv_dir)) {
    dir.create(csv_dir, recursive = TRUE)
}

animals_csv <- file.path(csv_dir, "animals.csv")
gps_fixes_csv <- file.path(csv_dir, "gps_fixes.csv")
weights_csv <- file.path(csv_dir, "weights.csv")

animals <- data.frame(
    animal_id = c("A01", "A02", "A03"),
    treatment_group = c("control", "supplement", "control"),
    stringsAsFactors = FALSE
)

gps_fixes <- data.frame(
    fix_id = c(1L, 2L, 3L, 4L, 5L),
    animal_id = c("A01", "A01", "A02", "A03", "A03"),
    ts = c(
        "2026-06-01 06:00:00",
        "2026-06-01 12:00:00",
        "2026-06-01 06:05:00",
        "2026-06-01 06:10:00",
        "2026-06-01 12:10:00"
    ),
    speed_m_s = c(0.8, 1.1, 0.5, 0.7, 1.4),
    stringsAsFactors = FALSE
)

weights <- data.frame(
    animal_id = c("A01", "A01", "A02", "A03"),
    ts = c(
        "2026-06-01 05:50:00",
        "2026-06-01 11:50:00",
        "2026-06-01 05:55:00",
        "2026-06-01 06:00:00"
    ),
    weight_kg = c(542.2, 543.0, 498.5, 561.8),
    stringsAsFactors = FALSE
)

write.csv(animals, animals_csv, row.names = FALSE)
write.csv(gps_fixes, gps_fixes_csv, row.names = FALSE)
write.csv(weights, weights_csv, row.names = FALSE)

con <- dbConnect(duckdb(), dbdir = dbdir)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

# Recreate tables with explicit types and relational constraints.
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

animals_csv_sql <- as.character(dbQuoteString(con, normalizePath(animals_csv, winslash = "/", mustWork = TRUE)))
gps_fixes_csv_sql <- as.character(dbQuoteString(con, normalizePath(gps_fixes_csv, winslash = "/", mustWork = TRUE)))
weights_csv_sql <- as.character(dbQuoteString(con, normalizePath(weights_csv, winslash = "/", mustWork = TRUE)))

dbExecute(
    con,
    paste0(
        "
        INSERT INTO animals
        SELECT
          CAST(animal_id AS VARCHAR),
          CAST(treatment_group AS VARCHAR)
        FROM read_csv(",
        animals_csv_sql,
        ", columns = {'animal_id': 'VARCHAR', 'treatment_group': 'VARCHAR'}, header = TRUE)
        "
    )
)

dbExecute(
    con,
    paste0(
        "
        INSERT INTO gps_fixes
        SELECT
          CAST(fix_id AS BIGINT),
          CAST(animal_id AS VARCHAR),
          STRPTIME(ts, '%Y-%m-%d %H:%M:%S')::TIMESTAMP,
          CAST(speed_m_s AS DOUBLE)
        FROM read_csv(",
        gps_fixes_csv_sql,
        ", columns = {'fix_id': 'BIGINT', 'animal_id': 'VARCHAR', 'ts': 'VARCHAR', 'speed_m_s': 'DOUBLE'}, header = TRUE)
        "
    )
)

dbExecute(
    con,
    paste0(
        "
        INSERT INTO weights
        SELECT
          CAST(animal_id AS VARCHAR),
          STRPTIME(ts, '%Y-%m-%d %H:%M:%S')::TIMESTAMP,
          CAST(weight_kg AS DOUBLE)
        FROM read_csv(",
        weights_csv_sql,
        ", columns = {'animal_id': 'VARCHAR', 'ts': 'VARCHAR', 'weight_kg': 'DOUBLE'}, header = TRUE)
        "
    )
)

cat("Setup complete. CSV files written to:", csv_dir, "\n")
cat("DuckDB database initialized at:", dbdir, "\n")
