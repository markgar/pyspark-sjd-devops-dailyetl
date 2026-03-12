# Fabric Spark Job Definition — Deployment Lessons Learned

## SJD Creation & Deployment

### Single-Step Create Silently Fails
POSTing to the `items` endpoint with `displayName` + `type` + `definition` all at once returns HTTP 202 but the definition is **never applied**. You **must** use a two-step approach:
1. `fab mkdir` to create the empty SJD item
2. `fab api -X post .../updateDefinition` to deploy the config + code

### V2 Deploy Payload Should Be Lean
The payload to `updateDefinition` should contain exactly two parts:
- `SparkJobDefinitionV1.json` (base64)
- `Main/main.py` (base64)

No `Libs/` part. The `.whl` is delivered by the attached Environment.

### `executableFile` Is a Bare Filename
Set it to `"main.py"`, not a path. The V2 payload uses `"Main/main.py"` as the part path, but the config field is just the filename.

---

## Custom Libraries (.whl)

### Custom `.whl` Libraries Must Go Through Fabric Environments
Three approaches were tried and failed:
- Putting `.whl` paths in `additionalLibraryUris` — **API rejects them** for Python SJDs
- Inlining `.whl` in the V2 payload as a `Libs/` part — **doesn't work reliably**
- Uploading `.whl` to OneLake and referencing it — **not supported**

The only working path: upload the `.whl` to a Fabric Environment, publish it, and set `environmentArtifactId` in the SJD config.

### `additionalLibraryUris` Must Be `[]`
For Python SJDs, this field must always be an empty array. Any `.whl` entry will be rejected by the API.

### Build the `.whl` with `--no-deps`
`pip wheel . -w dist/ --no-deps` builds from `pyproject.toml` without bundling dependencies. This keeps the wheel small and avoids conflicts with the Fabric Spark runtime.

### Environment-Based Deployment Enables Sharing
Multiple SJDs and notebooks can reference the same Environment GUID. Updating the library means re-uploading + re-publishing the environment once — not redeploying every SJD individually.

---

## Fabric Environments

### Binary Uploads Require `curl`, Not `fab api`
`fab api -i` only accepts JSON input. For uploading `.whl` files to an Environment (which requires `Content-Type: application/octet-stream`), you must use `curl` with a bearer token from `az account get-access-token`.

### Uploads Go to Staging — Not Effective Until Published
Uploading a `.whl` puts it in **staging**. It has no effect on running jobs until you explicitly publish the environment. This is a two-phase commit: upload, then publish.

### Environment Publish Takes Minutes
The API suggests `Retry-After: 120`. Fabric pre-installs the library during publish (equivalent to `pip install`), so expect 2+ minutes. Poll with `sleep 30` intervals.

### Only One Publish at a Time
An environment accepts only one publish operation concurrently. Check the environment status before publishing — if a publish is already in progress, the request will fail.

### Max 100 MB per `.whl` File
The Upload Custom Library API enforces a 100 MB limit per file.

### Deleting a Library Also Requires `curl`
The DELETE endpoint for staging libraries doesn't go through `fab api` either. Use `curl` with a bearer token, then publish again to make the deletion effective.

### Use `beta=false` on Environment APIs
The `?beta=false` query parameter is required on staging/library/publish endpoints. Without it, the deprecated preview contract is used.

---

## Long-Running Operations (LRO)

### Every `fab api` 202 Response Is an LRO
`updateDefinition`, environment publish, and other operations return HTTP 202 and run asynchronously. You **must** capture `x-ms-operation-id` from `--show_headers` and poll `operations/{opId}` until `Succeeded` or `Failed`. Skipping this means you won't know if the deploy actually worked.

### `fab import` Handles LRO Polling Internally; `fab api` Does Not
Built-in commands like `fab import` automatically poll and wait for completion. When using `fab api` directly for deployments or definition updates, you must poll manually.

