# OCP Evaluation Tests

This directory contains automated tests for the OCP multi-domain evaluation suite.

## Structure

```
tests/
├── __init__.py
├── conftest.py                          # Pytest configuration
├── README.md                            # This file
└── e2e/                                 # End-to-end tests
    └── evaluation/
        ├── __init__.py
        └── test_cluster_updates.py      # Main evaluation tests
```

## Running Tests

### Install Dependencies

First, ensure you have the required dependencies installed:

```bash
# Install framework dependencies
make install

# Install development dependencies (pytest, black, ruff, mypy)
make install-dev
```

### Run All Tests

```bash
make test
```

### Run Tests with Coverage

```bash
make test-cov
```

This generates an HTML coverage report at `htmlcov/index.html`.

### Run Only Critical Tests

```bash
make test-critical
```

### Run Tests with Specific Markers

```bash
make test-mark MARK=cluster_updates
```

### Run Tests Directly with pytest

```bash
# Run all tests
pytest tests/ -v

# Run specific test file
pytest tests/e2e/evaluation/test_cluster_updates.py -v

# Run specific test function
pytest tests/e2e/evaluation/test_cluster_updates.py::test_cluster_updates -v

# Run tests with markers
pytest tests/ -v -m critical
pytest tests/ -v -m cluster_updates
```

## Test Markers

- `@pytest.mark.cluster_updates`: Marks tests that run cluster updates evaluations
- `@pytest.mark.critical`: Marks tests that run only critical evaluation scenarios

## Environment Variables

Tests require the following environment variables:

### Required

- `OPENAI_API_KEY`: OpenAI API key for the judge LLM (GPT-4o)

### Optional

- `API_BASE_URL`: Override the API base URL (from config/system.yaml)
- `API_KEY`: API authentication token (if API is enabled)

Example:

```bash
export OPENAI_API_KEY="sk-..."
export API_KEY=$(oc create token ocp-eval-user -n openshift-lightspeed --duration=24h)
make test
```

## Test Structure

### test_cluster_updates.py

Contains end-to-end tests that run the lightspeed-eval framework:

1. **test_cluster_updates**: Runs all evaluation scenarios (matches lightspeed-service pattern)
2. **test_cluster_updates_critical_only**: Runs only scenarios tagged as critical

Both tests:
- Load system configuration from `config/system.yaml`
- Load evaluation data from `config/evaluation_data.yaml`
- Run the evaluation framework
- Assert that all evaluations complete without errors
- Verify that output artifacts (CSV and JSON) are generated

## Writing New Tests

To add new test scenarios:

1. **Add evaluation data** in `config/evaluation_data.yaml`
2. **Run the test** to validate the scenario:
   ```bash
   pytest tests/e2e/evaluation/test_cluster_updates.py -v
   ```

To add new test functions:

1. **Create a new test function** in `test_cluster_updates.py`
2. **Use pytest markers** to categorize the test:
   ```python
   @pytest.mark.cluster_updates
   @pytest.mark.critical
   def test_my_new_scenario(tmp_path: Path) -> None:
       """Test description."""
       # Test implementation
   ```
3. **Follow the pattern** of calling `_run_lseval()` with appropriate parameters

## Troubleshooting

### ModuleNotFoundError: No module named 'lightspeed_evaluation'

Install the framework:
```bash
pip install -r requirements.txt
```

### RuntimeError: OPENAI_API_KEY environment variable is required

Export your OpenAI API key:
```bash
export OPENAI_API_KEY="sk-..."
```

### PermissionError: Output directory is not writable

Ensure you have write permissions in the test output directory. The tests use `tmp_path` fixture which should always be writable.

### Evaluation errors (ERROR > 0)

Check the test output for specific evaluation errors. Common causes:
- API connection issues
- Invalid evaluation data format
- Judge LLM API key issues
- Malformed expected responses

## CI/CD Integration

These tests are designed to run in CI/CD pipelines. Ensure the following in your CI configuration:

1. Install dependencies: `pip install -r requirements.txt`
2. Install dev dependencies: `pip install -e ".[dev]"`
3. Set `OPENAI_API_KEY` secret
4. Run tests: `make test` or `pytest tests/ -v`
5. Collect artifacts from test output directories

## Additional Resources

- [LightSpeed Evaluation Framework](https://github.com/lightspeed-core/lightspeed-evaluation)
- [pytest Documentation](https://docs.pytest.org/)
- [Coverage.py Documentation](https://coverage.readthedocs.io/)
