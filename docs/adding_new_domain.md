# Adding a New Evaluation Domain

This guide walks through every step needed to add a new OCP evaluation domain to ocp-evals. The existing **cluster-updates** domain serves as the reference implementation — each step below links to the corresponding cluster-updates file.

Throughout this guide, a fictional **networking** domain is used as the running example.

## Prerequisites

- Familiarity with the [LightSpeed Evaluation Framework](https://github.com/lightspeed-core/lightspeed-evaluation)
- Understanding of the evaluation data format (conversation groups, turns, metrics)
- Access to an OpenShift cluster for testing

## Checklist

### Step 1: Add evaluation data

**File:** `config/evaluation_data.yaml`

Append your conversation groups to the shared evaluation data file. All domains coexist in this single file — **tags** are the organizational mechanism.

```yaml
- conversation_group_id: net_001
  tag: networking-critical
  turns:
  - turn_id: turn_001
    query: "Pods in namespace foo cannot reach pods in namespace bar over port 8080"
    expected_response: |
      Diagnostic steps for pod-to-pod connectivity failure...
    turn_metrics:
      - custom:answer_correctness
      - geval:technical_accuracy
```

**Tag naming convention:**

- Always prefix with your domain name: `networking-critical`, `networking-dns`, `networking-ingress`
- Include a `-critical` tag for the scenarios that CI should run by default (the smoke-test tier)
- Use descriptive suffixes for subcategories

**Reference:** See the `cluster-updates-*` tags in `config/evaluation_data.yaml` for examples.

### Step 2: Add domain-specific metrics (optional)

**Files:** `config/system.yaml`, `config/system_watsonx.yaml`, `config/system_google_vertex.yaml`, `config/system_google_vertex_anthropic.yaml`

If your domain needs custom evaluation criteria beyond `custom:answer_correctness`, add GEval metrics to the `metrics_metadata.turn_level` section.

```yaml
metrics_metadata:
  turn_level:
    "geval:network_diagnosis_accuracy":
      threshold: 0.85
      description: "Validates correct network troubleshooting steps"
      default: false
      criteria: |
        Evaluate whether the response correctly identifies the network issue
        and provides appropriate diagnostic commands (oc get pods, oc logs,
        oc debug, etc.) for the given scenario.
        Score 1.0 if all diagnostic steps are correct and complete.
        Score 0.0 if the diagnosis is wrong or missing key steps.
      evaluation_params: [query, response, expected_response]
```

**Important:** Metrics are duplicated across all four system config files. Add your metric to each one. The shared fields (`llm`, `output`, `visualization`, `environment`, `logging`) are identical across configs — only `api` and `metrics_metadata` differ.

**Reference:** See `geval:condition_status_accuracy` and `geval:technical_accuracy` in `config/system.yaml`.

### Step 3: Register the pytest marker

**Files:** `pytest.ini`, `tests/conftest.py`

Add your domain marker in both locations.

**pytest.ini** — add under the `markers` key:

```ini
markers =
    cluster_updates: mark test as a cluster updates evaluation test
    networking: mark test as a networking evaluation test
```

**tests/conftest.py** — add a new `addinivalue_line` call:

```python
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers",
        "cluster_updates: mark test as a cluster updates evaluation test",
    )
    config.addinivalue_line(
        "markers",
        "networking: mark test as a networking evaluation test",
    )
```

### Step 4: Create the test file

**File:** `tests/e2e/evaluation/test_<domain>.py`

Create a test file following the `test_cluster_updates.py` pattern. The key structure:

```python
"""Networking evaluation tests across multiple LLM providers."""

import csv
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest
import yaml

MAX_EVAL_ERROR_RATE_PCT = 15.0

_NETWORKING_PROVIDERS = (
    "openai",
    "google_vertex",
    "google_vertex_anthropic",
    "watsonx",
)

PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
CONFIG_DIR = PROJECT_ROOT / "config"
EVAL_DATA = CONFIG_DIR / "evaluation_data.yaml"

_PROVIDER_CONFIGS: dict[str, Path] = {
    "openai": CONFIG_DIR / "system.yaml",
    "google_vertex": CONFIG_DIR / "system_google_vertex.yaml",
    "google_vertex_anthropic": CONFIG_DIR / "system_google_vertex_anthropic.yaml",
    "watsonx": CONFIG_DIR / "system_watsonx.yaml",
}


def _skip_reason_for_provider(provider: str) -> str | None:
    """Return a skip reason when this provider should not run, else None."""
    cluster_raw = os.getenv("PROVIDER", "").strip()
    if not cluster_raw:
        return None
    cluster_providers = {p.strip() for p in cluster_raw.split() if p.strip()}
    if len(cluster_providers) != 1:
        return None
    only = next(iter(cluster_providers))
    if provider != only:
        return f"PROVIDER={only!r} on cluster; skipping networking for {provider!r}"
    return None


def _load_tags(prefix: str) -> list[str]:
    """Return sorted unique tags matching the domain prefix."""
    with open(EVAL_DATA, encoding="utf-8") as fh:
        eval_data = yaml.safe_load(fh)
    if not isinstance(eval_data, list):
        raise ValueError("Evaluation data should be a list of conversation groups")
    return sorted({
        conv["tag"] for conv in eval_data
        if "tag" in conv and conv["tag"].startswith(prefix)
    })


_EVAL_TAGS = _load_tags("networking-")


# Copy _ensure_lseval_installed, _resolve_api_url, _get_api_token,
# and _run_lseval from test_cluster_updates.py — they are identical.
# ...


@pytest.mark.networking
@pytest.mark.parametrize("tag", _EVAL_TAGS)
@pytest.mark.parametrize("provider", _NETWORKING_PROVIDERS)
def test_networking(tmp_path: Path, provider: str, tag: str) -> None:
    """Run networking eval for a single tag and provider."""
    if reason := _skip_reason_for_provider(provider):
        pytest.skip(reason)

    with open(EVAL_DATA, encoding="utf-8") as fh:
        eval_data = yaml.safe_load(fh)

    conversations = [conv for conv in eval_data if conv.get("tag") == tag]
    if not conversations:
        pytest.skip(f"No conversations with tag {tag!r}")

    tmp_eval_data = tmp_path / f"eval_data_{tag}.yaml"
    with open(tmp_eval_data, "w", encoding="utf-8") as fh:
        yaml.dump(conversations, fh)

    out_dir = tmp_path / tag / provider
    _run_lseval(tmp_eval_data, out_dir, _PROVIDER_CONFIGS[provider])
```

**Key differences from the template:**

- `_NETWORKING_PROVIDERS` — you can use a subset of providers if not all are relevant
- `_load_tags("networking-")` — filters tags to your domain's prefix only
- `@pytest.mark.networking` — uses your registered marker
- The test function name matches your domain: `test_networking`

**Reference:** `tests/e2e/evaluation/test_cluster_updates.py`

### Step 5: Add Makefile targets

**File:** `Makefile`

Add two targets and update the `.PHONY` line:

```makefile
# Run networking-specific tests (supports PROVIDER= to filter to a single provider)
test-networking:
	@echo "Running networking evaluation tests..."
	@if [ -n "$(PROVIDER)" ]; then echo "Provider: $(PROVIDER)"; fi
	@mkdir -p test_results
	PROVIDER=$(PROVIDER) pytest tests/e2e/evaluation -vv -s -m networking \
		--junit-xml=test_results/junit_e2e_networking.xml
	@echo "Networking tests complete!"
	@echo "Results: test_results/junit_e2e_networking.xml"

# Run networking tests via orchestration script (full CI/CD flow)
test-networking-ci:
	@echo "Running networking tests (CI mode)..."
	./tests/scripts/test-networking.sh --artifact-dir test_results
	@echo "CI tests complete!"
```

Update the `.PHONY` line to include `test-networking test-networking-ci`.

Update the `help` target to list the new targets.

**Reference:** `test-cluster-updates` and `test-cluster-updates-ci` targets in the Makefile.

### Step 6: Create CI orchestration script

**File:** `tests/scripts/test-<domain>.sh`

Copy `tests/scripts/test-cluster-updates.sh` and adapt it. The script structure is:

1. Validate cluster connection
2. Install dependencies
3. Deploy OLS (if `PROVIDER` is set)
4. Apply RBAC
5. Set up environment (API keys, tokens)
6. Run pytest with your domain's marker
7. Collect artifacts

**What to change:**

- Script header/banner text
- The pytest marker passed to `run_cluster_updates_tests` — change to your marker name
- The RBAC file path (if your domain uses a different one)

**What stays the same:** Everything from `utils.sh` — logging, dependency installation, OLS deployment, artifact collection, and cluster validation are all reusable.

**Reference:** `tests/scripts/test-cluster-updates.sh`

### Step 7: Create OLSConfig CRDs (if needed)

**Directory:** `tests/config/ols_deploy/`

If your domain requires a different OLS configuration (e.g., different MCP servers, feature gates, or tool filtering), create per-provider CRD files:

```
olsconfig.crd.openai_networking.yaml
olsconfig.crd.watsonx_networking.yaml
olsconfig.crd.google_vertex_networking.yaml
olsconfig.crd.google_vertex_anthropic_networking.yaml
```

**In most cases you can reuse the existing cluster-updates CRDs.** Only create new ones if your domain needs different OLS behavior (different tools, different models, etc.).

If you do create new CRDs, update the `deploy_ols` function in `utils.sh` to select the correct CRD based on the domain, or pass the CRD path as a parameter.

**Reference:** `tests/config/ols_deploy/olsconfig.crd.openai_cluster_updates.yaml`

### Step 8: Update RBAC (if needed)

**File:** `config/rbac-ocp-evals.yaml`

The default RBAC grants `cluster-reader` and `monitoring-edit` roles to the `ocp-eval-user` service account. This covers most read-only evaluation scenarios.

If your domain's evaluation queries require additional permissions (e.g., write access to specific namespaces, access to custom resources), add the necessary ClusterRoleBindings or RoleBindings to this file.

### Step 9: Set up CI periodic jobs

**Repository:** `openshift/release`

Add periodic jobs for your domain following the existing pattern. See [CI Integration](ci_integration.md) for the full template.

**Job naming convention:** `<domain-abbrev>-eval-<provider>-periodics`

- cluster-updates uses `cu-eval-*`
- networking would use `net-eval-*`

**Cron staggering:** Space jobs at least 1 hour apart to avoid resource contention. The cluster-updates jobs run at 14:30, 15:30, 16:30, and 17:30 UTC.

**Each job:**

1. Claims an OCP cluster
2. Exports `PROVIDER`, credential paths, and `EVAL_TAG=<domain>-critical`
3. Copies the provider system config over `config/system.yaml` (for non-openai providers)
4. Runs `tests/scripts/test-<domain>.sh --artifact-dir "${ARTIFACT_DIR}"`
5. Runs `gather-must-gather` post-step

**Credential mounts:** All jobs need `openai-apitoken` (for the judge LLM). Provider-specific jobs also need their own token (e.g., `watsonx-apitoken`, `vertex-apitoken`).

## Naming Conventions

| Component | Pattern | Example |
| --- | --- | --- |
| Tags | `<domain>-<category>` | `networking-critical` |
| Pytest marker | `<domain>` (underscored) | `networking` |
| Test file | `tests/e2e/evaluation/test_<domain>.py` | `test_networking.py` |
| CI script | `tests/scripts/test-<domain>.sh` | `test-networking.sh` |
| Makefile target | `test-<domain>` | `test-networking` |
| CI Makefile target | `test-<domain>-ci` | `test-networking-ci` |
| JUnit XML | `junit_e2e_<domain>.xml` | `junit_e2e_networking.xml` |
| CI job name | `<abbrev>-eval-<provider>-periodics` | `net-eval-openai-periodics` |
| OLSConfig CRD | `olsconfig.crd.<provider>_<domain>.yaml` | `olsconfig.crd.openai_networking.yaml` |
| System config | `config/system_<provider>.yaml` | Shared across domains |

## Shared vs. Domain-Specific Components

| Component | Shared? | Notes |
| --- | --- | --- |
| `requirements.txt` / `pyproject.toml` | Shared | No changes needed |
| `tests/test_basic.py` | Shared | Validates common structure |
| `tests/scripts/utils.sh` | Shared | Logging, OLS deploy, artifact collection |
| `tests/config/ols_deploy/route.yaml` | Shared | OLS route config |
| `tests/config/ols_deploy/imagedigestmirrorset.yaml` | Shared | CI image mirroring |
| Judge LLM config (`llm` section) | Shared | Same across all domains |
| `config/evaluation_data.yaml` | Domain-specific | Append your conversation groups |
| `config/system*.yaml` metrics section | Domain-specific | Add your GEval criteria |
| `pytest.ini` / `tests/conftest.py` markers | Domain-specific | Register your marker |
| `tests/e2e/evaluation/test_<domain>.py` | Domain-specific | Create per domain |
| `tests/scripts/test-<domain>.sh` | Domain-specific | Create per domain |
| `Makefile` targets | Domain-specific | Add per domain |
| OLSConfig CRDs | Often reusable | Create only if different OLS config needed |
| `config/rbac-ocp-evals.yaml` | Often reusable | Update only if different permissions needed |
| CI periodic jobs (openshift/release) | Domain-specific | Create per domain |
