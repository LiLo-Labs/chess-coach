#!/usr/bin/env python3
"""Experiment 1: Output Format Wars — which format does Qwen3-4B follow most reliably?

Tests 12 format variants x 15 positions x thinking on/off = 360 trials, 2 runs per trial.
Uses llama-cpp-python to load a GGUF model directly (no Ollama).
Outputs results/exp1_formats.csv
"""

import csv
import json
import os
import random
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

# Add parent dir for imports
sys.path.insert(0, str(Path(__file__).parent))
from evaluator import (
    format_ok,
    parse_refs_coaching,
    parse_json_response,
    parse_xml_response,
    hallucination_score,
)

RESULTS_DIR = Path(__file__).parent / "results"
MODEL_PATH = os.environ.get("GGUF_MODEL_PATH", "Qwen3-4B-Q4_K_M.gguf")
MODEL_NAME = "Qwen3-4B-Q4_K_M"
NUM_POSITIONS = 15
RUNS_PER_TRIAL = 2
MAX_TOKENS_THINKING = 2000    # thinking tokens (~1500-1800) + output (~200)
MAX_TOKENS_NON_THINKING = 200 # output only

# Qwen3 sampling params
THINKING_PARAMS = {"temperature": 0.6, "top_p": 0.95, "top_k": 20, "min_p": 0.0}
NON_THINKING_PARAMS = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}

# ---------------------------------------------------------------------------
# 12 format variants
# ---------------------------------------------------------------------------
FORMAT_VARIANTS = [
    {
        "id": "refs_coaching",
        "name": "REFS/COACHING (current)",
        "instruction": (
            "Respond with exactly two sections. First a REFS line listing the key squares "
            "or pieces, then a COACHING section with a brief explanation.\n"
            "Format:\n"
            "REFS: <comma-separated squares or pieces>\n"
            "COACHING: <one or two sentences>"
        ),
        "example": "REFS: bishop e5, pawn d4\nCOACHING: The bishop on e5 is very active, targeting the weak f7 pawn.",
    },
    {
        "id": "coaching_only",
        "name": "Coaching text only",
        "instruction": (
            "Respond with only a short coaching explanation (one or two sentences). "
            "Do not include any structured data, labels, or formatting — just plain coaching text."
        ),
        "example": "The knight on f3 is well-placed, supporting a future attack on the kingside.",
    },
    {
        "id": "json_flat",
        "name": "Flat JSON",
        "instruction": (
            "Respond with a single JSON object on one line containing two keys:\n"
            '- "coaching": a short coaching explanation\n'
            '- "refs": an array of referenced squares or pieces\n'
            "Output only the JSON, nothing else."
        ),
        "example": '{"coaching": "The bishop targets the weak f7 pawn.", "refs": ["bishop e5", "pawn d4"]}',
    },
    {
        "id": "json_nested",
        "name": "Nested JSON with quality",
        "instruction": (
            "Respond with a JSON object containing:\n"
            '- "coaching": a short explanation\n'
            '- "refs": an array of referenced squares or pieces\n'
            '- "quality": one of "good", "neutral", or "bad" describing the position\n'
            "Output only the JSON, nothing else."
        ),
        "example": '{"coaching": "The bishop is very active.", "refs": ["bishop e5"], "quality": "good"}',
    },
    {
        "id": "xml_tags",
        "name": "XML tags",
        "instruction": (
            "Respond using XML tags. Use <refs> for referenced squares/pieces and "
            "<coaching> for the explanation. Output only the XML, nothing else."
        ),
        "example": "<refs>bishop e5, pawn d4</refs>\n<coaching>The bishop targets the weak f7 pawn.</coaching>",
    },
    {
        "id": "xml_cdata",
        "name": "XML with CDATA",
        "instruction": (
            "Respond using XML tags with CDATA sections:\n"
            "<refs><![CDATA[...]]></refs>\n"
            "<coaching><![CDATA[...]]></coaching>\n"
            "Output only the XML, nothing else."
        ),
        "example": (
            "<refs><![CDATA[bishop e5, pawn d4]]></refs>\n"
            "<coaching><![CDATA[The bishop targets the weak f7 pawn.]]></coaching>"
        ),
    },
    {
        "id": "markdown_headers",
        "name": "Markdown headers",
        "instruction": (
            "Respond using Markdown with two sections:\n"
            "## Refs\n"
            "<comma-separated squares or pieces>\n\n"
            "## Coaching\n"
            "<one or two sentences>"
        ),
        "example": "## Refs\nbishop e5, pawn d4\n\n## Coaching\nThe bishop targets the weak f7 pawn.",
    },
    {
        "id": "numbered_lines",
        "name": "Numbered lines",
        "instruction": (
            "Respond with exactly two numbered lines:\n"
            "1. REFS: <comma-separated squares or pieces>\n"
            "2. COACHING: <one or two sentences>"
        ),
        "example": "1. REFS: bishop e5, pawn d4\n2. COACHING: The bishop targets the weak f7 pawn.",
    },
    {
        "id": "yaml_format",
        "name": "YAML format",
        "instruction": (
            "Respond in YAML format with two keys: refs (a list) and coaching (a string).\n"
            "Output only the YAML, nothing else."
        ),
        "example": "refs:\n  - bishop e5\n  - pawn d4\ncoaching: The bishop targets the weak f7 pawn.",
    },
    {
        "id": "pipe_delimited",
        "name": "Pipe delimited",
        "instruction": (
            "Respond with a single line using pipe (|) as delimiter:\n"
            "refs|coaching\n"
            "Where refs is a comma-separated list and coaching is a short explanation."
        ),
        "example": "bishop e5, pawn d4|The bishop targets the weak f7 pawn.",
    },
    {
        "id": "single_line_json",
        "name": "Compact single-line JSON",
        "instruction": (
            "Respond with a compact JSON object using short keys:\n"
            '{"r": "<comma-separated refs>", "c": "<coaching text>"}\n'
            "Output only the JSON, nothing else."
        ),
        "example": '{"r": "bishop e5, pawn d4", "c": "The bishop targets the weak f7 pawn."}',
    },
    {
        "id": "fenced_json",
        "name": "JSON in code fence",
        "instruction": (
            "Respond with a JSON object inside a Markdown code fence:\n"
            "```json\n"
            '{"coaching": "...", "refs": ["..."]}\n'
            "```\n"
            "Output only the fenced JSON, nothing else."
        ),
        "example": (
            '```json\n{"coaching": "The bishop targets the weak f7 pawn.", '
            '"refs": ["bishop e5", "pawn d4"]}\n```'
        ),
    },
]


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------

