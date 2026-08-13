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

csv_dir <- here::here("data")

if (!dir.exists(csv_dir)) {
    dir.create(csv_dir, recursive = TRUE)
}

animals_csv <- file.path(csv_dir, "animals.csv")
gps_csv <- file.path(csv_dir, "gps.csv")
weights_csv <- file.path(csv_dir, "weights.csv")
accel_csv <- file.path(csv_dir, "accel.csv")

set.seed(123)

n_animals_tbl <- sample(1001:1500, 1)
n_gps_tbl <- sample(1200:6000, 1)
n_weights_tbl <- sample(1100:4000, 1)

animal_ids <- sprintf("A%04d", seq_len(n_animals_tbl))

animals_tbl <- data.frame(
    animal_id = animal_ids,
    treatment_group = sample(
        c("control", "supplement", "pasture"),
        n_animals_tbl,
        replace = TRUE,
        prob = c(0.45, 0.35, 0.20)
    ),
    stringsAsFactors = FALSE
)

gps_tbl_start <- as.POSIXct("2026-06-01 00:00:00", tz = "UTC")
gps_tbl <- data.frame(
    fix_id = seq_len(n_gps_tbl),
    animal_id = sample(animal_ids, n_gps_tbl, replace = TRUE),
    ts = format(
        gps_tbl_start + sample(0:(60 * 60 * 24 * 30 - 1), n_gps_tbl, replace = TRUE),
        "%Y-%m-%d %H:%M:%S",
        tz = "UTC"
    ),
    speed_m_s = round(runif(n_gps_tbl, min = 0.1, max = 2.8), 2),
    lat = round(runif(n_gps_tbl, min = 33.6, max = 37.0), 6),
    lon = round(runif(n_gps_tbl, min = -103.0, max = -94.4), 6),
    stringsAsFactors = FALSE
)

