required_packages <- c("DBI", "duckdb", "here")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

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
missing_tables <- required_tables[
  !vapply(required_tables, dbExistsTable, logical(1), conn = con)
]

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
# match_status makes explicit, for teaching purposes, which side(s) each row
# came from: rows with a NULL on one side are otherwise easy to miss.
left_join <- dbGetQuery(
  con,
  "
  SELECT
    w.animal_id AS w_animal_id,
    animals_tbl.animal_id AS a_animal_id,
    w.weight_kg,
    animals_tbl.treatment_group,
    CASE
      WHEN w.animal_id IS NOT NULL AND animals_tbl.animal_id IS NOT NULL THEN 'matched'
      WHEN w.animal_id IS NOT NULL THEN 'left_only'
      ELSE 'right_only'
    END AS match_status
  FROM weights_tbl AS w
  LEFT JOIN animals_tbl
    ON w.animal_id = animals_tbl.animal_id
  "
)

View(left_join)

# Right join of weights_tbl and animals_tbl
right_join <- dbGetQuery(
  con,
  "
  SELECT
    w.animal_id AS w_animal_id,
    animals_tbl.animal_id AS a_animal_id,
    w.weight_kg,
    animals_tbl.treatment_group,
    CASE
      WHEN w.animal_id IS NOT NULL AND animals_tbl.animal_id IS NOT NULL THEN 'matched'
      WHEN animals_tbl.animal_id IS NOT NULL THEN 'right_only'
      ELSE 'left_only'
    END AS match_status
  FROM weights_tbl AS w
  RIGHT JOIN animals_tbl
    ON w.animal_id = animals_tbl.animal_id
  "
)

View(right_join)

# Inner join of weights_tbl and animals_tbl
# every row here is necessarily 'matched' -- included for symmetry/contrast
# with the other join types when presenting counts.
inner_join <- dbGetQuery(
  con,
  "
  SELECT
    w.animal_id AS w_animal_id,
    animals_tbl.animal_id AS a_animal_id,
    w.weight_kg,
    animals_tbl.treatment_group,
    'matched' AS match_status
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
    w.animal_id AS w_animal_id,
    animals_tbl.animal_id AS a_animal_id,
    w.weight_kg,
    animals_tbl.treatment_group,
    CASE
      WHEN w.animal_id IS NOT NULL AND animals_tbl.animal_id IS NOT NULL THEN 'matched'
      WHEN w.animal_id IS NOT NULL THEN 'left_only'
      ELSE 'right_only'
    END AS match_status
  FROM weights_tbl AS w
  FULL JOIN animals_tbl
    ON w.animal_id = animals_tbl.animal_id
  "
)

dplyr::glimpse(full_join)

# Summary bar chart: count of rows by match_status, per join type
# This is the key visual for the audience -- it makes literal what
# LEFT/RIGHT/INNER/FULL JOIN keep or drop.
match_status_summary <- dplyr::bind_rows(
  dplyr::mutate(dplyr::count(left_join, match_status), join_type = "LEFT"),
  dplyr::mutate(dplyr::count(right_join, match_status), join_type = "RIGHT"),
  dplyr::mutate(dplyr::count(inner_join, match_status), join_type = "INNER"),
  dplyr::mutate(dplyr::count(full_join, match_status), join_type = "FULL")
) |>
  dplyr::mutate(
    join_type = factor(join_type, levels = c("LEFT", "RIGHT", "INNER", "FULL")),
    match_status = factor(
      match_status,
      levels = c("matched", "left_only", "right_only")
    )
  )

library(ggplot2)

print(
  ggplot(match_status_summary, aes(x = join_type, y = n, fill = match_status)) +
    geom_col(position = "stack") +
    labs(
      x = "Join type",
      y = "Row count",
      fill = "Match status",
      title = "Which rows matched vs. didn't, by join type"
    )
)

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


# NOTES: 
# left_only never appears — weights_tbl has no animal_id missing from animals_tbl, so LEFT/INNER are identical (all matched)
# RIGHT/FULL show the same small right_only bar (animals in animals_tbl with no weight record)