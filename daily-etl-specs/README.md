# Daily ETL Specs

Ground-truth specifications for migrating the WideWorldImporters DailyETL from SSIS to native PySpark on Microsoft Fabric.

## What it migrates

The original `DailyETLMain.dtsx` SSIS package performs incremental loads from the `WideWorldImporters` OLTP database into the `WideWorldImportersDW` data warehouse. Each spec below documents one dimension or fact table load — what the SSIS package does today — so a build agent can reimplement it as pure PySpark writing to a Fabric Lakehouse.

## Specs

Implement in order — each spec builds on the previous.

| File | Description |
|---|---|
| `CONSTITUTION.md` | Package name, stack, connections, auth, Fabric targets, testing strategy — shared across all specs |
| `01_prerequisites.md` | Lineage table, ETL cutoff table, seed data, cutoff time calculation — must be done first |
| `02_payment_method_dimension.md` | Payment Method dimension — SCD Type 2 load from OLTP to Lakehouse |
| `03_transaction_type_dimension.md` | Transaction Type dimension — SCD Type 2 load from OLTP to Lakehouse |
| `04_stock_item_dimension.md` | Stock Item dimension — SCD Type 2 load from OLTP to Lakehouse |

## How to use

Select **sjd-builder** from the Copilot chat mode dropdown, then hand it specs one at a time:

```
implement daily-etl-specs/01_stock_item_dimension.md
```

Or point it at the whole directory to build everything in order:

```
implement the spec in daily-etl-specs/
```

The agent reads `CONSTITUTION.md` for project-level facts, then works through the numbered specs in order.

## Reference materials

- **Source OLTP:** `.bacpac/WideWorldImportersOLTP-Standard.bacpac`
- **Destination DW:** `.bacpac/WideWorldImportersDW-Standard.bacpac`
- **SSIS package:** `.ispac/DailyETLMain.dtsx`