weights_tbl_start <- as.POSIXct("2026-05-15 00:00:00", tz = "UTC")
weights_tbl <- data.frame(
    animal_id = sample(animal_ids, n_weights_tbl, replace = TRUE),
    ts = format(weights_tbl_start + seq(0, by = 600, length.out = n_weights_tbl), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    weight_kg = round(rnorm(n_weights_tbl, mean = 540, sd = 35), 1),
    stringsAsFactors = FALSE
)

weights_tbl$weight_kg <- pmax(350, pmin(750, weights_tbl$weight_kg))

n_accel_tbl_events <- sample(950:1050, 1)
accel_tbl_start <- as.POSIXct("2026-06-01 00:00:00", tz = "UTC")

# Use exactly 5 animals and guarantee each has at least 100 accelerometer events.
accel_animals <- sample(animal_ids, 5, replace = FALSE)
base_events_per_animal <- rep(100L, length(accel_animals))
remaining_events <- n_accel_tbl_events - sum(base_events_per_animal)

extra_events <- tabulate(
    sample(seq_along(accel_animals), remaining_events, replace = TRUE),
    nbins = length(accel_animals)
)

accel_animal_id_values <- rep(accel_animals, times = base_events_per_animal + extra_events)

accel_tbl <- data.frame(
    animal_id = sample(accel_animal_id_values, n_accel_tbl_events, replace = FALSE),
    # Keep fractional seconds so primary keys do not collapse to the same second.
    ts = format(accel_tbl_start + seq(0, by = 0.1, length.out = n_accel_tbl_events), "%Y-%m-%d %H:%M:%OS3", tz = "UTC"),
    activity_count = pmax(0L, as.integer(round(rnorm(n_accel_tbl_events, mean = 140, sd = 45)))),
    stringsAsFactors = FALSE
)

write.csv(animals_tbl, animals_csv, row.names = FALSE)
write.csv(gps_tbl, gps_csv, row.names = FALSE)
write.csv(weights_tbl, weights_csv, row.names = FALSE)
write.csv(accel_tbl, accel_csv, row.names = FALSE)

con <- dbConnect(duckdb(), dbdir = dbdir)

# Recreate tables with explicit types and relational constraints.
dbExecute(con, "DROP TABLE IF EXISTS accel_tbl")
dbExecute(con, "DROP TABLE IF EXISTS weights_tbl")
dbExecute(con, "DROP TABLE IF EXISTS gps_tbl")
dbExecute(con, "DROP TABLE IF EXISTS animals_tbl")

dbExecute(
    con,
    "
    CREATE TABLE animals_tbl (
      animal_id VARCHAR PRIMARY KEY,
      treatment_group VARCHAR NOT NULL
    )
    "
)

dbExecute(
    con,
    "
    CREATE TABLE gps_tbl (
      fix_id BIGINT PRIMARY KEY,
      animal_id VARCHAR NOT NULL,
      ts TIMESTAMP NOT NULL,
      speed_m_s DOUBLE NOT NULL,
            lat DOUBLE NOT NULL,
            lon DOUBLE NOT NULL,
      CONSTRAINT fk_gps_tbl_animal
        FOREIGN KEY (animal_id)
        REFERENCES animals_tbl(animal_id)
    )
    "
)

dbExecute(
    con,
    "
    CREATE TABLE weights_tbl (
      animal_id VARCHAR NOT NULL,
      ts TIMESTAMP NOT NULL,
      weight_kg DOUBLE NOT NULL,
      PRIMARY KEY (animal_id, ts),
      CONSTRAINT fk_weights_tbl_animal
        FOREIGN KEY (animal_id)
        REFERENCES animals_tbl(animal_id)
    )
    "
)

dbExecute(
    con,
    "
    CREATE TABLE accel_tbl (
      animal_id VARCHAR NOT NULL,
      ts TIMESTAMP NOT NULL,
      activity_count INTEGER NOT NULL,
      PRIMARY KEY (animal_id, ts),
      CONSTRAINT fk_accel_tbl_animal
        FOREIGN KEY (animal_id)
        REFERENCES animals_tbl(animal_id)
    )
    "
)

animals_csv <- as.character(dbQuoteString(con, normalizePath(animals_csv, winslash = "/", mustWork = TRUE)))

gps_csv <- as.character(dbQuoteString(con, normalizePath(gps_csv, winslash = "/", mustWork = TRUE)))

weights_csv <- as.character(dbQuoteString(con, normalizePath(weights_csv, winslash = "/", mustWork = TRUE)))

accel_csv <- as.character(dbQuoteString(con, normalizePath(accel_csv, winslash = "/", mustWork = TRUE)))

dbExecute(
    con,
    paste0(
        "
        INSERT INTO animals_tbl
        SELECT
          CAST(animal_id AS VARCHAR),
          CAST(treatment_group AS VARCHAR)
        FROM read_csv(",
        animals_csv,
        ", columns = {'animal_id': 'VARCHAR', 'treatment_group': 'VARCHAR'}, header = TRUE)
        "
    )
)

dbExecute(
    con,
    paste0(
        "
        INSERT INTO accel_tbl
        SELECT
          CAST(animal_id AS VARCHAR),
                    STRPTIME(ts, '%Y-%m-%d %H:%M:%S.%f')::TIMESTAMP,
          CAST(activity_count AS INTEGER)
        FROM read_csv(",
        accel_csv,
        ", columns = {'animal_id': 'VARCHAR', 'ts': 'VARCHAR', 'activity_count': 'INTEGER'}, header = TRUE)
        "
    )
)

dbExecute(
    con,
    paste0(
        "
        INSERT INTO gps_tbl
        SELECT
          CAST(fix_id AS BIGINT),
          CAST(animal_id AS VARCHAR),
          STRPTIME(ts, '%Y-%m-%d %H:%M:%S')::TIMESTAMP,
                    CAST(speed_m_s AS DOUBLE),
                    CAST(lat AS DOUBLE),
                    CAST(lon AS DOUBLE)
        FROM read_csv(",
        gps_csv,
        ", columns = {'fix_id': 'BIGINT', 'animal_id': 'VARCHAR', 'ts': 'VARCHAR', 'speed_m_s': 'DOUBLE', 'lat': 'DOUBLE', 'lon': 'DOUBLE'}, header = TRUE)
        "
    )
)

dbExecute(
    con,
    paste0(
        "
        INSERT INTO weights_tbl
        SELECT
          CAST(animal_id AS VARCHAR),
          STRPTIME(ts, '%Y-%m-%d %H:%M:%S')::TIMESTAMP,
          CAST(weight_kg AS DOUBLE)
        FROM read_csv(",
        weights_csv,
        ", columns = {'animal_id': 'VARCHAR', 'ts': 'VARCHAR', 'weight_kg': 'DOUBLE'}, header = TRUE)
        "
    )
)

cat("Setup complete. CSV files written to:", csv_dir, "\n")

cat("DuckDB database initialized at:", dbdir, "\n")

cat("Rows generated - animals_tbl:", n_animals_tbl, "gps_tbl:", n_gps_tbl, "weights_tbl:", n_weights_tbl, "accel_tbl_events:", nrow(accel_tbl), "\n")

dbDisconnect(con, shutdown = TRUE)
