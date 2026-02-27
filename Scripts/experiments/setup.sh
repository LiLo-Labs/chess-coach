#!/bin/bash
# Setup script for on-device LLM experiments
# Installs Python dependencies needed to run experiments against Qwen3-4B GGUF

set -e

echo "Installing experiment dependencies..."
pip install llama-cpp-python chess
echo "Done. Run: python3 run_all.py"
