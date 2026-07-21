# OCP Evaluations Makefile

.PHONY: help install install-uv clean eval test test-cluster-updates test-cluster-updates-ci test-cov test-critical test-mark format lint typecheck all

# Provider filter (openai, google_vertex, google_vertex_anthropic, watsonx)
PROVIDER ?=

# Default target
help:
	@echo "OCP Evaluations - Available targets:"
	@echo ""
	@echo "Installation:"
	@echo "  make install                - Install dependencies (pip)"
	@echo "  make install-uv             - Install dependencies (uv - recommended)"
	@echo "  make install-dev            - Install development dependencies"
	@echo ""
	@echo "Evaluations:"
	@echo "  make eval                   - Run evaluations (use TAGS= or CONV_IDS= to filter)"
	@echo ""
	@echo "Testing:"
	@echo "  make test                   - Run all tests"
	@echo "  make test-cluster-updates   - Run cluster-updates tests (all providers or PROVIDER=<name>)"
	@echo "  make test-cluster-updates-ci- Run cluster-updates tests (full CI/CD flow)"
	@echo "  make test-cov               - Run tests with coverage report"
	@echo "  make test-critical          - Run only critical tests"
	@echo "  make test-mark MARK=<name>  - Run tests with specific marker"
	@echo ""
	@echo "Code Quality:"
	@echo "  make format                 - Format code with black"
	@echo "  make lint                   - Run linters (ruff)"
	@echo "  make typecheck              - Run type checker (mypy)"
	@echo "  make all                    - Format, lint, typecheck, and test"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                  - Clean output and cache files"
	@echo "  make clean-cache            - Clear evaluation caches only"
	@echo ""
	@echo "Examples:"
	@echo "  make eval TAGS='cluster-updates-critical'    # Run specific tag"
	@echo "  make eval CONV_IDS='pre_upgrade_check'       # Run specific conversation"
	@echo "  make test-cluster-updates                    # Run cluster updates tests"
	@echo "  make test-mark MARK='cluster_updates'        # Run tests with marker"
	@echo "  PROVIDER=openai make test-cluster-updates     # Run single provider"
	@echo ""

# Install dependencies
install:
	@echo "Installing dependencies..."
	pip install -r requirements.txt
	@echo "Installation complete!"

# Install dependencies using uv (recommended, matches lightspeed-service)
install-uv:
	@echo "Installing dependencies with uv..."
	@if ! command -v uv &> /dev/null; then \
		echo "uv not found. Installing uv..."; \
		pip install uv; \
	fi
	uv sync --extra lseval
	@echo "Installation complete (uv)!"

# Install development dependencies
install-dev:
	@echo "Installing development dependencies..."
	pip install -r requirements.txt
	pip install -e ".[dev]"
	@echo "Development installation complete!"

# Install development dependencies using uv
install-dev-uv:
	@echo "Installing development dependencies with uv..."
	@if ! command -v uv &> /dev/null; then \
		echo "uv not found. Installing uv..."; \
		pip install uv; \
	fi
	uv sync --extra lseval --extra dev
	@echo "Development installation complete (uv)!"

# Run evaluations
eval:
	@echo "Running evaluations..."
ifdef TAGS
	@echo "Filtering by tags: $(TAGS)"
	lightspeed-eval --system-config config/system.yaml \
		--eval-data config/evaluation_data.yaml \
		--output-dir eval_output \
		--tags $(TAGS)
else ifdef CONV_IDS
	@echo "Filtering by conversation IDs: $(CONV_IDS)"
	lightspeed-eval --system-config config/system.yaml \
		--eval-data config/evaluation_data.yaml \
		--output-dir eval_output \
		--conv-ids $(CONV_IDS)
else
	lightspeed-eval --system-config config/system.yaml \
		--eval-data config/evaluation_data.yaml \
		--output-dir eval_output
endif
	@echo "Evaluation complete! Results in eval_output/"

# Run evaluation with cache warmup (rebuild caches)
eval-warmup:
	@echo "Running evaluations with cache warmup..."
	lightspeed-eval --system-config config/system.yaml \
		--eval-data config/evaluation_data.yaml \
		--output-dir eval_output \
		--cache-warmup

# Run all tests
test:
	@echo "Running all tests..."
	pytest tests/ -v
	@echo "Tests complete!"

# Run cluster-updates specific tests (supports PROVIDER= to filter to a single provider)
test-cluster-updates:
	@echo "Running cluster-updates evaluation tests..."
	@if [ -n "$(PROVIDER)" ]; then echo "Provider: $(PROVIDER)"; fi
	@mkdir -p test_results
	PROVIDER=$(PROVIDER) pytest tests/e2e/evaluation -vv -s -m cluster_updates \
		--junit-xml=test_results/junit_e2e_cluster_updates.xml
	@echo "Cluster-updates tests complete!"
	@echo "Results: test_results/junit_e2e_cluster_updates.xml"

# Run cluster-updates tests via orchestration script (full CI/CD flow)
test-cluster-updates-ci:
	@echo "Running cluster-updates tests (CI mode)..."
	./tests/scripts/test-cluster-updates.sh --artifact-dir test_results
	@echo "CI tests complete!"

# Run tests with coverage
test-cov:
	@echo "Running tests with coverage..."
	pytest tests/ -v --cov=. --cov-report=term-missing --cov-report=html
	@echo "Tests complete! Coverage report: htmlcov/index.html"

# Run only critical tests
test-critical:
	@echo "Running critical tests only..."
	pytest tests/ -v -m critical
	@echo "Critical tests complete!"

# Run tests with specific markers
test-mark:
	@echo "Running tests with marker: $(MARK)"
	pytest tests/ -v -m $(MARK)
	@echo "Tests complete!"

# Format code
format:
	@echo "Formatting code with black..."
	black . --exclude venv
	@echo "Formatting complete!"

# Run linters
lint:
	@echo "Running linters..."
	ruff check .
	@echo "Linting complete!"

# Type checking
typecheck:
	@echo "Running type checker..."
	mypy . --exclude venv
	@echo "Type checking complete!"

# Clean output and cache files
clean:
	@echo "Cleaning output and cache files..."
	rm -rf eval_output/*
	rm -rf .caches/*
	rm -rf .pytest_cache
	rm -rf .mypy_cache
	rm -rf .ruff_cache
	rm -rf **/__pycache__
	rm -rf *.egg-info
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "Clean complete!"

# Clear evaluation caches only
clean-cache:
	@echo "Clearing evaluation caches..."
	rm -rf .caches/*
	@echo "Cache cleared!"

# Run all quality checks
all: format lint typecheck test
	@echo "All checks complete!"

# Quick eval for smoke testing (just a few scenarios)
smoke-test:
	@echo "Running smoke test with basic scenarios..."
	lightspeed-eval --system-config config/system.yaml \
		--eval-data config/evaluation_data.yaml \
		--output-dir eval_output \
		--tags cluster-updates-critical
	@echo "Smoke test complete!"
