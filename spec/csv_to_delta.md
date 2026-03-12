# Module: CSV to Delta

## Description

Read the CSV output produced by the People to CSV job and write it to a Delta table called `people`.

## Input

- Format: CSV with header row
- Source path is passed as a parameter (same path used as output by the People to CSV job)

## Output

- Format: Delta table
- Table name: `people`
- Write mode: overwrite

## Module

- **File:** `src/spark_project/csv_to_delta.py`
- **Entry point:** `run(spark, csv_path)` function
- Helper functions:
  - `read_people_csv(spark, csv_path)` — reads the CSV into a DataFrame
  - `write_people_delta(df)` — writes the DataFrame to the `people` Delta table
