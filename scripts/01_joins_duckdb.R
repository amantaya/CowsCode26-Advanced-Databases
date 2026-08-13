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

ensure_duckdb_connection <- function(con) {
    # Interactive reruns can leave `con` closed; recreate it when needed.
    if (inherits(con, "DBIConnection") && dbIsValid(con)) {
        return(con)
    }
    dbConnect(duckdb(), dbdir = dbdir)
}

con <- ensure_duckdb_connection(con)

required_tables <- c("animals", "gps_fixes", "weights")
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

# Left join of weights and animals
dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals.treatment_group
  FROM weights AS w
  LEFT JOIN animals
    ON w.animal_id = animals.animal_id
  "
)

# Right join of weights and animals
dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals.treatment_group
  FROM weights AS w
  RIGHT JOIN animals
    ON w.animal_id = animals.animal_id
  "
)

# Inner join of weights and animals
dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals.treatment_group
  FROM weights AS w
  INNER JOIN animals
    ON w.animal_id = animals.animal_id
  "
)

# Full join of weights and animals
dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    animals.treatment_group
  FROM weights AS w
  FULL JOIN animals
    ON w.animal_id = animals.animal_id
  "
)

# Anti join of weights and animals
dbGetQuery(
    con,
    "
  SELECT
    w.animal_id,
    w.weight_kg,
    NULL AS treatment_group
  FROM weights AS w
  ANTI JOIN animals
    ON w.animal_id = animals.animal_id
  "
)


# Complex join of gps_fixes, animals, and weights using left joins

complex_join_sql <- "
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
"

joined <- dbGetQuery(
    con,
    paste0(complex_join_sql, "\nORDER BY gps.animal_id, gps.ts")
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
    SELECT 'animals' AS table_name, COUNT(*) AS row_count FROM animals
    UNION ALL
    SELECT 'gps_fixes' AS table_name, COUNT(*) AS row_count FROM gps_fixes
    UNION ALL
    SELECT 'weights' AS table_name, COUNT(*) AS row_count FROM weights
    ORDER BY table_name
    "
)

print(source_row_counts)

# How many rows are in the joined table that have no matching animal_id in the animals table?

rows_missing_animals <- dbGetQuery(
    con,
    paste0(
        "
        SELECT COUNT(*) AS rows_missing_animals
        FROM (",
        complex_join_sql,
        ") AS joined
        WHERE treatment_group IS NULL
        "
    )
)

print(rows_missing_animals)

# How many rows are in the joined table that have no matching animal_id in the weights table?

rows_missing_weights <- dbGetQuery(
    con,
    paste0(
        "
        SELECT COUNT(*) AS rows_missing_weights
        FROM (",
        complex_join_sql,
        ") AS joined
        WHERE weight_kg IS NULL
        "
    )
)

print(rows_missing_weights)




