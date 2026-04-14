

# 🔍 DMS Pre-Migration Database Assessment Tool

**Comprehensive database discovery and complexity scoring for planning AWS DMS PostgreSQL migrations.**

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-11%2B-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![AWS DMS](https://img.shields.io/badge/AWS-DMS-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/dms/)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

</div>

---

## 🎯 Why Run an Assessment First?

| | Without Assessment | With Assessment |
|---|---|---|
| 🔥 | Discover issues mid-migration | Know all issues upfront |
| ⚙️ | Wrong DMS settings (LOB mode, etc.) | Tailored DMS configuration |
| 🧩 | Missing schema objects post-migration | Complete migration checklist |
| ⏱️ | Unknown downtime risk | Accurate complexity score & timeline |

---

## 🔄 Assessment Flow

```mermaid
graph TD
    A[🔌 Connect to Source PostgreSQL] --> B[🔎 Scan 16 Assessment Areas]
    B --> C[📊 Calculate Complexity Score]
    C --> D{Score?}
    D -->|🟢 0-5 LOW| E[Run dms-pg-migrate.sh directly]
    D -->|🟡 6-10 MEDIUM| F[pg_dump schema + DMS + post-migration]
    D -->|🔴 11-20 HIGH| G[Detailed planning + custom table mappings]
    C --> H[📄 Save Report to File]
```

---

## ⚙️ Prerequisites

| Requirement | Install Command |
|---|---|
| **bash 4.0+** | Pre-installed on most systems |
| **psql client** | `brew install libpq` (macOS) / `apt install postgresql-client` (Ubuntu) |
| **Network access** | Must be able to reach source PostgreSQL on port 5432 |

---

## 🚀 Quick Start

```bash
chmod +x db-assessment.sh
./db-assessment.sh
```

```
DB Host:      mydb.cluster-abc123.us-east-2.rds.amazonaws.com
DB Port:      5432
DB Name:      insurance_db
DB Username:  postgres
DB Password:  ********
```

---

## 🔐 Required Database Permissions

> 💡 The assessment is **read-only** — no changes are made to the source database.

```sql
-- ✅ Minimum permissions
GRANT CONNECT ON DATABASE mydb TO assessment_user;
GRANT USAGE ON SCHEMA public TO assessment_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO assessment_user;

-- 🌟 Recommended (for accurate row counts)
GRANT pg_read_all_stats TO assessment_user;
```

---

## 🔎 16 Assessment Areas

### 📦 Structure & Size

| # | Area | What It Checks | Migration Impact |
|---|---|---|---|
| 1️⃣ | **Database Overview** | Total size, PostgreSQL version | Migration type decision, version compatibility |
| 2️⃣ | **Schema Summary** | Schema count, sizes per schema | Multi-schema DMS table mappings |
| 3️⃣ | **Table Inventory** | Top 30 tables by size, row counts | Full load parallelism, largest table planning |
| 4️⃣ | **Data Type Distribution** | Column types across all tables | Type compatibility, DMS type mappings |

### 📄 Data Complexity

| # | Area | What It Checks | Migration Impact |
|---|---|---|---|
| 5️⃣ | **LOB / Large Columns** | BYTEA, TEXT, JSON, JSONB, XML, arrays | DMS LOB mode — `FullLobMode` vs `LimitedLobMode` |
| 6️⃣ | **Index Summary** | BTREE, GIN, GiST, BRIN, HASH, UNIQUE | Create indexes **after** full load for speed |
| 7️⃣ | **Foreign Keys** | FK constraints between tables | DMS does **not** migrate FKs — add post-migration |
| 8️⃣ | **Triggers** | BEFORE/AFTER INSERT/UPDATE/DELETE triggers | Disable on target during migration |

### 🧩 Schema Objects

| # | Area | What It Checks | Migration Impact |
|---|---|---|---|
| 9️⃣ | **Views** | View definitions | Migrate via `pg_dump --schema-only` |
| 🔟 | **Functions / Procedures** | Functions, procedures, aggregates | Migrate via `pg_dump --schema-only` |
| 1️⃣1️⃣ | **Extensions** | PostGIS, pgcrypto, pg_trgm, etc. | Must install on target **before** migration |
| 1️⃣2️⃣ | **Sequences** | Sequence names and current values | Sync values after CDC cutover |

### 🏗️ Advanced

| # | Area | What It Checks | Migration Impact |
|---|---|---|---|
| 1️⃣3️⃣ | **Partitioned Tables** | RANGE / LIST / HASH partitions | DMS needs special table mapping rules |
| 1️⃣4️⃣ | **Database Roles** | Users, permissions, superuser flags | Recreate on target account |
| 1️⃣5️⃣ | **Replication Status** | WAL level, replication slots | CDC readiness — `wal_level` must be `logical` |
| 1️⃣6️⃣ | **Complexity Score** | Weighted score (0-20) | Determines migration approach |

---

## 📊 Complexity Scoring

### Scoring Weights

| Factor | Weight | Condition |
|---|---|---|
| 💾 **Database size** | 1-3 | `<100GB` = 1 · `100GB-1TB` = 2 · `>1TB` = 3 |
| 📄 **LOB columns** | 0-3 | `None` = 0 · `1-20` = 1 · `>20` = 3 |
| 🔗 **Foreign keys** | 0-2 | `None` = 0 · `1-50` = 1 · `>50` = 2 |
| ⚡ **Triggers** | 0-2 | `None` = 0 · `Any` = 2 |
| 🧩 **Functions** | 0-1 | `None` = 0 · `Any` = 1 |
| 👁️ **Views** | 0-1 | `None` = 0 · `Any` = 1 |
| 📦 **Partitions** | 0-2 | `None` = 0 · `Any` = 2 |
| 📇 **Indexes** | 0-2 | `<100` = 0 · `>100` = 2 |
| 🔢 **Sequences** | 0-1 | `None` = 0 · `Any` = 1 |

### Score Interpretation

| Score | Level | Recommended Approach |
|---|---|---|
| **0 – 5** | 🟢 **LOW** | Run `dms-pg-migrate.sh` directly — standard DMS migration |
| **6 – 10** | 🟡 **MEDIUM** | `pg_dump --schema-only` first → DMS → post-migration scripts for FKs, triggers, views |
| **11 – 20** | 🔴 **HIGH** | Detailed planning required — custom DMS table mappings, phased migration |

---

## 📄 Sample Output

```
═══════════════════════════════════════════════════
  DATABASE ASSESSMENT REPORT
  Host: mydb.cluster-abc123.us-east-2.rds.amazonaws.com:5432/insurance_db
  Date: Sun Mar 29 14:30:21 CDT 2026
═══════════════════════════════════════════════════

1. DATABASE OVERVIEW
─────────────────────────────────────────────────
  database     | total_size | version
  insurance_db | 2.5 TB     | PostgreSQL 14.10

2. SCHEMA SUMMARY
─────────────────────────────────────────────────
  schema  | tables | total_size
  public  | 230    | 2.3 TB
  audit   | 15     | 200 GB

3. TABLE INVENTORY (top 30 by size)
─────────────────────────────────────────────────
  table_name          | total_size | data_size | index_size | row_count
  public.claims       | 800 GB     | 600 GB    | 200 GB     | 450000000
  public.policies     | 500 GB     | 380 GB    | 120 GB     | 280000000
  public.documents    | 400 GB     | 390 GB    | 10 GB      | 15000000

  ...

16. MIGRATION COMPLEXITY ASSESSMENT
═══════════════════════════════════════════════════

  Complexity: MEDIUM (8/20) — DMS + schema migration needed
  Recommended: pg_dump schema + dms-pg-migrate.sh + post-migration scripts

Migration Notes:
  ⚠ Large DB (2500GB) — use full-load then CDC (two-phase)
  ⚠ Some LOB columns (12) — check LobMaxSize setting
  ⚠ Has FKs (45) — DMS does not migrate FKs, add post-migration
  ⚠ Has triggers (8) — disable on target during load
  ⚠ Has functions (23) — migrate via pg_dump --schema-only
  ⚠ Has views (15) — migrate via pg_dump --schema-only
  ⚠ Has sequences (30) — sync after CDC cutover

═══════════════════════════════════════════════════
  Summary: 245 tables | 2500GB | 312 indexes
  45 FKs | 8 triggers | 23 functions
  15 views | 30 sequences | 0 partitions
═══════════════════════════════════════════════════
```

> 📁 Report saved to: `db-assessment-20260329-143021.txt`

---

## ⏱️ Expected Timeline by Database Size

| DB Size | Assessment | Full Load | CDC Catch-up | Total |
|---|---|---|---|---|
| **< 100 GB** | ~2 min | 30-60 min | Near real-time | **~1 hour** |
| **100 GB – 1 TB** | ~2 min | 2-6 hours | Near real-time | **~3-7 hours** |
| **1 TB – 5 TB** | ~2 min | 8-24 hours | Near real-time | **~10-26 hours** |
| **> 5 TB** | ~2 min | 1-3 days | Near real-time | **1-3 days** |

> ⚠️ Full load time depends on instance class, IOPS, network throughput, and table structure.
> For databases **> 1TB**, always use the **two-phase approach** (full-load first, then CDC separately) to avoid WAL log buildup.

---

## 🧰 Migration Toolkit

This tool is part of the **DMS PostgreSQL Migration Toolkit**:

| Script | Purpose | When to Run |
|---|---|---|
| 🔍 **`db-assessment.sh`** | Database discovery & complexity scoring | ⬅️ **Run first** — before planning |
| 🚀 **`dms-pg-migrate.sh`** | Full migration (VPC peering → RDS → DMS → full load → CDC) | Migration execution |
| ✂️ **`dms-cutover.sh`** | Stop CDC, verify data, update Secrets Manager | Cutover day |
| 🧹 **`dms-cleanup.sh`** | Remove all DMS resources, peering, routes | After migration confirmed stable |

---

## 🗺️ End-to-End Workflow

```
  🔍 Run db-assessment.sh on source DB
              │
              ▼
  📊 Review complexity score & notes
              │
              ├── 🟢 LOW (0-5)  ──────► 🚀 Run dms-pg-migrate.sh directly
              │
              ├── 🟡 MEDIUM (6-10) ──► 📦 pg_dump --schema-only first
              │                        🚀 then dms-pg-migrate.sh
              │                        🔧 then post-migration scripts
              │
              └── 🔴 HIGH (11-20) ──► 📋 Detailed planning required
                                      🗂️ Custom DMS table mappings
                                      📐 Phased migration approach
              │
              ▼
  ✂️ Run dms-cutover.sh on cutover day
              │
              ▼
  🧹 Run dms-cleanup.sh after confirmed stable
```

---

## ⚠️ Important Notes

> 🔒 Assessment is **read-only** — no changes are made to the source database

- 📊 Some checks require `pg_read_all_stats` role for accurate row counts
- 📦 Partitioned table detection requires **PostgreSQL 10+**
- 🧩 Function type detection (`prokind`) requires **PostgreSQL 11+**
- 🔌 Does **not** assess application-level dependencies (connection strings, ORMs, connection pools)
- 📄 LOB columns with large objects (PDFs, images > 1MB) need `FullLobMode` which significantly slows migration
- 💾 For databases **> 1TB**, always use the **two-phase approach** (full-load first, then CDC separately)

---

<div align="center">

## 📜 License

MIT License

---

**Built for AWS DMS PostgreSQL Cross-Account Migrations**

</div>
