#!/bin/bash
# Main evaluation runner script
# Runs OCP evaluations with proper environment setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== OCP Evaluation Runner ==="
echo "Project root: $PROJECT_ROOT"
echo ""

# Check required environment variables
if [ -z "$OPENAI_API_KEY" ]; then
    echo "ERROR: OPENAI_API_KEY environment variable not set"
    echo "Set it with: export OPENAI_API_KEY='your-key'"
    exit 1
fi

# Optional API_KEY check (only if API is enabled)
if grep -q "enabled: true" "$PROJECT_ROOT/config/system.yaml" 2>/dev/null; then
    if [ -z "$API_KEY" ]; then
        echo "WARNING: API is enabled but API_KEY not set"
        echo "Generate token with: export API_KEY=\$(oc create token ocp-eval-user -n openshift-lightspeed --duration=24h)"
        echo ""
    fi
fi

# Change to project root
cd "$PROJECT_ROOT"

# Parse command line arguments
TAGS=""
CONV_IDS=""
CLEAR_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --tags)
            TAGS="$2"
            shift 2
            ;;
        --conv-ids)
            CONV_IDS="$2"
            shift 2
            ;;
        --clear-cache)
            CLEAR_CACHE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --tags TAG1,TAG2        Run evaluations with specific tags"
            echo "  --conv-ids ID1,ID2      Run specific conversation IDs"
            echo "  --clear-cache           Clear caches before running"
            echo "  --help                  Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                           # Run all evaluations"
            echo "  $0 --tags cluster-updates-critical           # Run specific tag"
            echo "  $0 --conv-ids pre_upgrade_check              # Run specific conversation"
            echo "  $0 --clear-cache --tags cluster-updates-critical"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Clear cache if requested
if [ "$CLEAR_CACHE" = true ]; then
    echo "Clearing evaluation caches..."
    rm -rf .caches/*
    echo "Cache cleared"
    echo ""
fi

# Build lightspeed-eval command
CMD="lightspeed-eval --system-config config/system.yaml --eval-data config/evaluation_data.yaml --output-dir eval_output"

if [ -n "$TAGS" ]; then
    CMD="$CMD --tags $TAGS"
    echo "Running with tags: $TAGS"
fi

if [ -n "$CONV_IDS" ]; then
    CMD="$CMD --conv-ids $CONV_IDS"
    echo "Running conversation IDs: $CONV_IDS"
fi

echo "Running evaluations..."
echo ""

# Run evaluation
$CMD

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "=== Evaluation Complete ==="
    echo "Results saved to: eval_output/"
    echo ""
    echo "View results:"
    echo "  - CSV: eval_output/evaluation_*_detailed.csv"
    echo "  - JSON: eval_output/evaluation_*_summary.json"
    echo "  - Graphs: eval_output/graphs/"
else
    echo "=== Evaluation Failed ==="
    echo "Exit code: $EXIT_CODE"
    echo "Check logs above for errors"
fi

exit $EXIT_CODE
