# 04 — Stock Item Dimension

Incremental SCD Type 2 load of the Stock Item dimension from the WideWorldImporters OLTP database into a Fabric Lakehouse Delta table.

> **Prerequisites:** [01_prerequisites.md](01_prerequisites.md) must be implemented first (lineage table, ETL cutoff table, seed data).
> See [CONSTITUTION.md](CONSTITUTION.md) for package name, stack, connections, and environment details.

## SSIS Lineage

This spec documents the behavior of the **Load Stock Item Dimension** sequence container in `DailyETLMain.dtsx`. The inner execution order (from precedence constraints) is:

1. **Set TableName** — `@TableName = "Stock Item"`
2. **Get Lineage Key** — calls `Integration.GetLineageKey(@TableName, @TargetETLCutoffTime)` on the DW → inserts a row into `Integration.Lineage` with `Was Successful = 0`, returns `@LineageKey`
3. **Truncate Staging** — `DELETE FROM Integration.StockItem_Staging`
4. **Get Last ETL Cutoff Time** — calls `Integration.GetLastETLCutoffTime(@TableName)` on the DW → reads `Cutoff Time` from `Integration.[ETL Cutoff]` into `@LastETLCutoffTime`
5. **Extract to Staging** — calls `Integration.GetStockItemUpdates(@LastETLCutoffTime, @TargetETLCutoffTime)` on the OLTP source, pipes results into `Integration.StockItem_Staging`
6. **Migrate Staged Data** — calls `Integration.MigrateStagedStockItemData` on the DW, which:
   - Closes off existing SCD2 rows
   - Inserts new rows into `Dimension.[Stock Item]` (stamped with `@LineageKey`)
   - Updates `Integration.Lineage` to mark the load successful
   - Advances `Integration.[ETL Cutoff]` to the new cutoff time

The PySpark migration must reproduce the **net effect**: read changed rows from the source since the last watermark, apply transformations, merge into the destination as SCD Type 2, and update the lineage/cutoff tracking tables.

---

## Source Tables (OLTP — WideWorldImporters)

### `Warehouse.StockItems` (temporal — system-versioned)

The primary source entity. History rows live in `Warehouse.StockItems_Archive`.

| Column               | Type            | Nullable | Notes |
|----------------------|-----------------|----------|-------|
| StockItemID          | int             | NOT NULL | PK, business key |
| StockItemName        | nvarchar(100)   | NOT NULL | |
| SupplierID           | int             | NOT NULL | FK → Purchasing.Suppliers (not used by this ETL) |
| ColorID              | int             | NULL     | FK → Warehouse.Colors |
| UnitPackageID        | int             | NOT NULL | FK → Warehouse.PackageTypes (selling package) |
| OuterPackageID       | int             | NOT NULL | FK → Warehouse.PackageTypes (buying package) |
| Brand                | nvarchar(50)    | NULL     | |
| Size                 | nvarchar(20)    | NULL     | |
| LeadTimeDays         | int             | NOT NULL | |
| QuantityPerOuter     | int             | NOT NULL | |
| IsChillerStock       | bit             | NOT NULL | |
| Barcode              | nvarchar(50)    | NULL     | |
| TaxRate              | decimal(18,3)   | NOT NULL | |
| UnitPrice            | decimal(18,2)   | NOT NULL | |
| RecommendedRetailPrice | decimal(18,2) | NULL     | |
| TypicalWeightPerUnit | decimal(18,3)   | NOT NULL | |
| Photo                | varbinary(max)  | NULL     | |
| ValidFrom            | datetime2(7)    | NOT NULL | System-versioned period start |
| ValidTo              | datetime2(7)    | NOT NULL | System-versioned period end |

### `Warehouse.StockItems_Archive`

History table for temporal versioning. Same schema as `Warehouse.StockItems` (minus computed columns and constraints).

### `Warehouse.Colors` (temporal)

| Column    | Type          | Nullable |
|-----------|---------------|----------|
| ColorID   | int           | NOT NULL |
| ColorName | nvarchar(20)  | NOT NULL |
| ValidFrom | datetime2(7)  | NOT NULL |
| ValidTo   | datetime2(7)  | NOT NULL |

### `Warehouse.PackageTypes` (temporal)