```bash
RESPONSE=$(fab api -X post "<endpoint>" -i @payload.json --show_headers 2>&1)
OP_ID=$(echo "$RESPONSE" | grep -i "x-ms-operation-id" | awk '{print $2}' | tr -d '\r')

while true; do
  STATUS=$(fab api "operations/$OP_ID" -q status 2>&1 | tr -d '"')
  echo "Status: $STATUS"
  [[ "$STATUS" == "Running" || "$STATUS" == "NotStarted" || "$STATUS" == "Waiting" ]] || break
  sleep 5
done
```

---

## fab CLI Gotchas

### Always Use `-f` to Skip Prompts
The CLI runs non-interactively — there is no way to send keystrokes to respond to prompts. Always pass `-f` (force) on commands that support it.

---

## Logs & Debugging via Livy API

> **Note:** The Livy log retrieval endpoints below were documented from API exploration but have not been fully tested end-to-end.

### Listing Livy Sessions
After running an SJD, list its Livy sessions to get the IDs needed for log retrieval:

```bash
fab api "workspaces/$WS_ID/sparkJobDefinitions/$SJD_ID/livySessions"
```

Key fields per session: `livyId` (GUID, used in all log URLs), `sparkApplicationId` (e.g. `application_...`, needed for driver/executor logs), and `state` (`Success`, `Failed`, `Cancelled`).

### Log Types

| `type` param | `fileName` | `appId` | Contains |
|---|---|---|---|
| `livy` | *(not used)* | `none` | Livy session lifecycle, Spark submit, YARN logs |
| `driver` | `stdout` | required | `print()` output, Spark INFO messages |
| `driver` | `stderr` | required | Python exceptions, log4j, JVM stack traces |
| `rollingdriver` | *(use filenamePrefix)* | required | Rotated driver logs for long jobs |
| `executor` | *(use filenamePrefix)* | required | Executor-level logs (distributed tasks) |

All log URLs follow this base pattern:

```
https://api.fabric.microsoft.com/v1/workspaces/{wsId}/sparkJobDefinitions/{sjdId}/livySessions/{livyId}/applications/{appId}/logs?type={type}&fileName={file}
```

### `fab api` Can't Fetch Raw Text Logs
Log **metadata** (`&meta=true`) returns JSON and works with `fab api`. Log **content** returns raw text — `fab api` chokes with a JSON parse error. Use `curl` with a bearer token instead:

```bash
TOKEN=$(az account get-access-token \
  --resource "https://analysis.windows.net/powerbi/api" \
  --query accessToken -o tsv)

# Livy session log (use appId "none")
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.fabric.microsoft.com/v1/workspaces/$WS_ID/sparkJobDefinitions/$SJD_ID/livySessions/$LIVY_ID/applications/none/logs?type=livy"

# Driver stdout (your print() output)
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.fabric.microsoft.com/v1/workspaces/$WS_ID/sparkJobDefinitions/$SJD_ID/livySessions/$LIVY_ID/applications/$APP_ID/logs?type=driver&fileName=stdout&isDownload=true"

# Driver stderr (Python tracebacks, JVM stack traces)
curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://api.fabric.microsoft.com/v1/workspaces/$WS_ID/sparkJobDefinitions/$SJD_ID/livySessions/$LIVY_ID/applications/$APP_ID/logs?type=driver&fileName=stderr&isDownload=true"
```

For partial reads, add `&isPartial=true&offset=0&size=10000` (byte offsets).

### Livy Logs Are Always Available; Driver Logs May Not Be
Driver logs require a valid `sparkApplicationId`. For very short-lived or quickly-failed jobs, driver logs may 404 while the livy session log is still accessible. The livy log contains the Spark submit process output, which often includes the root cause of failures. **Always check the livy log first.**

### Rolling Driver Logs for Long Jobs
Long-running jobs rotate log files. List them by prefix:

```bash
fab api "workspaces/$WS_ID/sparkJobDefinitions/$SJD_ID/livySessions/$LIVY_ID/applications/$APP_ID/logs?type=rollingdriver&meta=true&filenamePrefix=stderr"
```

---

## Code Compatibility

### Never Use `mssparkutils` / `notebookutils` in SJDs
These Fabric-only APIs are unavailable in Spark Job Definitions. Use `DefaultAzureCredential` for auth and environment variables for configuration so the same code runs locally and in Fabric with zero changes.
