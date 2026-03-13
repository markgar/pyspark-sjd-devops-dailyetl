# How local/Fabric branching works

Same code runs in both environments. Only 3–4 narrow branch points separate local from Fabric:

| Concern | Local | Fabric | Bridge |
|---|---|---|---|
| Detection | `LOCAL_DEV=1` | not set | `is_local_dev()` |
| File paths | `lakehouse/Files/…` | `Files/…` | `LAKEHOUSE_ROOT` env var |
| Spark + Delta | `local[*]` + `configure_spark_with_delta_pip()` | Managed cluster | Conditional setup in `main.py` |
| Auth | `az login` → `DefaultAzureCredential` | Managed Identity | Same code path |
| SQL | JDBC + access token | `.mssql()` + workspace identity | `is_local_dev()` branch |
| Libraries | `pip install -e .` | `.whl` via Fabric Environments | `environmentArtifactId` |
