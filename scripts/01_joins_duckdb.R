required_packages <- c("DBI", "duckdb")
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

con <- dbConnect(duckdb(), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

ensure_duckdb_connection <- function(con) {
    # Interactive reruns can leave `con` closed; recreate it when needed.
    if (inherits(con, "DBIConnection") && dbIsValid(con)) {
        return(con)
    }
    dbConnect(duckdb(), dbdir = ":memory:")
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

con <- ensure_duckdb_connection(con)
dbWriteTable(con, "animals", animals, overwrite = TRUE)
dbWriteTable(con, "gps_fixes", gps_fixes, overwrite = TRUE)

joined <- dbGetQuery(
    con,
    "
  SELECT
    gps.animal_id,
    gps.ts,
    animals.treatment_group,
    gps.speed_m_s
  FROM gps_fixes AS gps
  LEFT JOIN animals
    ON gps.animal_id = animals.animal_id
  ORDER BY gps.animal_id, gps.ts
  "
)

summary_by_group <- dbGetQuery(
    con,
    "
  SELECT
    animals.treatment_group,
    COUNT(*) AS n_fixes,
    AVG(gps.speed_m_s) AS mean_speed_m_s
  FROM gps_fixes AS gps
  INNER JOIN animals
    ON gps.animal_id = animals.animal_id
  GROUP BY animals.treatment_group
  ORDER BY animals.treatment_group
  "
)

print(joined)
print(summary_by_group)
