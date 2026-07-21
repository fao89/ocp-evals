r"""Cluster-updates evaluation tests across multiple LLM providers.

Each provider uses its own system config (``config/system_<provider>.yaml``)
with OpenAI ``gpt-5-mini`` as the judge LLM for scoring.  The model sent to OLS is defined
in the same file under ``api``.

Tests are parametrized by **tag** (from ``evaluation_data.yaml``) and **provider**, so each
conversation group is a separate pytest test case with its own pass/fail.

Provider matrix: openai, google_vertex, google_vertex_anthropic, watsonx.

When ``PROVIDER`` is set to a single provider (typical CI), other parametrized providers
are skipped so the suite does not call OLS with the wrong backend.

Local usage
-----------
1. Start OLS locally with the provider you want to evaluate::

       OLS_CONFIG_FILE=olsconfig-openai.yaml make run   # example: openai

2. Export the judge LLM key::

       export OPENAI_API_KEY=<your-key>

3. Run the eval for a single provider::

       PROVIDER=openai pytest tests/e2e/evaluation/test_cluster_updates.py \
           -m cluster_updates -v

   Or run all providers (when PROVIDER is unset, all 4 run)::

       pytest tests/e2e/evaluation/test_cluster_updates.py -m cluster_updates -v
"""

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

_CLUSTER_UPDATES_PROVIDERS = (
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
        return f"PROVIDER={only!r} on cluster; skipping cluster_updates for {provider!r}"
    return None


def _ensure_lseval_installed() -> None:
    """Ensure the lightspeed-evaluation package is installed.

    Checks if lightspeed-eval binary is available in PATH or venv.
    If not found, raises an error with installation instructions.
    """
    lseval_bin = shutil.which("lightspeed-eval")
    if lseval_bin:
        return

    venv_bin = PROJECT_ROOT / "venv" / "bin" / "lightspeed-eval"
    if venv_bin.exists():
        return

    raise FileNotFoundError(
        "lightspeed-eval command not found. "
        "Install it with: pip install -r requirements.txt"
    )


def _resolve_api_url() -> str:
    """Return the API base URL from environment variable or config default."""
    return os.getenv("API_BASE_URL", "").rstrip("/")


def _get_api_token() -> str:
    """Extract the API token from environment."""
    return os.getenv("API_KEY", "")


def _run_lseval(eval_data: Path, out_dir: Path, system_config: Path) -> None:
    """Run lightspeed-eval with the given data file and assert artifacts are produced.

    Args:
        eval_data: Path to the evaluation dataset YAML.
        out_dir: Directory where evaluation artefacts are written.
        system_config: Provider-specific cluster-updates system config YAML.
    """
    _ensure_lseval_installed()

    out_dir.mkdir(parents=True, exist_ok=True)
    if not os.access(out_dir, os.W_OK):
        raise PermissionError(f"Output directory is not writable: {out_dir}")

    with open(system_config, encoding="utf-8") as fh:
        config = yaml.safe_load(fh)

    api_url = _resolve_api_url()
    if api_url:
        config["api"]["api_base"] = api_url
        config["api"]["enabled"] = True

    tmp_config_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".yaml", delete=False, dir=str(CONFIG_DIR)
        ) as tmp:
            yaml.dump(config, tmp)
            tmp_config_path = tmp.name

        env = os.environ.copy()

        if "OPENAI_API_KEY" not in env:
            raise RuntimeError(
                "OPENAI_API_KEY environment variable is required for the judge LLM "
                "(OpenAI gpt-5-mini). Ensure the CI script exports it before running."
            )

        token = _get_api_token()
        if token:
            env["API_KEY"] = token

        lseval_cmd = shutil.which("lightspeed-eval")
        if not lseval_cmd:
            lseval_cmd = str(PROJECT_ROOT / "venv" / "bin" / "lightspeed-eval")

        result = subprocess.run(  # noqa: S603
            [
                lseval_cmd,
                "--system-config",
                tmp_config_path,
                "--eval-data",
                str(eval_data),
                "--output-dir",
                str(out_dir),
            ],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
    finally:
        if tmp_config_path and os.path.exists(tmp_config_path):
            os.unlink(tmp_config_path)

    print("--- lightspeed-eval stdout ---")
    print(result.stdout)
    if result.stderr:
        print("--- lightspeed-eval stderr ---")
        print(result.stderr)

    assert result.returncode == 0, (
        f"lightspeed-eval exited with code {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )

    csv_files = list(out_dir.glob("*_detailed.csv"))
    assert csv_files, f"No detailed CSV artifacts found in {out_dir}"

    json_files = list(out_dir.glob("*_summary.json"))
    assert json_files, f"No summary JSON artifacts found in {out_dir}"

    with open(json_files[0], encoding="utf-8") as fh:
        overall = json.load(fh)["summary_stats"]["overall"]

    if overall["error_rate"] > MAX_EVAL_ERROR_RATE_PCT:
        judge_tokens = overall.get("total_judge_llm_tokens", -1)
        judge_detail = (
            "0 → OLS calls failed before judge was reached"
            if judge_tokens == 0
            else "judge was called"
        )
        print(
            f"\n--- ERROR DIAGNOSTICS ---\n"
            f"Judge LLM tokens used: {judge_tokens} ({judge_detail})\n"
        )
        with open(csv_files[0], encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            error_rows = [r for r in reader if r.get("result") == "ERROR"]
        if error_rows:
            print("First 3 error reasons from detailed CSV:")
            for row in error_rows[:3]:
                print(
                    f"  turn={row.get('turn_id', '?')} "
                    f"reason={row.get('reason', '?')[:200]}"
                )

    assert overall["error_rate"] <= MAX_EVAL_ERROR_RATE_PCT, (
        f"{overall['ERROR']}/{overall['TOTAL']} evaluations errored "
        f"(error_rate={overall['error_rate']:.1f}% > "
        f"threshold {MAX_EVAL_ERROR_RATE_PCT}%)."
    )


def _load_tags() -> list[str]:
    """Return sorted unique tags from the evaluation data file."""
    with open(EVAL_DATA, encoding="utf-8") as fh:
        eval_data = yaml.safe_load(fh)
    if not isinstance(eval_data, list):
        raise ValueError("Evaluation data should be a list of conversation groups")
    return sorted({conv["tag"] for conv in eval_data if "tag" in conv})


_EVAL_TAGS = _load_tags()


@pytest.mark.cluster_updates
@pytest.mark.parametrize("tag", _EVAL_TAGS)
@pytest.mark.parametrize("provider", _CLUSTER_UPDATES_PROVIDERS)
def test_cluster_updates(tmp_path: Path, provider: str, tag: str) -> None:
    """Run cluster-updates eval for a single tag and provider."""
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