| Column          | Type          | Nullable |
|-----------------|---------------|----------|
| PackageTypeID   | int           | NOT NULL |
| PackageTypeName | nvarchar(50)  | NOT NULL |
| ValidFrom       | datetime2(7)  | NOT NULL |
| ValidTo         | datetime2(7)  | NOT NULL |

---

## Source Extraction Logic

The SSIS package calls `Integration.GetStockItemUpdates(@LastCutoff, @NewCutoff)` on the **OLTP** database. The full procedure logic is reproduced below — the PySpark implementation must replicate its behavior.

### Change detection

The procedure finds all `StockItemID` + `ValidFrom` pairs where `ValidFrom` falls in the window `(@LastCutoff, @NewCutoff]`, drawn from both the current table and the archive:

```sql
SELECT c.StockItemID, c.ValidFrom
FROM Warehouse.StockItems_Archive AS c
WHERE c.ValidFrom > @LastCutoff AND c.ValidFrom <= @NewCutoff
UNION ALL
SELECT c.StockItemID, c.ValidFrom
FROM Warehouse.StockItems AS c
WHERE c.ValidFrom > @LastCutoff AND c.ValidFrom <= @NewCutoff
ORDER BY ValidFrom
```

### Point-in-time snapshot per change

For each `(StockItemID, ValidFrom)` pair, the procedure retrieves the stock item row **as of that exact `ValidFrom` timestamp** using `FOR SYSTEM_TIME AS OF @ValidFrom`. This means it joins temporal tables at the point in time each change occurred:

```sql
SELECT si.StockItemID, si.StockItemName, c.ColorName,
       spt.PackageTypeName,   -- selling (unit) package
       bpt.PackageTypeName,   -- buying (outer) package
       si.Brand, si.Size, si.LeadTimeDays, si.QuantityPerOuter,
       si.IsChillerStock, si.Barcode,
       si.LeadTimeDays,       -- ⚠ BUG: mapped to [Tax Rate] column
       si.UnitPrice, si.RecommendedRetailPrice,
       si.TypicalWeightPerUnit, si.Photo,
       si.ValidFrom, si.ValidTo
FROM Warehouse.StockItems FOR SYSTEM_TIME AS OF @ValidFrom AS si
INNER JOIN Warehouse.PackageTypes FOR SYSTEM_TIME AS OF @ValidFrom AS spt
    ON si.UnitPackageID = spt.PackageTypeID
INNER JOIN Warehouse.PackageTypes FOR SYSTEM_TIME AS OF @ValidFrom AS bpt
    ON si.OuterPackageID = bpt.PackageTypeID
LEFT OUTER JOIN Warehouse.Colors FOR SYSTEM_TIME AS OF @ValidFrom AS c
    ON si.ColorID = c.ColorID
WHERE si.StockItemID = @StockItemID
```

### Known bug — Tax Rate mapping

The original stored procedure's SELECT list has `si.LeadTimeDays` in the position that maps to the `[Tax Rate]` output column:

```
si.LeadTimeDays, si.QuantityPerOuter, si.IsChillerStock, si.Barcode,
si.LeadTimeDays,       ← this is the [Tax Rate] position
si.UnitPrice, ...
```

This means the `[Tax Rate]` column in the staging table and ultimately in `Dimension.[Stock Item]` actually contains the value of `LeadTimeDays` — **not** the real `TaxRate`. This is a bug in the original WWI sample. The PySpark implementation should replicate this behavior exactly if the goal is to match the existing DW output. Document the bug but don't fix it, so tests pass against the existing destination data.

### Valid To recalculation

After collecting all change rows into a temp table, the procedure recalculates `[Valid To]` for each row:

```sql
UPDATE cc
SET [Valid To] = COALESCE(
    (SELECT MIN([Valid From])
     FROM #StockItemChanges AS cc2
     WHERE cc2.[WWI Stock Item ID] = cc.[WWI Stock Item ID]
       AND cc2.[Valid From] > cc.[Valid From]),
    '9999-12-31 23:59:59.9999999')
FROM #StockItemChanges AS cc
```

For each change row, `[Valid To]` becomes the `[Valid From]` of the next change for the same stock item — or end-of-time (`9999-12-31 23:59:59.9999999`) if it's the latest change.

### NULL replacement

The final SELECT applies `ISNULL` to replace NULLs with `'N/A'` for these columns:

| Column  | Default |
|---------|---------|
| Color   | `N/A`   |
| Brand   | `N/A`   |
| Size    | `N/A`   |
| Barcode | `N/A`   |

---

## Staging Schema (DW — Integration.StockItem_Staging)

The intermediate staging table on the DW side. The SSIS data flow inserts directly into it. The PySpark implementation does **not** need a physical staging table — this is documented for reference only.

| Column                   | Type            | Nullable |
|--------------------------|-----------------|----------|
| Stock Item Staging Key   | int             | NOT NULL | (identity, not relevant to PySpark) |
| WWI Stock Item ID        | int             | NOT NULL |
| Stock Item               | nvarchar(100)   | NOT NULL |
| Color                    | nvarchar(20)    | NOT NULL |
| Selling Package          | nvarchar(50)    | NOT NULL |
| Buying Package           | nvarchar(50)    | NOT NULL |
| Brand                    | nvarchar(50)    | NOT NULL |
| Size                     | nvarchar(20)    | NOT NULL |
| Lead Time Days           | int             | NOT NULL |
| Quantity Per Outer       | int             | NOT NULL |
| Is Chiller Stock         | bit             | NOT NULL |
| Barcode                  | nvarchar(50)    | NULL     |
| Tax Rate                 | decimal(18,3)   | NOT NULL |
| Unit Price               | decimal(18,2)   | NOT NULL |
| Recommended Retail Price | decimal(18,2)   | NULL     |
| Typical Weight Per Unit  | decimal(18,3)   | NOT NULL |
| Photo                    | varbinary(max)  | NULL     |
| Valid From               | datetime2(7)    | NOT NULL |
| Valid To                 | datetime2(7)    | NOT NULL |

---

## Destination Table (DW — Dimension.[Stock Item])

The final SCD2 dimension table.

| Column                   | Type            | Nullable | Notes |
|--------------------------|-----------------|----------|-------|
| Stock Item Key           | int             | NOT NULL | PK — surrogate key from sequence `Sequences.StockItemKey`. **Omit in PySpark output.** |
| WWI Stock Item ID        | int             | NOT NULL | Business key — used for SCD2 matching |
| Stock Item               | nvarchar(100)   | NOT NULL | |
| Color                    | nvarchar(20)    | NOT NULL | |
| Selling Package          | nvarchar(50)    | NOT NULL | |
| Buying Package           | nvarchar(50)    | NOT NULL | |
| Brand                    | nvarchar(50)    | NOT NULL | |
| Size                     | nvarchar(20)    | NOT NULL | |
| Lead Time Days           | int             | NOT NULL | |
| Quantity Per Outer       | int             | NOT NULL | |
| Is Chiller Stock         | bit             | NOT NULL | |
| Barcode                  | nvarchar(50)    | NULL     | |
| Tax Rate                 | decimal(18,3)   | NOT NULL | ⚠ Actually contains `LeadTimeDays` due to source bug |
| Unit Price               | decimal(18,2)   | NOT NULL | |
| Recommended Retail Price | decimal(18,2)   | NULL     | |
| Typical Weight Per Unit  | decimal(18,3)   | NOT NULL | |
| Photo                    | varbinary(max)  | NULL     | |
| Valid From               | datetime2(7)    | NOT NULL | SCD2 row-start |
| Valid To                 | datetime2(7)    | NOT NULL | SCD2 row-end (`9999-12-31 23:59:59.9999999` for current) |
| Lineage Key              | int             | NOT NULL | ETL lineage reference. **Omit in PySpark output.** |

### Delta Table Name

`Dimension_Stock_Item`

### Delta Column Names

All spaces in column names are replaced with underscores:

| SQL Server Column Name     | Delta Column Name            |
|----------------------------|------------------------------|
| Stock Item Key             | *(omitted — surrogate key)* |
| WWI Stock Item ID          | WWI_Stock_Item_ID            |
| Stock Item                 | Stock_Item                   |
| Color                      | Color                        |
| Selling Package            | Selling_Package              |
| Buying Package             | Buying_Package               |
| Brand                      | Brand                        |
| Size                       | Size                         |
| Lead Time Days             | Lead_Time_Days               |
| Quantity Per Outer         | Quantity_Per_Outer           |
| Is Chiller Stock           | Is_Chiller_Stock             |
| Barcode                    | Barcode                      |
| Tax Rate                   | Tax_Rate                     |
| Unit Price                 | Unit_Price                   |
| Recommended Retail Price   | Recommended_Retail_Price     |
| Typical Weight Per Unit    | Typical_Weight_Per_Unit      |
| Photo                      | Photo                        |
| Valid From                 | Valid_From                   |
| Valid To                   | Valid_To                     |
| Lineage Key                | *(omitted — ETL metadata)*  |

