# 02 — Payment Method Dimension

Incremental SCD Type 2 load of the Payment Method dimension from the WideWorldImporters OLTP database into a Fabric Lakehouse Delta table.

> **Prerequisites:** [01_prerequisites.md](01_prerequisites.md) must be implemented first (lineage table, ETL cutoff table, seed data).
> See [CONSTITUTION.md](CONSTITUTION.md) for package name, stack, connections, and environment details.

## SSIS Lineage

This spec documents the behavior of the **Load Payment Method Dimension** sequence container in `DailyETLMain.dtsx`. The inner execution order (from precedence constraints) is:

1. **Set TableName** — `@TableName = "Payment Method"`
2. **Get Lineage Key** — calls `Integration.GetLineageKey(@TableName, @TargetETLCutoffTime)` on the DW → inserts a row into `Integration.Lineage` with `Was Successful = 0`, returns `@LineageKey`
3. **Truncate Staging** — `DELETE FROM Integration.PaymentMethod_Staging`
4. **Get Last ETL Cutoff Time** — calls `Integration.GetLastETLCutoffTime(@TableName)` on the DW → reads `Cutoff Time` from `Integration.[ETL Cutoff]` into `@LastETLCutoffTime`
5. **Extract to Staging** — calls `Integration.GetPaymentMethodUpdates(@LastETLCutoffTime, @TargetETLCutoffTime)` on the OLTP source, pipes results into `Integration.PaymentMethod_Staging`
6. **Migrate Staged Data** — calls `Integration.MigrateStagedPaymentMethodData` on the DW, which:
   - Closes off existing SCD2 rows
   - Inserts new rows into `Dimension.[Payment Method]` (stamped with `@LineageKey`)
   - Updates `Integration.Lineage` to mark the load successful
   - Advances `Integration.[ETL Cutoff]` to the new cutoff time

The PySpark migration must reproduce the **net effect**: read changed rows from the source since the last watermark, apply transformations, merge into the destination as SCD Type 2, and update the lineage/cutoff tracking tables.

---

## Source Table (OLTP — WideWorldImporters)

### `Application.PaymentMethods` (temporal — system-versioned)

The source entity. History rows live in `Application.PaymentMethods_Archive`.

| Column            | Type           | Nullable | Notes |
|-------------------|----------------|----------|-------|
| PaymentMethodID   | int            | NOT NULL | PK, business key |
| PaymentMethodName | nvarchar(50)   | NOT NULL | |
| LastEditedBy      | int            | NOT NULL | FK → Application.People (not used by this ETL) |
| ValidFrom         | datetime2(7)   | NOT NULL | System-versioned period start |
| ValidTo           | datetime2(7)   | NOT NULL | System-versioned period end |

### `Application.PaymentMethods_Archive`

History table for temporal versioning. Same schema as `Application.PaymentMethods` (minus computed columns and constraints).

---

## Source Extraction Logic

The SSIS package calls `Integration.GetPaymentMethodUpdates(@LastCutoff, @NewCutoff)` on the **OLTP** database. The full procedure logic is reproduced below — the PySpark implementation must replicate its behavior.

### Change detection

The procedure finds all `PaymentMethodID` + `ValidFrom` pairs where `ValidFrom` falls in the window `(@LastCutoff, @NewCutoff]`, drawn from both the current table and the archive:

```sql
SELECT p.PaymentMethodID, p.ValidFrom
FROM [Application].PaymentMethods_Archive AS p
WHERE p.ValidFrom > @LastCutoff AND p.ValidFrom <= @NewCutoff
UNION ALL
SELECT p.PaymentMethodID, p.ValidFrom
FROM [Application].PaymentMethods AS p
WHERE p.ValidFrom > @LastCutoff AND p.ValidFrom <= @NewCutoff
ORDER BY ValidFrom
```

### Point-in-time snapshot per change

For each `(PaymentMethodID, ValidFrom)` pair, the procedure retrieves the payment method row **as of that exact `ValidFrom` timestamp** using `FOR SYSTEM_TIME AS OF @ValidFrom`. Since this is a single-table dimension with no joins, the query is straightforward:

