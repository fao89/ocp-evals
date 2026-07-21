# OCP Evaluations

Evaluation suite for [OpenShift Lightspeed](https://docs.openshift.com/container-platform/latest/lightspeed/index.html) across OCP domains, powered by the [LightSpeed Evaluation Framework](https://github.com/lightspeed-core/lightspeed-evaluation).

## Overview

This repository provides evaluation scenarios for OpenShift Lightspeed, organized by OCP domain. Each domain contains test scenarios, expected responses, and domain-specific metrics.

### Current Evaluation Domains

**Cluster Updates** — validates upgrade-related workflows:

- Pre-upgrade readiness checks
- Upgrade path validation with conditional update risk analysis
- Progress monitoring and failure troubleshooting
- Multi-turn conversation context retention

### Adding a New Domain

See [Adding a New Domain](docs/adding_new_domain.md) for the complete guide covering evaluation data, metrics, tests, CI, and all naming conventions.

## Quick Start

### Prerequisites

- Python 3.11 or higher
- Access to an OpenShift cluster (for real-time evaluations)
- OpenAI API key (for LLM judge)
- (Optional) Service account token for cluster access via MCP

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd ocp-evals

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### Configuration

1. **Set required environment variables:**

```bash
# Judge LLM API key (required)
export OPENAI_API_KEY="your-openai-api-key"

# API authentication for OpenShift Lightspeed service (if API enabled)
export API_KEY=$(oc create token ocp-eval-user -n openshift-lightspeed --duration=24h)

# Optional: Kubernetes config for script-based evaluations
export KUBECONFIG="/path/to/your/kubeconfig"
```

2. **Configure system settings** in `config/system.yaml`:
   - Adjust LLM provider and model
   - Configure API endpoint
   - Customize evaluation metrics

3. **Prepare evaluation data** in `config/evaluation_data.yaml`:
   - Define test scenarios
   - Set expected responses
   - Configure metrics per scenario

### Running Evaluations

**Basic evaluation run:**

```bash
make eval
```

**Run with specific tags:**

```bash
make eval TAGS="cluster-updates-critical cluster-updates-conditions"
```

**Run specific conversation IDs:**

```bash
make eval CONV_IDS="pre_upgrade_check upgrade_path_validation"
```

**Clear cache and rebuild:**

```bash
make clean
make eval
```

### Usage Modes

#### 1. API-Enabled (Real-time Data Collection)

Evaluates against a running OpenShift Lightspeed service:

```bash
# Ensure OLS is running
oc get pods -n openshift-lightspeed

# Run evaluation
make eval
```

#### 2. Static Data Evaluation (API Disabled)

Evaluates pre-generated responses without API calls:

```yaml
# In config/system.yaml
api:
  enabled: false
```

Provide `response`, `contexts`, and `tool_calls` in evaluation data.

## Directory Structure

```
ocp-evals/
├── config/                      # Configuration files
│   ├── system.yaml             # System-wide config
│   ├── evaluation_data.yaml    # Test scenarios (all domains)
│   └── scripts/                # Setup/cleanup/verify scripts
├── eval_output/                # Evaluation results (git-ignored)
├── docs/                       # Documentation
├── scripts/                    # Utility scripts
├── tests/                      # Test infrastructure
├── .claude/                    # Claude Code configuration
├── pyproject.toml             # Package configuration
├── requirements.txt           # Python dependencies
├── Makefile                   # Development commands
├── README.md                  # This file
├── LICENSE                    # Apache 2.0
└── .gitignore                 # Git ignore rules
```

## Evaluation Metrics

### Turn-Level Metrics

- **custom:answer_correctness** - General correctness evaluation
- **geval:condition_status_accuracy** - Kubernetes condition interpretation (99% threshold)
- **geval:output_format_compliance** - Summary + TL;DR format validation
- **geval:technical_accuracy** - OpenShift/Kubernetes technical correctness
- **geval:actionable_guidance** - Quality of remediation steps
- **custom:context_retention** - Multi-turn context memory
- **custom:progressive_refinement** - Guidance specificity progression

### Conversation-Level Metrics

- **deepeval:conversation_completeness** - How completely conversations address user intentions
- **deepeval:conversation_relevancy** - Conversation topic relevance

## Output

After running evaluations, results are saved to `eval_output/`:

- **CSV** - Detailed results with scores and reasons
- **JSON** - Summary statistics
- **TXT** - Human-readable summary
- **Graphs** - Visualizations (score distribution, status breakdown)

## Development

### Running Tests

```bash
make test
```

### Code Quality

```bash
# Format code
make format

# Lint
make lint

# Type check
make typecheck
```

### Adding New Scenarios

1. Add scenario to `config/evaluation_data.yaml`
2. Define expected response
3. Select appropriate metrics
4. Tag with domain prefix for organization (e.g., `cluster-updates-critical`, `networking-dns`)
5. Run evaluation

## CI/CD Integration

This repository can be integrated with OpenShift CI for periodic evaluations:

1. Configure periodic job in `openshift/release` repository
2. Set up credentials (API keys, service account tokens)
3. Define schedule (e.g., daily at specific time)
4. Collect artifacts to GCS

See `docs/ci_integration.md` for detailed setup instructions.

## Troubleshooting

### Common Issues

**Issue:** `lightspeed-evaluation not found`
```bash
# Reinstall dependencies
pip install -r requirements.txt --force-reinstall
```

**Issue:** `API connection timeout`
```bash
# Check OLS service is running
oc get pods -n openshift-lightspeed

# Verify API endpoint in config/system.yaml
api:
  api_base: http://localhost:8080
```

**Issue:** `RBAC permission denied`
```bash
# Apply RBAC
oc apply -f config/rbac-ocp-evals.yaml

# Generate fresh token
export API_KEY=$(oc create token ocp-eval-user -n openshift-lightspeed --duration=24h)
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new scenarios
4. Run quality checks (`make lint test`)
5. Submit a pull request

## License

Apache License 2.0 - See [LICENSE](LICENSE) file for details.

## Resources

- [LightSpeed Evaluation Framework](https://github.com/lightspeed-core/lightspeed-evaluation)
- [OpenShift Documentation](https://docs.openshift.com/)
- [Cluster Updates Guide](https://docs.openshift.com/container-platform/latest/updating/index.html)
