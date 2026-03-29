#!/usr/bin/env bash

# DMS Pre-Migration Database Assessment
# Discovers source DB structure, data types, sizes, and migration complexity

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   DMS Pre-Migration Database Assessment       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo

read -p "DB Host: " DB_HOST
read -p "DB Port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}
read -p "DB Name [postgres]: " DB_NAME
DB_NAME=${DB_NAME:-postgres}
read -p "DB Username [postgres]: " DB_USER
DB_USER=${DB_USER:-postgres}
read -s -p "DB Password: " DB_PASS
echo
echo

PSQL_CMD="/opt/homebrew/opt/libpq/bin/psql"
if [ ! -f "$PSQL_CMD" ]; then
    PSQL_CMD=$(which psql 2>/dev/null || echo "")
    if [ -z "$PSQL_CMD" ]; then
        echo -e "${RED}psql not found. Install with: brew install libpq${NC}"
        exit 1
    fi
fi

export PGPASSWORD="$DB_PASS"
PSQL="$PSQL_CMD -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -A"
PSQL_PRETTY="$PSQL_CMD -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"

# Test connection
if ! $PSQL -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}Cannot connect to database${NC}"
    exit 1
fi

REPORT_FILE="db-assessment-$(date +%Y%m%d-%H%M%S).txt"

# Tee output to both terminal and file
exec > >(tee "$REPORT_FILE") 2>&1

echo "═══════════════════════════════════════════════════"
echo "  DATABASE ASSESSMENT REPORT"
echo "  Host: $DB_HOST:$DB_PORT/$DB_NAME"
echo "  Date: $(date)"
echo "═══════════════════════════════════════════════════"
echo

# 1. Database Overview
echo -e "${BLUE}1. DATABASE OVERVIEW${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "
SELECT
    current_database() AS database,
    pg_size_pretty(pg_database_size(current_database())) AS total_size,
    version() AS version;"
echo

# 2. Schema Summary
echo -e "${BLUE}2. SCHEMA SUMMARY${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "
SELECT
    schemaname AS schema,
    count(*) AS tables,
    pg_size_pretty(sum(pg_total_relation_size(schemaname||'.'||relname))) AS total_size
FROM pg_stat_user_tables
GROUP BY schemaname ORDER BY sum(pg_total_relation_size(schemaname||'.'||relname)) DESC;"
echo

# 3. Table Inventory (top 30 by size)
echo -e "${BLUE}3. TABLE INVENTORY (top 30 by size)${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "
SELECT
    schemaname||'.'||relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS data_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size,
    n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC LIMIT 30;"
echo

# 4. Column Data Types
echo -e "${BLUE}4. DATA TYPE DISTRIBUTION${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "
SELECT
    data_type,
    count(*) AS column_count,
    count(DISTINCT table_name) AS in_tables
FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog','information_schema')
GROUP BY data_type ORDER BY count(*) DESC;"
echo