```sql
SELECT p.PaymentMethodID, p.PaymentMethodName, p.ValidFrom, p.ValidTo
FROM [Application].PaymentMethods FOR SYSTEM_TIME AS OF @ValidFrom AS p
WHERE p.PaymentMethodID = @PaymentMethodID
```

### Valid To recalculation

After collecting all change rows into a temp table, the procedure recalculates `[Valid To]` for each row:

```sql
UPDATE cc
SET [Valid To] = COALESCE(
    (SELECT MIN([Valid From])
     FROM #PaymentMethodChanges AS cc2
     WHERE cc2.[WWI Payment Method ID] = cc.[WWI Payment Method ID]
       AND cc2.[Valid From] > cc.[Valid From]),
    '9999-12-31 23:59:59.9999999')
FROM #PaymentMethodChanges AS cc
```

For each change row, `[Valid To]` becomes the `[Valid From]` of the next change for the same payment method — or end-of-time (`9999-12-31 23:59:59.9999999`) if it's the latest change.

### No NULL replacement needed

Unlike more complex dimensions, there are no nullable business columns in this entity — no `ISNULL` / `COALESCE` defaults are applied.

---

## Staging Schema (DW — Integration.PaymentMethod_Staging)

The intermediate staging table on the DW side. The SSIS data flow inserts directly into it. The PySpark implementation does **not** need a physical staging table — this is documented for reference only.

| Column                     | Type          | Nullable |
|----------------------------|---------------|----------|
| Payment Method Staging Key | int           | NOT NULL | (identity, not relevant to PySpark) |
| WWI Payment Method ID      | int           | NOT NULL |
| Payment Method             | nvarchar(50)  | NOT NULL |
| Valid From                 | datetime2(7)  | NOT NULL |
| Valid To                   | datetime2(7)  | NOT NULL |

---

## Destination Table (DW — Dimension.[Payment Method])

The final SCD2 dimension table.

| Column                | Type          | Nullable | Notes |
|-----------------------|---------------|----------|-------|
| Payment Method Key    | int           | NOT NULL | PK — surrogate key from sequence `Sequences.PaymentMethodKey`. **Omit in PySpark output.** |
| WWI Payment Method ID | int           | NOT NULL | Business key — used for SCD2 matching |
| Payment Method        | nvarchar(50)  | NOT NULL | |
| Valid From            | datetime2(7)  | NOT NULL | SCD2 row-start |
| Valid To              | datetime2(7)  | NOT NULL | SCD2 row-end (`9999-12-31 23:59:59.9999999` for current) |
| Lineage Key           | int           | NOT NULL | ETL lineage reference. **Omit in PySpark output.** |

### Delta Table Name

`Dimension_Payment_Method`

### Delta Column Names

All spaces in column names are replaced with underscores:

| SQL Server Column Name  | Delta Column Name        |
|-------------------------|--------------------------|
| Payment Method Key      | *(omitted — surrogate key)* |
| WWI Payment Method ID   | WWI_Payment_Method_ID    |
| Payment Method          | Payment_Method           |
| Valid From              | Valid_From               |
| Valid To                | Valid_To                 |
| Lineage Key             | *(omitted — ETL metadata)* |

---

## Column Mapping — Source to Destination

How each output column is derived from source columns. This is the transformation the PySpark code must implement.