---

## Column Mapping — Source to Destination

How each output column is derived from source columns. This is the transformation the PySpark code must implement.

| Output Column              | Source Expression | Notes |
|----------------------------|-------------------|-------|
| WWI Stock Item ID          | `si.StockItemID` | Business key — used for SCD2 matching |
| Stock Item                 | `si.StockItemName` | |
| Color                      | `ISNULL(c.ColorName, 'N/A')` | LEFT JOIN to `Warehouse.Colors`; NULL → `N/A` |
| Selling Package            | `spt.PackageTypeName` | JOIN to `Warehouse.PackageTypes` on `si.UnitPackageID = spt.PackageTypeID` |
| Buying Package             | `bpt.PackageTypeName` | JOIN to `Warehouse.PackageTypes` on `si.OuterPackageID = bpt.PackageTypeID` |
| Brand                      | `ISNULL(si.Brand, 'N/A')` | NULL → `N/A` |
| Size                       | `ISNULL(si.Size, 'N/A')` | NULL → `N/A` |
| Lead Time Days             | `si.LeadTimeDays` | |
| Quantity Per Outer         | `si.QuantityPerOuter` | |
| Is Chiller Stock           | `si.IsChillerStock` | bit → boolean |
| Barcode                    | `ISNULL(si.Barcode, 'N/A')` | NULL → `N/A` |
| Tax Rate                   | `si.LeadTimeDays` | ⚠ BUG: maps LeadTimeDays, not TaxRate. Replicate as-is. |
| Unit Price                 | `si.UnitPrice` | |
| Recommended Retail Price   | `si.RecommendedRetailPrice` | Remains NULL if source is NULL |
| Typical Weight Per Unit    | `si.TypicalWeightPerUnit` | |
| Photo                      | `si.Photo` | Binary data; NULL if source is NULL |
| Valid From                 | Recalculated — see [Valid To recalculation](#valid-to-recalculation) | |
| Valid To                   | Recalculated — see [Valid To recalculation](#valid-to-recalculation) | End-of-time = `9999-12-31 23:59:59.9999999` for current row |

---

## SCD Type 2 Merge Logic

The SSIS `MigrateStagedStockItemData` procedure performs two operations inside a transaction:

### Step 1 — Close off existing rows

For every `WWI Stock Item ID` that appears in the staging data, find the current row in the dimension (where `Valid To = '9999-12-31 23:59:59.9999999'`) and set its `Valid To` to the earliest `Valid From` of the incoming changes for that business key:

```sql
WITH RowsToCloseOff AS (
    SELECT s.[WWI Stock Item ID], MIN(s.[Valid From]) AS [Valid From]
    FROM Integration.StockItem_Staging AS s
    GROUP BY s.[WWI Stock Item ID]
)
UPDATE s
    SET s.[Valid To] = rtco.[Valid From]
FROM Dimension.[Stock Item] AS s
INNER JOIN RowsToCloseOff AS rtco
    ON s.[WWI Stock Item ID] = rtco.[WWI Stock Item ID]
WHERE s.[Valid To] = '9999-12-31 23:59:59.9999999';
```

### Step 2 — Insert new rows

Insert all staging rows into the dimension:

```sql
INSERT Dimension.[Stock Item]
    ([WWI Stock Item ID], [Stock Item], Color, [Selling Package], [Buying Package],
     Brand, Size, [Lead Time Days], [Quantity Per Outer], [Is Chiller Stock],
     Barcode, [Tax Rate], [Unit Price], [Recommended Retail Price],
     [Typical Weight Per Unit], Photo, [Valid From], [Valid To], [Lineage Key])
SELECT [WWI Stock Item ID], [Stock Item], Color, [Selling Package], [Buying Package],
       Brand, Size, [Lead Time Days], [Quantity Per Outer], [Is Chiller Stock],
       Barcode, [Tax Rate], [Unit Price], [Recommended Retail Price],
       [Typical Weight Per Unit], Photo, [Valid From], [Valid To],
       @LineageKey
FROM Integration.StockItem_Staging;
```

In Delta/PySpark, this translates to a `MERGE` operation:
- **Match condition:** `WWI_Stock_Item_ID` (business key) AND target `Valid_To = '9999-12-31 23:59:59.9999999'`
- **When matched:** Update `Valid_To` to the earliest `Valid_From` of the incoming changes for that business key
- **Insert:** All incoming rows (including historical change rows within the window)

### Step 3 — Update lineage and advance cutoff

After the merge, the original `MigrateStagedStockItemData` procedure completes the audit trail inside the same transaction:

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
WHERE [Table Name] = N'Stock Item';
```

The PySpark implementation should call `complete_load(spark, lineage_key)` (from [01_prerequisites.md](01_prerequisites.md)) to perform the Delta equivalents of both updates.

---

## Watermark / Incremental Strategy

The watermark is stored in `Integration_ETL_Cutoff` (see [01_prerequisites.md](01_prerequisites.md)).

| Table_Name    | Cutoff_Time |
|---------------|-------------|
| `Stock Item`  | Last successfully loaded source-system cutoff time |

**For the initial full load**, the seed value is `2012-12-31` (from `Configuration_ReseedETL`), and `@NewCutoff` is `GETDATE() - 5 minutes` (truncated to whole seconds). This causes the extraction procedure to return **all** rows from both `Warehouse.StockItems` and `Warehouse.StockItems_Archive`.

The PySpark load reads the cutoff from the Delta table before extraction, then advances it after a successful merge — both operations are handled by the lineage helpers in `01_prerequisites`.

---

## PySpark Source Query

Since `FOR SYSTEM_TIME AS OF` is a SQL Server temporal construct that must run on the source database, the PySpark implementation should use JDBC to push the extraction query down to SQL Server. The query is equivalent to the flattened logic of `Integration.GetStockItemUpdates`:

**Option A — Call the stored procedure via JDBC** (simplest, if the procedure exists on the source):

```sql
EXEC Integration.GetStockItemUpdates @LastCutoff=?, @NewCutoff=?
```

**Option B — Inline the query** (necessary if the stored procedure doesn't exist or can't be called):

Read the change list and snapshot data in a single query that replicates the procedure's cursor-based logic. Since cursors can't be used from JDBC, the equivalent can be achieved with a set-based approach using a CTE or temp table pattern.

The implementation should decide which option to use. Either approach is acceptable as long as the output rows match.

---

## Testing

### Test Data Sourcing

When writing tests, query the following to obtain sample data:

1. **Source (OLTP):** `adventureworksltmg.database.windows.net` / `WideWorldImporters`
   - Query `Warehouse.StockItems`, `Warehouse.StockItems_Archive`, `Warehouse.Colors`, `Warehouse.PackageTypes` to get a handful of stock items with their related lookup values.
   - Pick items that cover both nullable and non-null cases for `ColorID`, `Brand`, `Size`, and `Barcode`.

2. **Destination (DW):** `adventureworksltmg.database.windows.net` / `WideWorldImportersDW`
   - Query `Dimension.[Stock Item]` for the same stock items (match by `[WWI Stock Item ID]`) to get the expected output rows.
   - These become the expected results in the unit tests.

### Test Structure

- **Input fixtures:** Hardcoded PySpark DataFrames built with `spark.createDataFrame()` using explicit schemas, representing the source table data.
- **Expected output:** Hardcoded rows matching what the destination DW contains for those same business keys.
- **Comparison:** Join on `WWI_Stock_Item_ID` + `Valid_From` (business key + SCD2 timestamp). Do **not** compare `Stock_Item_Key` (surrogate) or `Lineage_Key` (ETL metadata).
- **Coverage cases to include:**
  - A stock item with a non-null `ColorID` (should resolve to a color name)
  - A stock item with a null `ColorID` (should produce `'N/A'`)
  - A stock item with null `Brand`, `Size`, and/or `Barcode` (should produce `'N/A'`)
  - Verification that `Tax_Rate` contains `LeadTimeDays` (confirming the bug is replicated)
  - At least one item with multiple history rows to verify `Valid_To` recalculation
- **Photo column:** Exclude from comparison in tests (binary data is unwieldy for fixtures). Verify only that the column exists and has the correct type.
