# Module: Test SQL Connectivity

## Description

Verify JDBC connectivity to an Azure SQL Database by running a simple query and returning the results as a DataFrame.

## Connection Details

- **Server:** `adventureworksltmg.database.windows.net`
- **Database:** `wideworldimporters`
- **Driver:** JDBC (SQL Server / `com.microsoft.sqlserver.jdbc.SQLServerDriver`)

## Authentication

| Environment       | Method                                                                 |
|-------------------|------------------------------------------------------------------------|
| Local development | Azure AD credentials of the logged-in developer (`DefaultAzureCredential` / interactive) |
| Microsoft Fabric  | Workspace identity (managed identity)                                  |

The module should detect the runtime environment and select the appropriate authentication method automatically.

## Module

- **File:** `src/spark_project/test_sql_connectivity.py`
- **Entry point:** `run(spark)` function
- Helper functions:
  - `get_jdbc_url()` — builds the JDBC connection URL
  - `get_jdbc_properties(spark)` — returns JDBC connection properties with the appropriate auth token
  - `read_test_query(spark)` — executes a simple test query (e.g., `SELECT 1 AS connected`) and returns the result DataFrame