def load_model(model_path: str | None = None) -> "Llama":
    """Load the GGUF model via llama-cpp-python."""
    from llama_cpp import Llama

    path = model_path or MODEL_PATH
    print(f"Loading model from {path} ...")
    model = Llama(model_path=path, n_ctx=4096, n_threads=6, verbose=False)
    print("Model loaded.")
    return model


# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------

def build_prompt(position: dict, format_variant: dict, thinking: bool) -> tuple[str, str]:
    """Build the system and user messages for a trial.

    Returns (system_msg, user_msg).
    """
    think_tag = "/think" if thinking else "/no_think"

    if thinking:
        system_msg = (
            "You are a helpful chess coaching assistant. /think\n"
            "You may reason inside <think>...</think> tags. "
            "After closing </think>, output ONLY the final answer in the exact format requested — "
            "no extra text, no commentary, no markdown wrapping around the format."
        )
    else:
        system_msg = "You are a helpful chess coaching assistant. /no_think"

    # Build the position context
    fen = position.get("fen_after", position.get("fen", ""))
    side = position.get("side_to_move", "White")
    context_parts = [
        f"Position (FEN): {fen}",
        f"Side to move: {side}",
    ]
    if position.get("last_move"):
        context_parts.append(f"Last move: {position['last_move']}")
    if position.get("phase"):
        context_parts.append(f"Game phase: {position['phase']}")

    position_context = "\n".join(context_parts)

    # Build user message
    format_instruction = format_variant["instruction"]
    if thinking:
        format_instruction += (
            "\n\nIMPORTANT: After your </think> block, output ONLY the formatted response. "
            "Do not repeat your reasoning or add any text outside the requested format."
        )

    user_parts = [
        position_context,
        "",
        "Give a brief coaching insight for this position.",
        "",
        format_instruction,
    ]
    if format_variant.get("example"):
        user_parts.extend(["", "Example:", format_variant["example"]])

    user_msg = "\n".join(user_parts)
    return system_msg, user_msg


# ---------------------------------------------------------------------------
# Evaluation helpers
# ---------------------------------------------------------------------------