| Output Column          | Source Expression        | Notes |
|------------------------|--------------------------|-------|
| WWI Payment Method ID  | `p.PaymentMethodID`      | Business key — used for SCD2 matching |
| Payment Method         | `p.PaymentMethodName`    | |
| Valid From             | Recalculated — see [Valid To recalculation](#valid-to-recalculation) | |
| Valid To               | Recalculated — see [Valid To recalculation](#valid-to-recalculation) | End-of-time = `9999-12-31 23:59:59.9999999` for current row |

---

## SCD Type 2 Merge Logic

The SSIS `MigrateStagedPaymentMethodData` procedure performs two operations inside a transaction:

### Step 1 — Close off existing rows

For every `WWI Payment Method ID` that appears in the staging data, find the current row in the dimension (where `Valid To = '9999-12-31 23:59:59.9999999'`) and set its `Valid To` to the earliest `Valid From` of the incoming changes for that business key:

```sql
WITH RowsToCloseOff AS (
    SELECT pm.[WWI Payment Method ID], MIN(pm.[Valid From]) AS [Valid From]
    FROM Integration.PaymentMethod_Staging AS pm
    GROUP BY pm.[WWI Payment Method ID]
)
UPDATE pm
    SET pm.[Valid To] = rtco.[Valid From]
FROM Dimension.[Payment Method] AS pm
INNER JOIN RowsToCloseOff AS rtco
    ON pm.[WWI Payment Method ID] = rtco.[WWI Payment Method ID]
WHERE pm.[Valid To] = '9999-12-31 23:59:59.9999999';
```

### Step 2 — Insert new rows

Insert all staging rows into the dimension:

```sql
INSERT Dimension.[Payment Method]
    ([WWI Payment Method ID], [Payment Method], [Valid From], [Valid To], [Lineage Key])
SELECT [WWI Payment Method ID], [Payment Method], [Valid From], [Valid To],
       @LineageKey
FROM Integration.PaymentMethod_Staging;
```

In Delta/PySpark, this translates to a `MERGE` operation:
- **Match condition:** `WWI_Payment_Method_ID` (business key) AND target `Valid_To = '9999-12-31 23:59:59.9999999'`
- **When matched:** Update `Valid_To` to the earliest `Valid_From` of the incoming changes for that business key
- **Insert:** All incoming rows (including historical change rows within the window)

### Step 3 — Update lineage and advance cutoff

After the merge, the original `MigrateStagedPaymentMethodData` procedure completes the audit trail inside the same transaction:

```sql
-- Mark load successful
UPDATE Integration.Lineage
    SET [Data Load Completed] = SYSDATETIME(),
        [Was Successful] = 1
WHERE [Lineage Key] = @LineageKey;

-- Advance cutoff for next run
UPDATE Integration.[ETL Cutoff]
    SET [Cutoff Time] = (SELECT [Source System Cutoff Time]
                         FROM Integration.Lineage
                         WHERE [Lineage Key] = @LineageKey)
WHERE [Table Name] = N'Payment Method';
```

The PySpark implementation should call `complete_load(spark, lineage_key)` (from [01_prerequisites.md](01_prerequisites.md)) to perform the Delta equivalents of both updates.

---

## Watermark / Incremental Strategy

The watermark is stored in `Integration_ETL_Cutoff` (see [01_prerequisites.md](01_prerequisites.md)).

- Before extraction, read `Cutoff_Time` for `Table_Name = 'Payment Method'` → this is `@LastCutoff`.
- Use the already-computed `@TargetETLCutoffTime` as `@NewCutoff`.
- After a successful merge, advance `Cutoff_Time` for `'Payment Method'` to `@NewCutoff`.

---

## PySpark Source Query

Since `FOR SYSTEM_TIME AS OF` is a SQL Server temporal construct that must run on the source database, the PySpark implementation should use JDBC to push the extraction query down to SQL Server. The query is equivalent to the flattened logic of `Integration.GetPaymentMethodUpdates`:

**Option A — Call the stored procedure via JDBC** (simplest, if the procedure exists on the source):

```sql
EXEC Integration.GetPaymentMethodUpdates @LastCutoff=?, @NewCutoff=?
```

**Option B — Inline the query** (necessary if the stored procedure doesn't exist or can't be called):

Read the change list and snapshot data in a single query that replicates the procedure's cursor-based logic. Since cursors can't be used from JDBC, the equivalent can be achieved with a set-based approach using a CTE or temp table pattern.

The implementation should decide which option to use. Either approach is acceptable as long as the output rows match.
