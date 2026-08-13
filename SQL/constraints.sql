SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type
FROM
    information_schema.table_constraints AS tc
WHERE
    tc.table_schema = 'main'
    AND tc.table_name IN ('animals_tbl', 'gps_tbl', 'weights_tbl')
ORDER BY
    tc.table_name,
    tc.constraint_type,
    tc.constraint_name;