def _evaluate_response(response_text: str, variant_id: str, position: dict) -> dict:
    """Evaluate a response for format compliance, parseability, etc.

    Returns dict with: format_compliance, parseable, refs_extractable, hallucination_detected
    """
    result = {
        "format_compliance": False,
        "parseable": False,
        "refs_extractable": False,
        "hallucination_detected": False,
    }

    if not response_text or not response_text.strip():
        return result

    text = response_text.strip()

    # Strip thinking tags so format checks evaluate the actual output
    import re as _re
    think_match = _re.search(r"</think>\s*", text)
    if think_match:
        text = text[think_match.end():].strip()

    # --- format_compliance: does the response broadly match the requested format? ---
    if variant_id == "refs_coaching":
        result["format_compliance"] = format_ok(text, "refs_coaching")
        parsed = parse_refs_coaching(text)
        result["parseable"] = parsed is not None
        if parsed:
            result["refs_extractable"] = bool(parsed.get("refs"))

    elif variant_id == "coaching_only":
        result["format_compliance"] = format_ok(text, "coaching_only")
        result["parseable"] = True
        result["refs_extractable"] = False  # no refs expected

    elif variant_id in ("json_flat", "json_nested", "single_line_json"):
        parsed = parse_json_response(text)
        result["parseable"] = parsed is not None
        if parsed:
            result["format_compliance"] = True
            if variant_id == "single_line_json":
                result["refs_extractable"] = "r" in parsed and bool(parsed["r"])
            else:
                result["refs_extractable"] = "refs" in parsed and bool(parsed["refs"])
            if variant_id == "json_nested":
                result["format_compliance"] = "quality" in parsed

    elif variant_id == "fenced_json":
        # Strip fences then parse
        inner = text
        fence_match = re.search(r"```(?:json)?\s*\n?(.*?)\n?\s*```", text, re.DOTALL)
        if fence_match:
            inner = fence_match.group(1).strip()
            result["format_compliance"] = True
        parsed = parse_json_response(inner)
        result["parseable"] = parsed is not None
        if parsed:
            result["refs_extractable"] = "refs" in parsed and bool(parsed["refs"])

    elif variant_id in ("xml_tags", "xml_cdata"):
        parsed = parse_xml_response(text)
        result["parseable"] = parsed is not None
        if parsed:
            result["format_compliance"] = True
            result["refs_extractable"] = bool(parsed.get("refs"))

    elif variant_id == "markdown_headers":
        has_refs_header = bool(re.search(r"^##\s+Refs", text, re.MULTILINE | re.IGNORECASE))
        has_coaching_header = bool(re.search(r"^##\s+Coaching", text, re.MULTILINE | re.IGNORECASE))
        result["format_compliance"] = has_refs_header and has_coaching_header
        result["parseable"] = result["format_compliance"]
        if has_refs_header:
            refs_match = re.search(
                r"##\s+Refs\s*\n(.+?)(?=\n##|\Z)", text, re.DOTALL | re.IGNORECASE
            )
            result["refs_extractable"] = refs_match is not None and bool(refs_match.group(1).strip())

    elif variant_id == "numbered_lines":
        has_line1 = bool(re.search(r"^1\.\s*REFS:", text, re.MULTILINE | re.IGNORECASE))
        has_line2 = bool(re.search(r"^2\.\s*COACHING:", text, re.MULTILINE | re.IGNORECASE))
        result["format_compliance"] = has_line1 and has_line2
        result["parseable"] = result["format_compliance"]
        if has_line1:
            refs_match = re.search(r"1\.\s*REFS:\s*(.+)", text, re.IGNORECASE)
            result["refs_extractable"] = refs_match is not None and bool(refs_match.group(1).strip())

    elif variant_id == "yaml_format":
        has_refs = bool(re.search(r"^refs:", text, re.MULTILINE | re.IGNORECASE))
        has_coaching = bool(re.search(r"^coaching:", text, re.MULTILINE | re.IGNORECASE))
        result["format_compliance"] = has_refs and has_coaching
        result["parseable"] = result["format_compliance"]
        result["refs_extractable"] = has_refs

    elif variant_id == "pipe_delimited":
        parts = text.split("|")
        result["format_compliance"] = len(parts) == 2
        result["parseable"] = len(parts) >= 2
        if len(parts) >= 2:
            result["refs_extractable"] = bool(parts[0].strip())

    # --- hallucination check ---
    try:
        h_score = hallucination_score(text, position.get("fen_after", position.get("fen", "")))
        result["hallucination_detected"] = h_score > 0.5
    except Exception:
        result["hallucination_detected"] = False

    return result


# ---------------------------------------------------------------------------
# Trial runner
# ---------------------------------------------------------------------------

