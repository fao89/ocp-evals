#!/bin/bash
# Quick evaluation example - runs a subset of scenarios

set -e

echo "Running quick OCP evaluation..."
echo ""

# Check environment
if [ -z "$OPENAI_API_KEY" ]; then
    echo "ERROR: OPENAI_API_KEY not set"
    echo "Export your OpenAI API key first"
    exit 1
fi

# Run evaluation with specific scenarios
lightspeed-eval \
    --system-config config/system.yaml \
    --eval-data config/evaluation_data.yaml \
    --output-dir eval_output \
    --tags cluster-updates-critical

echo ""
echo "Quick evaluation complete!"
echo "Results in: eval_output/"
