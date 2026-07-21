# AGENTS.md

Guidelines for AI coding agents working on the ocp-evals repository.

## Repository Overview

**Purpose:** Evaluation suite for OpenShift Lightspeed across OCP domains

**Multi-domain structure:** Each OCP domain (e.g., cluster-updates) has its own evaluation data and domain-specific metrics under `config/`. New domains are added by creating additional evaluation data files and registering their metrics in `system.yaml`.

**Key Technology Stack:**
- Python 3.11+
- LightSpeed Evaluation Framework (external dependency)
- YAML configuration
- OpenShift/Kubernetes APIs (via MCP)

## Important Principles

### 1. This is a Configuration-First Repository

The repository primarily contains **configuration files** and **test scenarios**, not source code. The heavy lifting is done by the lightspeed-evaluation framework installed as a dependency.

**Core Files:**
- `config/system.yaml` - Evaluation system configuration
- `config/evaluation_data.yaml` - Test scenarios and expected responses
- `config/scripts/` - Setup/cleanup/verification scripts

### 2. Dependency Management

**NEVER duplicate the lightspeed-evaluation framework source code.** Always install it as a dependency:

```bash
pip install -r requirements.txt
```

The framework is installed from: `git+https://github.com/lightspeed-core/lightspeed-evaluation.git@v0.7.0`

### 3. Evaluation Data Best Practices

When creating or modifying test scenarios in `config/evaluation_data.yaml`:

**DO:**
- Use specific, measurable expected responses
- Include exact operator counts ("15 of 28 operators")
- Specify both condition type AND status field values
- Provide clear tags for organization
- Define appropriate metrics per scenario

**DON'T:**
- Use vague expectations ("should be healthy")
- Use placeholder data
- Assume condition status from type alone
- Mix unrelated test scenarios in one conversation

### 4. Metric Selection

Choose metrics based on what you're testing:

**Cluster-Updates Specific:**
- `geval:condition_status_accuracy` - For Kubernetes condition interpretation (strict 99%)
- `geval:output_format_compliance` - For format validation
- `geval:technical_accuracy` - For OpenShift/K8s concepts
- `geval:actionable_guidance` - For remediation quality

**General:**
- `custom:answer_correctness` - General correctness (always include)

**Multi-turn:**
- `custom:context_retention` - Conversation memory
- `custom:progressive_refinement` - Guidance improvement

## Development Workflow

### Adding a New Test Scenario

1. **Define the scenario** in `config/evaluation_data.yaml`:
```yaml
- conversation_group_id: my_test_scenario
  description: "Clear description of what is being tested"
  tag: cluster-updates-critical
  turns:
  - turn_id: turn_001
    query: "Specific query to test"
    expected_response: |
      Detailed expected response format with:
      ## Summary
      - Specific requirements

      ## TL;DR
      - Key points
    turn_metrics:
      - custom:answer_correctness
      - geval:technical_accuracy
```

2. **Run the evaluation**:
```bash
make eval CONV_IDS="my_test_scenario"
```

3. **Review results** in `eval_output/`

4. **Iterate** until passing

### Modifying System Configuration

**To change evaluation behavior**, edit `config/system.yaml`:

```yaml
# Change Judge LLM
llm:
  provider: "openai"
  model: "gpt-4o"  # Update model

# Add new metric
metrics_metadata:
  turn_level:
    "geval:my_new_metric":
      threshold: 0.8
      description: "What this metric evaluates"
      criteria: |
        Detailed evaluation criteria
      evaluation_params: [query, response]
```

### Running Evaluations

```bash
# All scenarios
make eval

# Specific tag
make eval TAGS="cluster-updates-critical"

# Specific conversations
make eval CONV_IDS="pre_upgrade_check"

# Clear cache first
make clean-cache
make eval
```

## Configuration File Patterns

### System Configuration (`config/system.yaml`)

**Structure:**
```yaml
core:           # Framework behavior
llm:            # Judge LLM settings
embedding:      # Embedding model (for RAG metrics)
api:            # API endpoint configuration
metrics_metadata:  # Metric definitions and thresholds
storage:        # Output configuration
visualization:  # Graph settings
environment:    # Environment variables
logging:        # Log levels
```

### Evaluation Data (`config/evaluation_data.yaml`)

**Structure:**
```yaml
- conversation_group_id: unique_id
  description: "What this tests"
  tag: category
  conversation_metrics: []  # Optional
  turns:
  - turn_id: turn_001
    query: "Question"
    expected_response: "Expected format"
    turn_metrics: [metrics]
```

## Common Tasks

### Update Framework Version

```bash
# Edit requirements.txt
git+https://github.com/lightspeed-core/lightspeed-evaluation.git@v0.8.0

# Reinstall
pip install -r requirements.txt --force-reinstall
```

### Add Verification Script

```bash
# Create script in config/scripts/
cat > config/scripts/verify_pod.sh << 'EOF'
#!/bin/bash
POD_NAME="${POD_NAME:-test-pod}"
if oc get pod "$POD_NAME" &>/dev/null; then
    echo "SUCCESS: Pod $POD_NAME exists"
    exit 0
else
    echo "FAILURE: Pod $POD_NAME not found"
    exit 1
fi
EOF

chmod +x config/scripts/verify_pod.sh
```

### Use in Evaluation Data

```yaml
- conversation_group_id: pod_creation_test
  turns:
  - turn_id: turn_001
    query: "Create a pod named test-pod"
    verify_script: "config/scripts/verify_pod.sh"
    turn_metrics:
      - script:action_eval
```

## Troubleshooting

### Issue: Framework Not Found

```bash
pip install -r requirements.txt --force-reinstall
```

### Issue: Evaluation Fails with API Error

Check:
1. OLS service is running: `oc get pods -n openshift-lightspeed`
2. API endpoint in `config/system.yaml`
3. API_KEY environment variable is set

### Issue: Metrics Always Fail

Check:
1. Expected response format matches actual
2. Threshold is reasonable
3. Evaluation params include required fields

### Issue: Cache Stale Results

```bash
make clean-cache
make eval
```

## Code Quality

If adding custom Python code (not typical for this repo):

```bash
# Format
make format

# Lint
make lint

# Type check
make typecheck

# Test
make test

# All checks
make all
```

## Adding New Evaluation Domains

See [Adding a New Domain](docs/adding_new_domain.md) for the complete guide.

Key files to touch when adding a domain:

1. `config/evaluation_data.yaml` — add conversation groups with domain-prefixed tags
2. `config/system*.yaml` — add domain-specific GEval metrics (if needed)
3. `pytest.ini` + `tests/conftest.py` — register the pytest marker
4. `tests/e2e/evaluation/test_<domain>.py` — create test file (follow `test_cluster_updates.py`)
5. `Makefile` — add `test-<domain>` and `test-<domain>-ci` targets
6. `tests/scripts/test-<domain>.sh` — create CI orchestration script
7. CI periodic jobs in `openshift/release` repo

## CI/CD Integration

This repository integrates with OpenShift CI. See [CI Integration](docs/ci_integration.md) for setup details.

## Resources

- [LightSpeed Evaluation Framework](https://github.com/lightspeed-core/lightspeed-evaluation)
- [OpenShift Updates Documentation](https://docs.openshift.com/container-platform/latest/updating/index.html)
- [Kubernetes Conditions](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-conditions)

## Questions?

Refer to:
1. `.claude/CLAUDE.md` - Claude Code specific guidance
2. `README.md` - User documentation
3. Framework docs - For framework-specific questions
