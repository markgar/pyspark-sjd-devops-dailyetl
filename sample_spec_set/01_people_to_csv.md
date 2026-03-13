# 01 — People to CSV

Generate imaginary person data and write it to a CSV file.

> See [CONSTITUTION.md](CONSTITUTION.md) for package name, stack, and environment details.

## Data Schema

| Column       | Type    | Nullable |
|--------------|---------|----------|
| `id`         | integer | no       |
| `first_name` | string  | no       |
| `last_name`  | string  | no       |
| `email`      | string  | no       |
| `age`        | integer | no       |
| `city`       | string  | no       |

## Hardcoded Data

~10 rows of imaginary person data defined directly in the source code (no external files or APIs).

## Output

- Format: CSV with header row
- File name: `people`
- Write mode: overwrite

