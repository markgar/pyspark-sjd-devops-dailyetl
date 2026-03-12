# Module: People to CSV

## Description

Create a DataFrame from hardcoded imaginary person data and write it to a CSV file.

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

The job should contain ~10 rows of imaginary person data defined directly in the source code (no external files or APIs).

## Output

- Format: CSV with header row
- Write mode: overwrite
- Coalesce to a single output file
- Output path is passed as a parameter

## Module

- **File:** `src/spark_project/people_to_csv.py`
- **Entry point:** `run(spark, output_path)` function
- Helper functions:
  - `create_people_df(spark)` — builds and returns the DataFrame
  - `write_people_csv(df, output_path)` — writes the DataFrame to CSV
