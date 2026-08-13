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

csv_dir <- here::here("data")

if (!dir.exists(csv_dir)) {
    dir.create(csv_dir, recursive = TRUE)
}

animals_csv <- file.path(csv_dir, "animals.csv")
gps_fixes_csv <- file.path(csv_dir, "gps_fixes.csv")
weights_csv <- file.path(csv_dir, "weights.csv")

set.seed(123)

n_animals <- sample(1001:1500, 1)
n_gps_fixes <- sample(1200:6000, 1)
n_weights <- sample(1100:4000, 1)

animal_ids <- sprintf("A%04d", seq_len(n_animals))

animals <- data.frame(
    animal_id = animal_ids,
    treatment_group = sample(
        c("control", "supplement", "pasture_plus"),
        n_animals,
        replace = TRUE,
        prob = c(0.45, 0.35, 0.20)
    ),
    stringsAsFactors = FALSE
)

gps_start <- as.POSIXct("2026-06-01 00:00:00", tz = "UTC")
gps_fixes <- data.frame(
    fix_id = seq_len(n_gps_fixes),
    animal_id = sample(animal_ids, n_gps_fixes, replace = TRUE),
    ts = format(
        gps_start + sample(0:(60 * 60 * 24 * 30 - 1), n_gps_fixes, replace = TRUE),
        "%Y-%m-%d %H:%M:%S",
        tz = "UTC"
    ),
    speed_m_s = round(runif(n_gps_fixes, min = 0.1, max = 2.8), 2),
    lat = round(runif(n_gps_fixes, min = 33.6, max = 37.0), 6),
    lon = round(runif(n_gps_fixes, min = -103.0, max = -94.4), 6),
    stringsAsFactors = FALSE
)

weights_start <- as.POSIXct("2026-05-15 00:00:00", tz = "UTC")
weights <- data.frame(
    animal_id = sample(animal_ids, n_weights, replace = TRUE),
    ts = format(weights_start + seq(0, by = 600, length.out = n_weights), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    weight_kg = round(rnorm(n_weights, mean = 540, sd = 35), 1),
    stringsAsFactors = FALSE
)

weights$weight_kg <- pmax(350, pmin(750, weights$weight_kg))

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
            lat DOUBLE NOT NULL,
            lon DOUBLE NOT NULL,
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
                    CAST(speed_m_s AS DOUBLE),
                    CAST(lat AS DOUBLE),
                    CAST(lon AS DOUBLE)
        FROM read_csv(",
        gps_fixes_csv_sql,
                ", columns = {'fix_id': 'BIGINT', 'animal_id': 'VARCHAR', 'ts': 'VARCHAR', 'speed_m_s': 'DOUBLE', 'lat': 'DOUBLE', 'lon': 'DOUBLE'}, header = TRUE)
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

cat("Rows generated - animals:", n_animals, "gps_fixes:", n_gps_fixes, "weights:", n_weights, "\n")