# 5. Large Object / LOB columns
echo -e "${BLUE}5. LOB / LARGE DATA COLUMNS${NC}"
echo "─────────────────────────────────────────────────"
LOB_COUNT=$($PSQL -c "
SELECT count(*) FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog','information_schema')
AND (data_type IN ('bytea','text','json','jsonb','xml')
     OR data_type LIKE '%[]%'
     OR character_maximum_length > 10000
     OR character_maximum_length IS NULL AND data_type IN ('character varying'));" 2>/dev/null)

if [ "$LOB_COUNT" -gt 0 ] 2>/dev/null; then
    echo -e "${YELLOW}Found $LOB_COUNT potential LOB columns:${NC}"
    $PSQL_PRETTY -c "
    SELECT
        table_schema||'.'||table_name AS table_name,
        column_name,
        data_type,
        COALESCE(character_maximum_length::text, 'unlimited') AS max_length
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog','information_schema')
    AND (data_type IN ('bytea','text','json','jsonb','xml')
         OR data_type LIKE '%[]%'
         OR character_maximum_length > 10000)
    ORDER BY table_name, column_name;"
else
    echo "  No LOB columns found"
fi
echo

# 6. Indexes
echo -e "${BLUE}6. INDEX SUMMARY${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "
SELECT
    indexdef_type AS index_type,
    count(*) AS count
FROM (
    SELECT
        CASE
            WHEN indexdef LIKE '%UNIQUE%' THEN 'UNIQUE'
            WHEN indexdef LIKE '%gin%' OR indexdef LIKE '%GIN%' THEN 'GIN'
            WHEN indexdef LIKE '%gist%' OR indexdef LIKE '%GiST%' THEN 'GiST'
            WHEN indexdef LIKE '%brin%' OR indexdef LIKE '%BRIN%' THEN 'BRIN'
            WHEN indexdef LIKE '%hash%' THEN 'HASH'
            ELSE 'BTREE'
        END AS indexdef_type
    FROM pg_indexes
    WHERE schemaname NOT IN ('pg_catalog','information_schema')
) sub
GROUP BY indexdef_type ORDER BY count DESC;"

TOTAL_INDEXES=$($PSQL -c "SELECT count(*) FROM pg_indexes WHERE schemaname NOT IN ('pg_catalog','information_schema');" 2>/dev/null)
echo "  Total indexes: $TOTAL_INDEXES"
echo

# 7. Foreign Keys
echo -e "${BLUE}7. FOREIGN KEY CONSTRAINTS${NC}"
echo "─────────────────────────────────────────────────"
FK_COUNT=$($PSQL -c "
SELECT count(*) FROM information_schema.table_constraints
WHERE constraint_type = 'FOREIGN KEY'
AND table_schema NOT IN ('pg_catalog','information_schema');" 2>/dev/null)
echo "  Total foreign keys: $FK_COUNT"

if [ "$FK_COUNT" -gt 0 ] 2>/dev/null && [ "$FK_COUNT" -le 50 ]; then
    $PSQL_PRETTY -c "
    SELECT
        tc.table_schema||'.'||tc.table_name AS from_table,
        kcu.column_name AS from_column,
        ccu.table_schema||'.'||ccu.table_name AS to_table,
        ccu.column_name AS to_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema NOT IN ('pg_catalog','information_schema')
    ORDER BY tc.table_name LIMIT 50;"
elif [ "$FK_COUNT" -gt 50 ] 2>/dev/null; then
    echo "  (showing first 50)"
    $PSQL_PRETTY -c "
    SELECT tc.table_schema||'.'||tc.table_name AS from_table, count(*) AS fk_count
    FROM information_schema.table_constraints tc
    WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema NOT IN ('pg_catalog','information_schema')
    GROUP BY tc.table_schema, tc.table_name ORDER BY count(*) DESC LIMIT 50;"
fi
echo

# 8. Triggers
echo -e "${BLUE}8. TRIGGERS${NC}"
echo "─────────────────────────────────────────────────"
TRIGGER_COUNT=$($PSQL -c "
SELECT count(*) FROM information_schema.triggers
WHERE trigger_schema NOT IN ('pg_catalog','information_schema');" 2>/dev/null)
echo "  Total triggers: $TRIGGER_COUNT"

if [ "$TRIGGER_COUNT" -gt 0 ] 2>/dev/null; then
    $PSQL_PRETTY -c "
    SELECT
        event_object_schema||'.'||event_object_table AS table_name,
        trigger_name,
        event_manipulation AS event,
        action_timing AS timing
    FROM information_schema.triggers
    WHERE trigger_schema NOT IN ('pg_catalog','information_schema')
    ORDER BY table_name LIMIT 30;"
fi
echo

# 9. Views
echo -e "${BLUE}9. VIEWS${NC}"
echo "─────────────────────────────────────────────────"
VIEW_COUNT=$($PSQL -c "
SELECT count(*) FROM information_schema.views
WHERE table_schema NOT IN ('pg_catalog','information_schema');" 2>/dev/null)
echo "  Total views: $VIEW_COUNT"

if [ "$VIEW_COUNT" -gt 0 ] 2>/dev/null; then
    $PSQL_PRETTY -c "
    SELECT table_schema||'.'||table_name AS view_name
    FROM information_schema.views
    WHERE table_schema NOT IN ('pg_catalog','information_schema')
    ORDER BY table_name LIMIT 30;"
fi
echo

# 10. Stored Procedures / Functions
echo -e "${BLUE}10. FUNCTIONS / STORED PROCEDURES${NC}"
echo "─────────────────────────────────────────────────"
FUNC_COUNT=$($PSQL -c "
SELECT count(*) FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog','information_schema');" 2>/dev/null)
echo "  Total functions: $FUNC_COUNT"

if [ "$FUNC_COUNT" -gt 0 ] 2>/dev/null; then
    $PSQL_PRETTY -c "
    SELECT
        n.nspname||'.'||p.proname AS function_name,
        CASE p.prokind WHEN 'f' THEN 'function' WHEN 'p' THEN 'procedure' WHEN 'a' THEN 'aggregate' WHEN 'w' THEN 'window' END AS type,
        pg_get_function_arguments(p.oid) AS arguments
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname NOT IN ('pg_catalog','information_schema')
    ORDER BY n.nspname, p.proname LIMIT 30;"
fi
echo

# 11. Extensions
echo -e "${BLUE}11. EXTENSIONS${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
echo

# 12. Sequences
echo -e "${BLUE}12. SEQUENCES${NC}"
echo "─────────────────────────────────────────────────"
SEQ_COUNT=$($PSQL -c "SELECT count(*) FROM pg_sequences WHERE schemaname NOT IN ('pg_catalog','information_schema');" 2>/dev/null)
echo "  Total sequences: $SEQ_COUNT"

if [ "$SEQ_COUNT" -gt 0 ] 2>/dev/null; then
    $PSQL_PRETTY -c "
    SELECT schemaname||'.'||sequencename AS sequence_name, last_value, max_value
    FROM pg_sequences
    WHERE schemaname NOT IN ('pg_catalog','information_schema')
    ORDER BY sequencename LIMIT 30;"
fi
echo

# 13. Partitioned Tables
echo -e "${BLUE}13. PARTITIONED TABLES${NC}"
echo "─────────────────────────────────────────────────"
PART_COUNT=$($PSQL -c "
SELECT count(*) FROM pg_partitioned_table;" 2>/dev/null || echo "0")
echo "  Partitioned tables: $PART_COUNT"

if [ "$PART_COUNT" -gt 0 ] 2>/dev/null; then
    $PSQL_PRETTY -c "
    SELECT
        n.nspname||'.'||c.relname AS table_name,
        CASE pt.partstrat WHEN 'r' THEN 'RANGE' WHEN 'l' THEN 'LIST' WHEN 'h' THEN 'HASH' END AS strategy,
        (SELECT count(*) FROM pg_inherits WHERE inhparent = c.oid) AS partitions
    FROM pg_partitioned_table pt
    JOIN pg_class c ON pt.partrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname NOT IN ('pg_catalog','information_schema');"
fi
echo

# 14. Roles / Permissions
echo -e "${BLUE}14. DATABASE ROLES${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%' AND rolname NOT IN ('rdsadmin','rds_superuser','rds_replication','rds_password')
ORDER BY rolname;" 2>/dev/null || echo "  Cannot list roles (insufficient permissions)"
echo

# 15. Replication Status
echo -e "${BLUE}15. REPLICATION STATUS${NC}"
echo "─────────────────────────────────────────────────"
$PSQL_PRETTY -c "SHOW wal_level;" 2>/dev/null || echo "  Cannot check wal_level"
$PSQL_PRETTY -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;" 2>/dev/null || echo "  No replication slots"
echo

# 16. Migration Complexity Score
echo -e "${BLUE}16. MIGRATION COMPLEXITY ASSESSMENT${NC}"
echo "═══════════════════════════════════════════════════"

DB_SIZE_GB=$($PSQL -c "SELECT pg_database_size(current_database()) / 1073741824;" 2>/dev/null || echo "0")
TABLE_COUNT=$($PSQL -c "SELECT count(*) FROM pg_stat_user_tables;" 2>/dev/null || echo "0")

SCORE=0
NOTES=""

# Size scoring
if [ "$DB_SIZE_GB" -gt 1000 ]; then
    SCORE=$((SCORE + 3)); NOTES="$NOTES\n  ⚠ Large DB (${DB_SIZE_GB}GB) — use full-load then CDC (two-phase)"
elif [ "$DB_SIZE_GB" -gt 100 ]; then
    SCORE=$((SCORE + 2)); NOTES="$NOTES\n  ⚠ Medium DB (${DB_SIZE_GB}GB) — full-load-and-cdc may work but monitor WAL"
else
    SCORE=$((SCORE + 1)); NOTES="$NOTES\n  ✓ Small DB (${DB_SIZE_GB}GB) — full-load-and-cdc is fine"
fi

# LOB scoring
if [ "$LOB_COUNT" -gt 20 ]; then
    SCORE=$((SCORE + 3)); NOTES="$NOTES\n  ⚠ Many LOB columns ($LOB_COUNT) — enable FullLobMode or set LobMaxSize"
elif [ "$LOB_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 1)); NOTES="$NOTES\n  ⚠ Some LOB columns ($LOB_COUNT) — check LobMaxSize setting"
fi

# FK scoring
if [ "$FK_COUNT" -gt 50 ]; then
    SCORE=$((SCORE + 2)); NOTES="$NOTES\n  ⚠ Many FKs ($FK_COUNT) — disable before load, re-enable after"
elif [ "$FK_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 1)); NOTES="$NOTES\n  ⚠ Has FKs ($FK_COUNT) — DMS does not migrate FKs, add post-migration"
fi

# Trigger scoring
if [ "$TRIGGER_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 2)); NOTES="$NOTES\n  ⚠ Has triggers ($TRIGGER_COUNT) — disable on target during load"
fi

# Function scoring
if [ "$FUNC_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 1)); NOTES="$NOTES\n  ⚠ Has functions ($FUNC_COUNT) — migrate via pg_dump --schema-only"
fi

# View scoring
if [ "$VIEW_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 1)); NOTES="$NOTES\n  ⚠ Has views ($VIEW_COUNT) — migrate via pg_dump --schema-only"
fi

# Partition scoring
if [ "$PART_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 2)); NOTES="$NOTES\n  ⚠ Has partitioned tables ($PART_COUNT) — DMS needs special table mapping"
fi

# Index scoring
if [ "$TOTAL_INDEXES" -gt 100 ]; then
    SCORE=$((SCORE + 2)); NOTES="$NOTES\n  ⚠ Many indexes ($TOTAL_INDEXES) — create after full load for speed"
fi

# Sequence scoring
if [ "$SEQ_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 1)); NOTES="$NOTES\n  ⚠ Has sequences ($SEQ_COUNT) — sync after CDC cutover"
fi

echo
if [ $SCORE -le 5 ]; then
    echo -e "  Complexity: ${GREEN}LOW ($SCORE/20)${NC} — Standard DMS migration"
    echo "  Recommended: dms-pg-migrate.sh (as-is)"
elif [ $SCORE -le 10 ]; then
    echo -e "  Complexity: ${YELLOW}MEDIUM ($SCORE/20)${NC} — DMS + schema migration needed"
    echo "  Recommended: pg_dump schema + dms-pg-migrate.sh + post-migration scripts"
else
    echo -e "  Complexity: ${RED}HIGH ($SCORE/20)${NC} — Complex migration, needs planning"
    echo "  Recommended: Full assessment, pg_dump schema, DMS with custom table mappings"
fi

echo
echo -e "${BLUE}Migration Notes:${NC}"
echo -e "$NOTES"
echo

echo "═══════════════════════════════════════════════════"
echo "  Summary: ${TABLE_COUNT} tables | ${DB_SIZE_GB}GB | ${TOTAL_INDEXES} indexes"
echo "  ${FK_COUNT} FKs | ${TRIGGER_COUNT} triggers | ${FUNC_COUNT} functions"
echo "  ${VIEW_COUNT} views | ${SEQ_COUNT} sequences | ${PART_COUNT} partitions"
echo "═══════════════════════════════════════════════════"
echo
echo "Report saved to: $REPORT_FILE"
