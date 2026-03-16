# SSIS-to-Spec Gap Analysis — Three Dimensions

Comparison of `DailyETLMain.dtsx` against the specs in `daily-etl-specs/` for the
Payment Method, Transaction Type, and Stock Item dimensions.

## Sources Inspected

| Source | What was checked |
|--------|-----------------|
| `.ispac/DailyETLMain.dtsx` | Full package: execution order, precedence constraints, all SQL tasks, data flow components, variable bindings, parameter mappings, column output schemas |
| `.bacpac/WideWorldImportersOLTP-Standard.bacpac` | Source tables (`Application.PaymentMethods`, `Application.TransactionTypes`, `Warehouse.StockItems`, `Warehouse.Colors`, `Warehouse.PackageTypes`) and extraction stored procedures (`Integration.Get*Updates`) |
| `.bacpac/WideWorldImportersDW-Standard.bacpac` | Destination dimension tables, staging tables, infrastructure tables (`Integration.Lineage`, `Integration.ETL Cutoff`), merge procedures (`Integration.MigrateStaged*Data`), lineage procedures (`GetLineageKey`, `GetLastETLCutoffTime`), and the `Configuration_ReseedETL` seed procedure |

---

## Overall Verdict

The specs are thorough and accurate. Every SSIS task, stored procedure, column mapping,
SCD2 merge operation, and lineage workflow for these three dimensions has a corresponding
and correct entry in the specs. **One inconsistency** was found in the prerequisites spec
(detailed below), and a handful of minor clarification items are noted.

---

## 01_prerequisites.md

### Covered correctly

- **ETL cutoff time calculation** — The SSIS expressions `DATEADD("Minute", -5, GETDATE())`
  and the millisecond-trim step match the spec's Python equivalent
  (`datetime.utcnow() - timedelta(minutes=5)` with `replace(microsecond=0)`). Verified
  against the actual SSIS expression tasks.
- **`Integration.Lineage` table** — Schema matches the DW bacpac exactly (6 columns,
  `Lineage Key` PK with sequence default, nullable `Data Load Completed`).
- **`Integration.ETL Cutoff` table** — Schema matches (2 columns, `Table Name` PK).
- **`GetLineageKey` behavior** — The DW procedure inserts a row with `Was_Successful = 0`
  and `Data_Load_Completed = NULL`, then returns the new key. Spec matches.
- **`GetLastETLCutoffTime` behavior** — Reads `Cutoff Time` for a given table name;
  throws if not found. Spec matches.
- **Seed cutoff values** — All three rows (`Payment Method`, `Transaction Type`,
  `Stock Item`) seeded at `2012-12-31`. Matches `Configuration_ReseedETL` which uses
  `@StartingETLCutoffTime = '20121231'`.
- **Unknown dimension seed rows** — All three seed INSERT statements match
  `Configuration_ReseedETL` exactly (column lists, values, sentinel ID = 0,
  `Valid From = 2013-01-01`, `Valid To = 9999-12-31 23:59:59.9999999`).
- **Date Dimension** — Correctly documented as out of scope. Confirmed that none of the
  three target dimensions join to or depend on `Dimension.Date`.

### Issue found

**The "PySpark Implementation Notes" section is incomplete.** The initialization function
summary at the bottom of the spec says:

> 1. Create `Integration_Lineage` Delta table if it doesn't exist
> 2. Create `Integration_ETL_Cutoff` Delta table if it doesn't exist; seed with the
>    initial cutoff row for `'Stock Item'`
> 3. Create `Dimension_Stock_Item` Delta table if it doesn't exist; insert the
>    "Unknown" seed row

This only mentions **Stock Item**. The seed data tables earlier in the same document
correctly list all three dimensions, and the seed INSERT statements cover all three,
but the implementation notes omit Payment Method and Transaction Type. A developer
following only the implementation notes would miss:

- Seeding `Integration_ETL_Cutoff` rows for `'Payment Method'` and
  `'Transaction Type'`
- Creating and seeding `Dimension_Payment_Method` and `Dimension_Transaction_Type`
  with their "Unknown" rows

**Recommendation:** Update the initialization function summary to cover all three
dimensions, e.g.:

> 1. Create `Integration_Lineage` Delta table if it doesn't exist
> 2. Create `Integration_ETL_Cutoff` Delta table if it doesn't exist; seed with
>    initial cutoff rows for `'Payment Method'`, `'Transaction Type'`, and
>    `'Stock Item'`
> 3. Create `Dimension_Payment_Method` if it doesn't exist; insert seed row
> 4. Create `Dimension_Transaction_Type` if it doesn't exist; insert seed row
> 5. Create `Dimension_Stock_Item` if it doesn't exist; insert seed row

---

## 02_payment_method_dimension.md

### Covered correctly — no gaps found

| Aspect | SSIS Package | Spec | Match? |
|--------|-------------|------|--------|
| Inner execution order | Set TableName → Get Lineage Key → Truncate Staging → Get Last Cutoff → Extract → Migrate | Same 6-step sequence documented | Yes |
| Source connection | `WWI_Source_DB` (OLTP) | "calls … on the **OLTP** database" | Yes |
| Extraction procedure | `EXEC Integration.GetPaymentMethodUpdates ?, ?` | Full procedure body reproduced | Yes |
| Change detection | UNION ALL of `PaymentMethods` + `PaymentMethods_Archive` where `ValidFrom` in `(@LastCutoff, @NewCutoff]` | Matches | Yes |
| Point-in-time snapshot | `FOR SYSTEM_TIME AS OF @ValidFrom` per cursor row | Matches | Yes |
| Valid To recalculation | COALESCE of next `Valid From` for same business key, else end-of-time | Matches | Yes |
| Output columns | 4 columns: WWI Payment Method ID, Payment Method, Valid From, Valid To | Matches SSIS RESULT SETS and DW staging/dimension schemas | Yes |
| Staging schema | 5 columns (incl. staging key) — all NOT NULL | Matches DW bacpac | Yes |
| Destination schema | 6 columns (incl. surrogate key + lineage key, both omitted in Delta) | Matches DW bacpac | Yes |
| SCD2 merge | Close-off current rows (set `Valid To`), then INSERT all staging rows | `MigrateStagedPaymentMethodData` body matches exactly | Yes |
| Lineage/cutoff updates | Update Lineage `Was Successful = 1`, advance ETL Cutoff | Procedure body matches | Yes |
| NULL replacements | None needed (no nullable business columns) | Spec says "No NULL replacement needed" | Yes |

