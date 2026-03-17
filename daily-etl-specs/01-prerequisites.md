# 01 — Prerequisites

Infrastructure tables and seed data required before any dimension load can run. Implement this spec first.

> See [CONSTITUTION.md](CONSTITUTION.md) for package name, stack, connections, and environment details.

## SSIS Lineage

In `DailyETLMain.dtsx`, three tasks run before any dimension sequence container:

1. **Calculate ETL Cutoff Time backup** — `@TargetETLCutoffTime = GETDATE() - 5 minutes`
2. **Trim Any Milliseconds** — truncates `@TargetETLCutoffTime` to whole seconds
3. **Ensure Date Dimension includes current year** — calls `Integration.PopulateDateDimensionForYear(@YearNumber)` on the DW

Every dimension sequence container then uses two DW-side stored procedures that depend on the tables documented below:

- `Integration.GetLineageKey(@TableName, @NewCutoffTime)` — inserts a row into `Integration.Lineage` and returns the new key
- `Integration.GetLastETLCutoffTime(@TableName)` — reads the watermark from `Integration.[ETL Cutoff]`

After each dimension's merge completes, `MigrateStaged*Data` updates both tables to mark the load as successful and advance the cutoff.

The PySpark migration replaces these SQL Server objects with Delta tables in the Lakehouse.

---

## ETL Cutoff Time Calculation

The SSIS package computes the target cutoff time at the very start of each run:

```
@TargetETLCutoffTime = DATEADD("Minute", -5, GETDATE())
@TargetETLCutoffTime = DATEADD("Millisecond", 0 - DATEPART("Millisecond", @TargetETLCutoffTime), @TargetETLCutoffTime)
```

This gives a cutoff 5 minutes in the past with milliseconds stripped. The 5-minute lag avoids reading uncommitted transactions on the source. The PySpark implementation should compute this the same way in Python before passing it to the extraction query.

---

## Infrastructure Tables

### `Integration.Lineage` → Delta: `Integration_Lineage`

Audit log of every ETL load attempt. One row per (table, run).

| SQL Server Column           | Type          | Nullable | Delta Column                  | Notes |
|-----------------------------|---------------|----------|-------------------------------|-------|
| Lineage Key                 | int           | NOT NULL | Lineage_Key                   | PK. In SQL Server, default = `NEXT VALUE FOR Sequences.LineageKey`. In Delta, auto-increment or max+1. |
| Data Load Started           | datetime2(7)  | NOT NULL | Data_Load_Started             | Timestamp when the load attempt began |
| Table Name                  | sysname       | NOT NULL | Table_Name                    | e.g. `'Stock Item'` |
| Data Load Completed         | datetime2(7)  | NULL     | Data_Load_Completed           | NULL while in-progress; set on success |
| Was Successful              | bit           | NOT NULL | Was_Successful                | `0` on insert; set to `1` on success |
| Source System Cutoff Time   | datetime2(7)  | NOT NULL | Source_System_Cutoff_Time     | The `@TargetETLCutoffTime` passed in — upper bound of the extraction window |

**Behavior to replicate:**

`GetLineageKey` inserts a row with `Was_Successful = false` and `Data_Load_Completed = NULL`, then returns the new `Lineage_Key`. After the merge succeeds, `MigrateStaged*Data` updates the row:

```sql
UPDATE Integration.Lineage
    SET [Data Load Completed] = SYSDATETIME(),
        [Was Successful] = 1
WHERE [Lineage Key] = @LineageKey;
```

The PySpark equivalent: insert a row into the `Integration_Lineage` Delta table at the start of the load, then update it after the merge completes.

### `Integration.[ETL Cutoff]` → Delta: `Integration_ETL_Cutoff`

Watermark table. One row per dimension/fact table, tracking how far data has been loaded.

| SQL Server Column | Type          | Nullable | Delta Column  | Notes |
|-------------------|---------------|----------|---------------|-------|
| Table Name        | sysname       | NOT NULL | Table_Name    | PK. e.g. `'Stock Item'` |
| Cutoff Time       | datetime2(7)  | NOT NULL | Cutoff_Time   | Last successfully loaded source `ValidFrom` |

**Behavior to replicate:**

`GetLastETLCutoffTime` reads this for the `@LastCutoff` extraction parameter. After a successful merge, `MigrateStaged*Data` advances it:

```sql
UPDATE Integration.[ETL Cutoff]
    SET [Cutoff Time] = (SELECT [Source System Cutoff Time]
                         FROM Integration.Lineage
                         WHERE [Lineage Key] = @LineageKey)
WHERE [Table Name] = N'Stock Item';
```

The PySpark equivalent: read the cutoff before extraction, then overwrite/update it after a successful merge.

**Seed value:** For the initial full load, seed with a date before any source data exists:

| Table_Name         | Cutoff_Time             |
|--------------------|-------------------------|
| `Payment Method`   | `2012-12-31 00:00:00`   |
| `Transaction Type` | `2012-12-31 00:00:00`   |
| `Stock Item`       | `2012-12-31 00:00:00`   |

This matches the `Configuration_ReseedETL` procedure's starting value of `20121231`.

---

## Seed Data — "Unknown" Dimension Rows

The original DW seeds each dimension with a key-0 "Unknown" row used as a default for fact table lookups.

### Payment Method

```sql
INSERT Dimension.[Payment Method]
    ([Payment Method Key], [WWI Payment Method ID], [Payment Method],
     [Valid From], [Valid To], [Lineage Key])
VALUES
    (0, 0, N'Unknown', '2013-01-01', '9999-12-31 23:59:59.9999999', 0);
```

The PySpark implementation should insert this row when creating the `Dimension_Payment_Method` table for the first time (if it doesn't already exist). Use `WWI_Payment_Method_ID = 0` as the sentinel.

### Transaction Type

```sql
INSERT Dimension.[Transaction Type]
    ([Transaction Type Key], [WWI Transaction Type ID], [Transaction Type],
     [Valid From], [Valid To], [Lineage Key])
VALUES
    (0, 0, N'Unknown', '2013-01-01', '9999-12-31 23:59:59.9999999', 0);
```

The PySpark implementation should insert this row when creating the `Dimension_Transaction_Type` table for the first time (if it doesn't already exist). Use `WWI_Transaction_Type_ID = 0` as the sentinel.

### Stock Item

```sql
INSERT Dimension.[Stock Item]
    ([Stock Item Key], [WWI Stock Item ID], [Stock Item], Color,
     [Selling Package], [Buying Package], Brand, Size,
     [Lead Time Days], [Quantity Per Outer], [Is Chiller Stock],
     Barcode, [Tax Rate], [Unit Price], [Recommended Retail Price],
     [Typical Weight Per Unit], Photo, [Valid From], [Valid To], [Lineage Key])
VALUES
    (0, 0, N'Unknown', N'N/A', N'N/A', N'N/A',
     N'N/A', N'N/A', 0, 0, 0,
     N'N/A', 0, 0, 0, 0,
     NULL, '2013-01-01', '9999-12-31 23:59:59.9999999', 0);
```

The PySpark implementation should insert this row when creating the `Dimension_Stock_Item` table for the first time (if it doesn't already exist). Use `WWI_Stock_Item_ID = 0` as the sentinel.

For all dimensions, the `Lineage_Key` column is omitted from the Delta table per the constitution, so omit it from the seed row too.

---

## Date Dimension (out of scope — documented for reference)

The SSIS package calls `Integration.PopulateDateDimensionForYear` before the dimension loads. This populates `Dimension.[Date]` with one row per day for the current year. The Stock Item dimension does **not** join to or depend on the Date dimension, so this is **not required** as a prerequisite for implementing the Stock Item load. It is documented here only for completeness — it will become relevant when fact tables are added.

---

## PySpark Implementation Notes

### Initialization function

Create a function that ensures the infrastructure tables exist and are seeded:

1. Create `Integration_Lineage` Delta table if it doesn't exist
2. Create `Integration_ETL_Cutoff` Delta table if it doesn't exist; seed with the initial cutoff rows for all dimensions documented in this spec set
3. Create each dimension's Delta table if it doesn't exist; insert its "Unknown" seed row

This function should be idempotent — safe to call on every run.

### Cutoff time calculation

```python
from datetime import datetime, timedelta

target_cutoff = datetime.utcnow() - timedelta(minutes=5)
target_cutoff = target_cutoff.replace(microsecond=0)  # strip sub-second
```

### Lineage helper functions

Two helper functions wrapping the lineage table:

1. **`begin_load(spark, table_name, cutoff_time) → lineage_key`** — inserts a row into `Integration_Lineage` and returns the key
2. **`complete_load(spark, lineage_key)`** — updates the row with `Data_Load_Completed` and `Was_Successful = True`, then advances `Integration_ETL_Cutoff`

---

## Testing

### Test Structure

- **`Integration_Lineage`:** After calling `begin_load`, verify a row exists with `Was_Successful = False` and `Data_Load_Completed = None`. After calling `complete_load`, verify `Was_Successful = True` and `Data_Load_Completed` is set.
- **`Integration_ETL_Cutoff`:** Verify initial seed value. After `complete_load`, verify the cutoff advanced to the new value.
- **Seed rows:** Verify the "Unknown" row exists in each dimension table with the corresponding `WWI_*_ID = 0` sentinel.
- **Idempotency:** Call the initialization function twice; verify no duplicate rows or errors.
