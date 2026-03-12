# Copilot Instructions

## Project

Local PySpark development environment matching Microsoft Fabric Runtime 1.3
(Spark 3.5, Java 11, Python 3.11, Delta Lake 3.2).

## Stack

- **Python 3.11** — use modern syntax (type hints, `match`, `|` unions)
- **PySpark 3.5 + Delta Lake 3.2** — primary data processing framework
- **ruff** — sole linter and formatter (no black, flake8, pylint, isort)
- **pytest + pytest-cov** — testing framework
- **pre-commit** — git hook runner

## Code conventions

- Line length: 120 characters
- Source code lives in `src/spark_project/`
- Tests live in `tests/`
- Use `from __future__ import annotations` in all modules
- Imports sorted by ruff (isort-compatible)
- Follow existing `pyproject.toml` ruff rules: F, E, W, B, I, UP, S, PL

## Testing

- Mark Spark-dependent tests so they can be filtered: `pytest -m spark`
- Tests with `_int_` in the name are auto-marked as integration tests
- Target `pytest -m "not integration"` for fast local runs
- Place fixtures in `tests/conftest.py`

## PySpark patterns

- Prefer DataFrame API over SQL strings
- Use `spark.createDataFrame()` with explicit schemas in tests
- Stop SparkSessions in test fixtures (session-scoped)

## Reference

- See [Fabric Deployment Lessons Learned](fabric-deployment-lessons-learned.md) for deployment gotchas and best practices