---

## 03_transaction_type_dimension.md

### Covered correctly — no gaps found

| Aspect | SSIS Package | Spec | Match? |
|--------|-------------|------|--------|
| Inner execution order | Set TableName → Get Lineage Key → Truncate Staging → Get Last Cutoff → Extract → Migrate | Same 6-step sequence documented | Yes |
| Source connection | `WWI_Source_DB` (OLTP) | "calls … on the **OLTP** database" | Yes |
| Extraction procedure | `EXEC Integration.GetTransactionTypeUpdates ?, ?` | Full procedure body reproduced | Yes |
| Change detection | UNION ALL of `TransactionTypes` + `TransactionTypes_Archive` | Matches | Yes |
| Point-in-time snapshot | `FOR SYSTEM_TIME AS OF @ValidFrom` | Matches | Yes |
| Valid To recalculation | Same COALESCE pattern | Matches | Yes |
| Output columns | 4 columns: WWI Transaction Type ID, Transaction Type, Valid From, Valid To | Matches | Yes |
| Staging schema | 5 columns | Matches DW bacpac | Yes |
| Destination schema | 6 columns (surrogate key + lineage key omitted in Delta) | Matches | Yes |
| SCD2 merge | Close-off + INSERT | `MigrateStagedTransactionTypeData` body matches | Yes |
| Lineage/cutoff updates | Same pattern | Matches | Yes |
| NULL replacements | None needed | Spec says "No NULL replacement needed" | Yes |

---

## 04_stock_item_dimension.md

### Covered correctly — no gaps found

| Aspect | SSIS Package | Spec | Match? |
|--------|-------------|------|--------|
| Inner execution order | Set TableName → Get Lineage Key → Truncate Staging → Get Last Cutoff → Extract → Migrate | Same 6-step sequence | Yes |
| Source tables | `Warehouse.StockItems` + `_Archive`, `Warehouse.Colors`, `Warehouse.PackageTypes` | All four tables documented with column schemas | Yes |
| Change detection scope | Only `StockItems` + `StockItems_Archive` (NOT Colors/PackageTypes changes) | Spec's change detection SQL matches — only checks StockItems | Yes |
| Point-in-time joins | `FOR SYSTEM_TIME AS OF @ValidFrom` across StockItems, PackageTypes (×2), Colors | Matches exactly, including the LEFT OUTER JOIN for Colors | Yes |
| LeadTimeDays → Tax Rate bug | `si.LeadTimeDays` appears twice in SELECT list — once for `[Lead Time Days]`, once for `[Tax Rate]` | Bug documented with "replicate as-is" guidance | Yes |
| NULL replacements | `ISNULL` applied to Color, Brand, Size, Barcode → `'N/A'` in the final SELECT | All four columns documented with correct defaults | Yes |
| Valid To recalculation | Same COALESCE pattern | Matches | Yes |
| Output columns | 18 columns in SSIS RESULT SETS | All 18 mapped in the spec's column mapping table | Yes |
| Data types | `decimal(18,3)` for Tax Rate/Typical Weight, `decimal(18,2)` for Unit Price/RRP, `varbinary(max)` for Photo | All match DW bacpac and SSIS output schema | Yes |
| Staging schema | 19 columns (incl. staging key) | Matches DW bacpac exactly | Yes |
| Destination schema | 20 columns (surrogate key + lineage key omitted in Delta) | Matches DW bacpac | Yes |
| SCD2 merge | Close-off + INSERT of all 18 content columns | `MigrateStagedStockItemData` body matches | Yes |
| Lineage/cutoff updates | Same pattern | Matches | Yes |

---

## Prerequisites for These Three Dimensions — Nothing Missing

The SSIS package runs three tasks before any dimension load:

| # | SSIS Task | Required for these 3 dimensions? | In specs? |
|---|-----------|----------------------------------|-----------|
| 1 | Calculate ETL Cutoff Time backup | Yes | 01_prerequisites.md — ETL Cutoff Time Calculation |
| 2 | Trim Any Milliseconds | Yes | 01_prerequisites.md — same section |
| 3 | Ensure Date Dimension includes current year | No — none of the three dimensions join to `Dimension.Date` | 01_prerequisites.md — documented as out of scope |

The SSIS execution order also loads City, Customer, and Employee dimensions before
Payment Method. These are **not** data dependencies — they happen to run first due to
the serial ETL design, but the three target dimensions read from entirely separate
source tables and write to separate destination tables. No cross-dimension prerequisites
are missing.

---

## Summary

| Spec | Status | Action needed |
|------|--------|---------------|
| 01_prerequisites.md | One inconsistency | Update the "PySpark Implementation Notes" section to list all three dimensions (not just Stock Item) in the initialization function |
| 02_payment_method_dimension.md | Complete | None |
| 03_transaction_type_dimension.md | Complete | None |
| 04_stock_item_dimension.md | Complete | None |
