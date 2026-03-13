# 03 — Test SQL Connectivity

Verify SQL connectivity to an Azure SQL Database by reading the `Application.Cities` table and returning the results as a DataFrame.

> See [CONSTITUTION.md](CONSTITUTION.md) for package name, stack, and environment details.

## Connection Details

- **Server:** `adventureworksltmg.database.windows.net`
- **Database:** `wideworldimporters`
- **Driver (local only):** JDBC (`com.microsoft.sqlserver.jdbc.SQLServerDriver`)
- **Table:** `Application.Cities`

## Authentication

| Environment       | Connector                                               | Auth mechanism                                                         |
|-------------------|---------------------------------------------------------|------------------------------------------------------------------------|
| Local development | JDBC (`spark.read.jdbc(...)`)                           | `DefaultAzureCredential` → access token (`az login` required)         |
| Microsoft Fabric  | Built-in Spark SQL connector (`spark.read...mssql()`)   | Workspace identity (automatic Entra auth, no token needed)             |

The module auto-detects the runtime environment and selects the appropriate connector and auth method.

### Local
- Uses `DefaultAzureCredential` to obtain an access token scoped to `https://database.windows.net/.default`.
- Connects via JDBC with the token as an `accessToken` connection property.

### Fabric
- Uses the built-in `.mssql()` Spark SQL connector (pre-registered in Fabric runtime).
- Auth is automatic via the workspace's Entra identity — no tokens needed.
- `.mssql()` does not exist outside Fabric.
