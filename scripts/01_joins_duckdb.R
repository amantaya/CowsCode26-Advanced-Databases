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
library(ggplot2)

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

View(full_join)

# Summary bar chart: count of rows by match_status, per join type
# This is the key visual for the audience -- it makes literal what
# LEFT vs FULL JOIN keep or drop.
match_status_summary <- dplyr::bind_rows(
  dplyr::mutate(dplyr::count(left_join, match_status), join_type = "LEFT"),
  dplyr::mutate(dplyr::count(full_join, match_status), join_type = "FULL")
) |>
  dplyr::mutate(
    join_type = factor(join_type, levels = c("LEFT", "FULL")),
    match_status = factor(
      match_status,
      levels = c("matched", "left_only", "right_only")
    )
  )


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

# NOTES:
# left_only never appears — weights_tbl has no animal_id missing from animals_tbl, so LEFT is all matched
# FULL adds a small right_only bar (animals in animals_tbl with no weight record)