def run_trial(model, position: dict, format_variant: dict, thinking: bool) -> dict:
    """Run a single trial: generate a response and evaluate it.

    Returns a dict with all measurements.
    """
    system_msg, user_msg = build_prompt(position, format_variant, thinking)
    params = THINKING_PARAMS if thinking else NON_THINKING_PARAMS

    t0 = time.perf_counter()
    try:
        output = model.create_chat_completion(
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user", "content": user_msg},
            ],
            max_tokens=MAX_TOKENS_THINKING if thinking else MAX_TOKENS_NON_THINKING,
            temperature=params["temperature"],
            top_p=params["top_p"],
            top_k=params["top_k"],
            min_p=params["min_p"],
        )
        response_text = output["choices"][0]["message"]["content"] or ""
        tokens_out = output["usage"]["completion_tokens"]
        tokens_in = output["usage"]["prompt_tokens"]
    except Exception as e:
        print(f"  [ERROR] Generation failed: {e}")
        response_text = ""
        tokens_out = 0
        tokens_in = 0

    latency_ms = (time.perf_counter() - t0) * 1000.0

    # Evaluate
    eval_result = _evaluate_response(response_text, format_variant["id"], position)

    return {
        "response_text": response_text,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "latency_ms": round(latency_ms, 1),
        "format_compliance": eval_result["format_compliance"],
        "parseable": eval_result["parseable"],
        "refs_extractable": eval_result["refs_extractable"],
        "hallucination_detected": eval_result["hallucination_detected"],
        "system_msg": system_msg,
        "user_msg": user_msg,
    }


# ---------------------------------------------------------------------------
# Main experiment runner
# ---------------------------------------------------------------------------

CSV_COLUMNS = [
    "experiment_id",
    "trial_id",
    "timestamp",
    "model",
    "position_id",
    "variant_id",
    "thinking_mode",
    "max_tokens",
    "tokens_in",
    "tokens_out",
    "format_compliance",
    "parseable",
    "refs_extractable",
    "hallucination_detected",
    "latency_ms",
    "raw_prompt",
    "raw_response",
    "params_json",
]


def run_experiment(model_path: str | None = None) -> Path:
    """Run the full Experiment 1 and write results to CSV.

    Returns the path to the output CSV.
    """
    experiment_id = f"exp1_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = RESULTS_DIR / "exp1_formats.csv"

    # Load test positions
    positions_file = Path(__file__).parent / "test_positions.json"
    if not positions_file.exists():
        print(f"ERROR: {positions_file} not found. Please create it first.")
        sys.exit(1)

    with open(positions_file) as f:
        all_positions = json.load(f)

    # Sample positions
    if len(all_positions) > NUM_POSITIONS:
        positions = random.sample(all_positions, NUM_POSITIONS)
    else:
        positions = all_positions
    print(f"Using {len(positions)} positions.")

    # Load model
    model = load_model(model_path)

    # Total trials
    total_trials = len(FORMAT_VARIANTS) * len(positions) * 2 * RUNS_PER_TRIAL  # 2 = thinking on/off
    print(f"Running {total_trials} trials ({len(FORMAT_VARIANTS)} formats x {len(positions)} positions x 2 thinking modes x {RUNS_PER_TRIAL} runs)")
    print(f"Output: {csv_path}")
    print()

    trial_count = 0

    with open(csv_path, "w", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=CSV_COLUMNS)
        writer.writeheader()

        for variant in FORMAT_VARIANTS:
            for position in positions:
                for thinking in [True, False]:
                    for run_idx in range(RUNS_PER_TRIAL):
                        trial_count += 1
                        trial_id = str(uuid.uuid4())[:12]
                        thinking_label = "thinking" if thinking else "non_thinking"
                        params = THINKING_PARAMS if thinking else NON_THINKING_PARAMS
                        position_id = position.get("position_id", position.get("fen_after", "unknown")[:20])

                        print(
                            f"  [{trial_count}/{total_trials}] {variant['id']} | "
                            f"{position_id} | {thinking_label} | run {run_idx + 1}"
                        )

                        result = run_trial(model, position, variant, thinking)

                        # Build the full prompt for logging
                        raw_prompt = (
                            f"[SYSTEM] {result['system_msg']}\n"
                            f"[USER] {result['user_msg']}"
                        )

                        row = {
                            "experiment_id": experiment_id,
                            "trial_id": trial_id,
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                            "model": MODEL_NAME,
                            "position_id": position_id,
                            "variant_id": variant["id"],
                            "thinking_mode": thinking_label,
                            "max_tokens": MAX_TOKENS_THINKING if thinking else MAX_TOKENS_NON_THINKING,
                            "tokens_in": result["tokens_in"],
                            "tokens_out": result["tokens_out"],
                            "format_compliance": result["format_compliance"],
                            "parseable": result["parseable"],
                            "refs_extractable": result["refs_extractable"],
                            "hallucination_detected": result["hallucination_detected"],
                            "latency_ms": result["latency_ms"],
                            "raw_prompt": raw_prompt,
                            "raw_response": result["response_text"],
                            "params_json": json.dumps(params),
                        }
                        writer.writerow(row)

    print()
    print(f"Done. {trial_count} trials written to {csv_path}")
    return csv_path


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    path_arg = sys.argv[1] if len(sys.argv) > 1 else None
    result_path = run_experiment(model_path=path_arg)
    print(f"\nResults: {result_path}")
