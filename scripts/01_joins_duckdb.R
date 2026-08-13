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
library(dplyr)

dbdir <- here::here("data", "advanced.duckdb")

con <- dbConnect(duckdb(), dbdir = dbdir)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

ensure_duckdb_connection <- function(con) {
    # Interactive reruns can leave `con` closed; recreate it when needed.
    if (inherits(con, "DBIConnection") && dbIsValid(con)) {
        return(con)
    }
    dbConnect(duckdb(), dbdir = dbdir)
}

con <- ensure_duckdb_connection(con)

required_tables <- c("animals_tbl", "gps_tbl", "weights_tbl")
missing_tables <- required_tables[!vapply(required_tables, dbExistsTable, logical(1), conn = con)]

if (length(missing_tables) > 0) {
    stop(
        paste(
            "Missing required tables in DuckDB:",
            paste(missing_tables, collapse = ", "),
            "- run scripts/00_setup_duckdb.R first."
        ),
        call. = FALSE
    )
}

# Left join of weights_tbl and animals_tbl
left_join <- dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals_tbl.treatment_group
  FROM weights_tbl AS w
  LEFT JOIN animals_tbl
    ON w.animal_id = animals_tbl.animal_id
  "
)

dplyr::glimpse(left_join)

View(left_join)

# Right join of weights_tbl and animals_tbl
right_join <- dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals_tbl.treatment_group
  FROM weights_tbl AS w
  RIGHT JOIN animals_tbl
    ON w.animal_id = animals_tbl.animal_id
  "
)

dplyr::glimpse(right_join)

# Inner join of weights_tbl and animals_tbl
inner_join <- dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals_tbl.treatment_group
  FROM weights_tbl AS w
  INNER JOIN animals_tbl
    ON w.animal_id = animals_tbl.animal_id
  "
)

dplyr::glimpse(inner_join)

# Full join of weights_tbl and animals_tbl
full_join <- dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals_tbl.treatment_group
  FROM weights_tbl AS w
  FULL JOIN animals_tbl
    ON w.animal_id = animals_tbl.animal_id
  "
)

dplyr::glimpse(full_join)

# Complex join of gps_tbl, animals_tbl, and weights_tbl using left joins

complex_join_sql <- "
  SELECT
    gps_tbl.animal_id,
    gps_tbl.ts,
    animals_tbl.treatment_group,
    gps_tbl.speed_m_s,
    w.weight_kg
  FROM gps_tbl AS gps_tbl
  LEFT JOIN animals_tbl
    ON gps_tbl.animal_id = animals_tbl.animal_id
  LEFT JOIN weights_tbl AS w
    ON gps_tbl.animal_id = w.animal_id
"

joined <- dbGetQuery(
    con,
    paste0(complex_join_sql, "\nORDER BY gps_tbl.animal_id, gps_tbl.ts")
)

print(joined)

joined_row_count <- dbGetQuery(
    con,
    paste0(
        "
        SELECT COUNT(*) AS joined_row_count
        FROM (",
        complex_join_sql,
        ") AS joined
        "
    )
)

print(joined_row_count)

# Using SQL, How many rows are in each of the source tables?

source_row_counts <- dbGetQuery(
    con,
    "
    SELECT 'animals_tbl' AS table_name, COUNT(*) AS row_count FROM animals_tbl
    UNION ALL
    SELECT 'gps_tbl' AS table_name, COUNT(*) AS row_count FROM gps_tbl
    UNION ALL
    SELECT 'weights_tbl' AS table_name, COUNT(*) AS row_count FROM weights_tbl
    ORDER BY table_name
    "
)

print(source_row_counts)

# How many rows are in the joined table that have no matching animal_id in the animals_tbl table?

rows_missing_animals_tbl <- dbGetQuery(
    con,
    paste0(
        "
        SELECT COUNT(*) AS rows_missing_animals_tbl
        FROM (",
        complex_join_sql,
        ") AS joined
        WHERE treatment_group IS NULL
        "
    )
)

print(rows_missing_animals_tbl)

# How many rows are in the joined table that have no matching animal_id in the weights_tbl table?

rows_missing_weights_tbl <- dbGetQuery(
    con,
    paste0(
        "
        SELECT COUNT(*) AS rows_missing_weights_tbl
        FROM (",
        complex_join_sql,
        ") AS joined
        WHERE weight_kg IS NULL
        "
    )
)

print(rows_missing_weights_tbl)




