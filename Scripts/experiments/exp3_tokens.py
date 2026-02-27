#!/usr/bin/env python3
"""
Experiment 3: Token Budget Experiments
Tests impact of input and output token limits on coaching quality.

Uses llama-cpp-python to load GGUF directly (NO Ollama).

Phases:
  1. Output grid:   8 max_tokens values x 15 positions x thinking on/off = 240 trials
  2. Input grid:    8 input configs x 15 positions x thinking on/off   = 240 trials
  3. Combined best: top 3 input x top 3 output x 15 positions          = 135 trials
  Total: ~615 trials

Outputs: results/exp3_tokens.csv
"""

import csv
import json
import os
import re
import time
import uuid
from pathlib import Path

from llama_cpp import Llama

from evaluator import (
    board_summary,
    format_ok,
    hallucination_score,
    mentions_move,
    mentions_opening,
)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
RESULTS_DIR = SCRIPT_DIR / "results"
POSITIONS_PATH = SCRIPT_DIR / "test_positions.json"
OUTPUT_CSV = RESULTS_DIR / "exp3_tokens.csv"
EXP2_CSV = RESULTS_DIR / "exp2_prompts.csv"
EXP1_CSV = RESULTS_DIR / "exp1_formats.csv"

DEFAULT_MODEL_PATH = REPO_ROOT / "Models" / "qwen3-4b-q4_k_m.gguf"

EXPERIMENT_ID = "exp3_tokens"
MODEL_NAME = "qwen3-4b"
NUM_POSITIONS = 15

# ---------------------------------------------------------------------------
# Sampling parameters
# ---------------------------------------------------------------------------
THINKING_PARAMS = {"temperature": 0.6, "top_p": 0.95, "top_k": 20, "min_p": 0.0}
NON_THINKING_PARAMS = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}

# ---------------------------------------------------------------------------
# Token experiment grids
# ---------------------------------------------------------------------------
OUTPUT_TOKEN_VALUES = [32, 64, 100, 150, 200, 300, 500, 800]

INPUT_CONFIG_IDS = [
    "full",
    "no_board_summary",
    "no_history",
    "no_opening_desc",
    "no_rules",
    "minimal_input",
    "fen_only_input",
    "kitchen_sink",
]

# Fixed max_tokens for the input grid phase
INPUT_GRID_MAX_TOKENS = 200

# ---------------------------------------------------------------------------
# CSV columns
# ---------------------------------------------------------------------------
CSV_COLUMNS = [
    "experiment_id",
    "trial_id",
    "timestamp",
    "model",
    "position_id",
    "input_config_id",
    "max_tokens",
    "thinking_mode",
    "tokens_in",
    "tokens_out",
    "truncated",
    "format_compliance",
    "coaching_complete",
    "hallucination_detected",
    "latency_ms",
    "quality_score",
    "raw_prompt",
    "raw_response",
    "params_json",
]


# ---------------------------------------------------------------------------
# Determine best prompt from exp2
# ---------------------------------------------------------------------------
def determine_best_prompt() -> str:
    """Read results/exp2_prompts.csv and return the variant_id with the
    highest average quality_score.  Falls back to 'current' if the file
    is missing or empty."""
    if not EXP2_CSV.exists():
        return "current"

    scores: dict[str, list[float]] = {}
    try:
        with open(EXP2_CSV, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                vid = row.get("variant_id", row.get("prompt_variant", ""))
                if not vid:
                    continue
                try:
                    q = float(row["quality_score"])
                except (KeyError, ValueError):
                    continue
                scores.setdefault(vid, []).append(q)
    except Exception:
        return "current"

    if not scores:
        return "current"

    best_id = max(scores, key=lambda v: sum(scores[v]) / len(scores[v]))
    return best_id


# ---------------------------------------------------------------------------
# Determine best format from exp1
# ---------------------------------------------------------------------------
def determine_best_format() -> str:
    """Read results/exp1_formats.csv and return the format_id with the
    highest average quality_score.  Falls back to 'refs_coaching'."""
    if not EXP1_CSV.exists():
        return "refs_coaching"

    scores: dict[str, list[float]] = {}
    try:
        with open(EXP1_CSV, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                fid = row.get("format_id", "")
                if not fid:
                    continue
                try:
                    q = float(row["quality_score"])
                except (KeyError, ValueError):
                    continue
                scores.setdefault(fid, []).append(q)
    except Exception:
        return "refs_coaching"

    if not scores:
        return "refs_coaching"

    best_id = max(scores, key=lambda v: sum(scores[v]) / len(scores[v]))
    return best_id


# ---------------------------------------------------------------------------
# Format instruction helper
# ---------------------------------------------------------------------------
FORMAT_INSTRUCTIONS = {
    "refs_coaching": (
        "Reply in exactly this format:\n"
        "REFS: <piece square, piece square, ...>\n"
        "COACHING: <one or two sentences of coaching advice>"
    ),
    "coaching_only": (
        "Reply with one or two sentences of coaching advice. "
        "Do not use labels or structured formatting."
    ),
    "json_flat": (
        'Reply with a JSON object like: {"refs": "...", "coaching": "..."}'
    ),
    "json_nested": (
        "Reply with a JSON object containing a 'refs' array of "
        "{\"piece\": ..., \"square\": ...} objects and a 'coaching' string."
    ),
    "xml_tags": (
        "Reply using XML tags: <refs>...</refs><coaching>...</coaching>"
    ),
    "markdown_headers": (
        "Reply using markdown headers:\n## Refs\n...\n## Coaching\n..."
    ),
    "numbered_lines": (
        "Reply as numbered lines:\n1. Refs: ...\n2. Coaching: ..."
    ),
    "yaml_format": (
        "Reply in YAML format:\nrefs: ...\ncoaching: ..."
    ),
    "pipe_delimited": (
        "Reply in pipe-delimited format: refs | coaching text"
    ),
    "single_line_json": (
        'Reply with a single-line JSON object: {"refs": "...", "coaching": "..."}'
    ),
    "fenced_json": (
        "Reply with a fenced JSON block:\n```json\n{\"refs\": \"...\", \"coaching\": \"...\"}\n```"
    ),
    "xml_cdata": (
        "Reply using XML with CDATA sections:\n"
        "<refs><![CDATA[...]]></refs><coaching><![CDATA[...]]></coaching>"
    ),
}


def get_format_instruction(format_id: str) -> str:
    """Return the format instruction string for the given format_id."""
    return FORMAT_INSTRUCTIONS.get(format_id, FORMAT_INSTRUCTIONS["refs_coaching"])


# ---------------------------------------------------------------------------
# Input config builders
# ---------------------------------------------------------------------------
def _move_history_text(position: dict) -> str:
    """Build a short move-history fragment from position metadata."""
    san = position.get("book_move_san", "")
    ply = position.get("ply", 0)
    side = "White" if position.get("is_white_move") else "Black"
    move_num = (ply + 1) // 2 + 1
    return f"Move {move_num} ({side}): {san}"


def _opening_desc_text(position: dict) -> str:
    """Build an opening description fragment."""
    name = position.get("opening_name", "")
    explanation = position.get("move_explanation", "")
    parts = []
    if name:
        parts.append(f"Opening: {name}")
    if explanation:
        parts.append(f"This move's idea: {explanation}")
    return "\n".join(parts)


def _rules_text() -> str:
    """Standard rules/role preamble for the user message."""
    return (
        "You are a chess coach for a beginner. "
        "Explain why the suggested move is good in simple terms. "
        "Mention which pieces are important and why."
    )


def _plan_text(position: dict) -> str:
    """Extended plan information for kitchen_sink config."""
    plan = position.get("plan_summary", "")
    goals = position.get("strategic_goals", [])
    parts = []
    if plan:
        parts.append(f"Plan: {plan}")
    if goals:
        parts.append("Strategic goals: " + "; ".join(goals))
    return "\n".join(parts)


def _piece_targets_text(position: dict) -> str:
    """Piece target information for kitchen_sink config."""
    targets = position.get("piece_targets", [])
    if not targets:
        return ""
    lines = []
    for t in targets:
        piece = t.get("piece", "")
        squares = ", ".join(t.get("ideal_squares", []))
        reason = t.get("reasoning", "")
        lines.append(f"{piece} -> {squares}: {reason}")
    return "Piece targets:\n" + "\n".join(lines)


def build_input(
    position: dict, input_config_id: str, format_instruction: str
) -> tuple[str, str]:
    """Build (system_message, user_message) for a given input config.

    Returns:
        (system_msg, user_msg) tuple
    """
    fen = position.get("fen_before", "")
    san = position.get("book_move_san", "")
    opening_name = position.get("opening_name", "")
    bs = board_summary(fen)

    system_msg = "You are a chess coach helping a beginner learn openings."

    if input_config_id == "full":
        # FEN + board summary + move history + opening desc + rules + format (~400 tokens)
        user_parts = [
            f"Position (FEN): {fen}",
            f"Board:\n{bs}",
            _move_history_text(position),
            _opening_desc_text(position),
            _rules_text(),
            format_instruction,
        ]

    elif input_config_id == "no_board_summary":
        # FEN + move history + opening desc + rules + format (~250)
        user_parts = [
            f"Position (FEN): {fen}",
            _move_history_text(position),
            _opening_desc_text(position),
            _rules_text(),
            format_instruction,
        ]

    elif input_config_id == "no_history":
        # FEN + board summary + opening desc + rules + format (~350)
        user_parts = [
            f"Position (FEN): {fen}",
            f"Board:\n{bs}",
            _opening_desc_text(position),
            _rules_text(),
            format_instruction,
        ]

    elif input_config_id == "no_opening_desc":
        # FEN + board summary + move history + rules + format (~350)
        user_parts = [
            f"Position (FEN): {fen}",
            f"Board:\n{bs}",
            _move_history_text(position),
            _rules_text(),
            format_instruction,
        ]

    elif input_config_id == "no_rules":
        # FEN + board summary + move history + opening desc + format (~300)
        user_parts = [
            f"Position (FEN): {fen}",
            f"Board:\n{bs}",
            _move_history_text(position),
            _opening_desc_text(position),
            format_instruction,
        ]

    elif input_config_id == "minimal_input":
        # FEN + move + opening name + format (~100)
        user_parts = [
            f"FEN: {fen}",
            f"Move: {san}",
            f"Opening: {opening_name}",
            format_instruction,
        ]

    elif input_config_id == "fen_only_input":
        # FEN + move + format (~60)
        user_parts = [
            f"FEN: {fen}",
            f"Move: {san}",
            format_instruction,
        ]

    elif input_config_id == "kitchen_sink":
        # Everything + plan + piece targets + Maia placeholder data (~600)
        user_parts = [
            f"Position (FEN): {fen}",
            f"Board:\n{bs}",
            _move_history_text(position),
            _opening_desc_text(position),
            _plan_text(position),
            _piece_targets_text(position),
            f"Pawn structure: {position.get('pawn_structure', '')}",
            f"Maia win probability: 0.52",  # placeholder
            f"Maia suggested move: {san}",  # placeholder
            _rules_text(),
            format_instruction,
        ]

    else:
        # Fallback to full
        user_parts = [
            f"Position (FEN): {fen}",
            f"Board:\n{bs}",
            _move_history_text(position),
            _opening_desc_text(position),
            _rules_text(),
            format_instruction,
        ]

    user_msg = "\n\n".join(p for p in user_parts if p)
    return system_msg, user_msg


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------
def load_model(model_path: str | Path | None = None) -> Llama:
    """Load the GGUF model via llama-cpp-python."""
    path = str(model_path or DEFAULT_MODEL_PATH)
    print(f"Loading model from {path} ...")
    model = Llama(
        model_path=path,
        n_ctx=2048,
        n_gpu_layers=-1,  # offload all layers to GPU/Metal
        verbose=False,
    )
    print("Model loaded.")
    return model


# ---------------------------------------------------------------------------
# Single trial
# ---------------------------------------------------------------------------
def run_trial(
    model: Llama,
    position: dict,
    max_tokens: int,
    input_config_id: str,
    thinking: bool,
    format_instruction: str,
    format_id: str = "refs_coaching",
) -> dict:
    """Run a single inference trial and return measurement dict."""
    system_msg, user_msg = build_input(position, input_config_id, format_instruction)

    messages = [
        {"role": "system", "content": system_msg},
        {"role": "user", "content": user_msg},
    ]

    params = dict(THINKING_PARAMS if thinking else NON_THINKING_PARAMS)
    params_json = json.dumps(params)

    t0 = time.perf_counter()
    try:
        output = model.create_chat_completion(
            messages=messages,
            max_tokens=max_tokens,
            **params,
        )
    except Exception as e:
        elapsed_ms = (time.perf_counter() - t0) * 1000
        return {
            "experiment_id": EXPERIMENT_ID,
            "trial_id": str(uuid.uuid4()),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "model": MODEL_NAME,
            "position_id": position.get("position_id", ""),
            "input_config_id": input_config_id,
            "max_tokens": max_tokens,
            "thinking_mode": thinking,
            "tokens_in": 0,
            "tokens_out": 0,
            "truncated": False,
            "format_compliance": False,
            "coaching_complete": False,
            "hallucination_detected": False,
            "latency_ms": round(elapsed_ms, 1),
            "quality_score": 0,
            "raw_prompt": json.dumps(messages),
            "raw_response": f"ERROR: {e}",
            "params_json": params_json,
        }
    elapsed_ms = (time.perf_counter() - t0) * 1000

    # Extract response text
    raw_response = ""
    if output.get("choices"):
        raw_response = output["choices"][0].get("message", {}).get("content", "")

    # Token counts from usage
    usage = output.get("usage", {})
    tokens_in = usage.get("prompt_tokens", 0)
    tokens_out = usage.get("completion_tokens", 0)

    # Truncation: did the response hit max_tokens?
    finish_reason = ""
    if output.get("choices"):
        finish_reason = output["choices"][0].get("finish_reason", "")
    truncated = finish_reason == "length"

    # Format compliance
    fmt_ok = format_ok(raw_response, format_id)

    # Coaching completeness: ends with sentence-ending punctuation
    response_stripped = raw_response.strip()
    coaching_complete = bool(
        response_stripped and response_stripped[-1] in ".?!"
    )

    # Hallucination detection
    fen = position.get("fen_before", "")
    h_score = hallucination_score(raw_response, fen)
    hallucination_detected = h_score > 0

    # Quality score (0-4)
    quality = 0
    if fmt_ok:
        quality += 1
    if not hallucination_detected:
        quality += 1
    opening_name = position.get("opening_name", "")
    if mentions_opening(raw_response, opening_name):
        quality += 1
    book_move_san = position.get("book_move_san", "")
    if mentions_move(raw_response, book_move_san):
        quality += 1

    return {
        "experiment_id": EXPERIMENT_ID,
        "trial_id": str(uuid.uuid4()),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "model": MODEL_NAME,
        "position_id": position.get("position_id", ""),
        "input_config_id": input_config_id,
        "max_tokens": max_tokens,
        "thinking_mode": thinking,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "truncated": truncated,
        "format_compliance": fmt_ok,
        "coaching_complete": coaching_complete,
        "hallucination_detected": hallucination_detected,
        "latency_ms": round(elapsed_ms, 1),
        "quality_score": quality,
        "raw_prompt": json.dumps(messages),
        "raw_response": raw_response,
        "params_json": params_json,
    }


# ---------------------------------------------------------------------------
# Top-N helper
# ---------------------------------------------------------------------------
def _top_n_by_quality(rows: list[dict], group_key: str, n: int = 3) -> list[str]:
    """Return the top-n group values ranked by average quality_score."""
    scores: dict[str, list[float]] = {}
    for row in rows:
        gid = row[group_key]
        scores.setdefault(gid, []).append(float(row["quality_score"]))
    ranked = sorted(scores, key=lambda g: sum(scores[g]) / len(scores[g]), reverse=True)
    return ranked[:n]


# ---------------------------------------------------------------------------
# Main experiment runner
# ---------------------------------------------------------------------------
def run_experiment(model_path: str | Path | None = None) -> Path:
    """Run the full three-phase token budget experiment.

    Returns the path to the output CSV.
    """
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    # Load positions
    if not POSITIONS_PATH.exists():
        raise FileNotFoundError(
            f"Test positions not found at {POSITIONS_PATH}. "
            "Run generate_test_positions.py first."
        )
    with open(POSITIONS_PATH, "r", encoding="utf-8") as f:
        all_positions = json.load(f)

    positions = all_positions[:NUM_POSITIONS]
    print(f"Using {len(positions)} positions for experiment.")

    # Determine best prompt and format from prior experiments
    best_prompt = determine_best_prompt()
    best_format = determine_best_format()
    format_instruction = get_format_instruction(best_format)
    print(f"Best prompt from exp2: {best_prompt}")
    print(f"Best format from exp1: {best_format}")

    # Load model
    model = load_model(model_path)

    all_rows: list[dict] = []

    # Open CSV for incremental writing
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=CSV_COLUMNS)
        writer.writeheader()

        # =================================================================
        # Phase 1: Output token grid
        # 8 max_tokens values x 15 positions x thinking on/off = 240 trials
        # =================================================================
        print("\n=== Phase 1: Output Token Grid ===")
        phase1_rows: list[dict] = []
        total_phase1 = len(OUTPUT_TOKEN_VALUES) * len(positions) * 2
        trial_num = 0

        for max_tok in OUTPUT_TOKEN_VALUES:
            for pos in positions:
                for thinking in [True, False]:
                    trial_num += 1
                    print(
                        f"  Phase 1 [{trial_num}/{total_phase1}] "
                        f"max_tokens={max_tok} thinking={thinking} "
                        f"pos={pos.get('position_id', '?')}"
                    )
                    row = run_trial(
                        model=model,
                        position=pos,
                        max_tokens=max_tok,
                        input_config_id="full",
                        thinking=thinking,
                        format_instruction=format_instruction,
                        format_id=best_format,
                    )
                    writer.writerow(row)
                    csvfile.flush()
                    phase1_rows.append(row)
                    all_rows.append(row)

        # =================================================================
        # Phase 2: Input config grid
        # 8 input configs x 15 positions x thinking on/off = 240 trials
        # =================================================================
        print("\n=== Phase 2: Input Config Grid ===")
        phase2_rows: list[dict] = []
        total_phase2 = len(INPUT_CONFIG_IDS) * len(positions) * 2
        trial_num = 0

        for config_id in INPUT_CONFIG_IDS:
            for pos in positions:
                for thinking in [True, False]:
                    trial_num += 1
                    print(
                        f"  Phase 2 [{trial_num}/{total_phase2}] "
                        f"input={config_id} thinking={thinking} "
                        f"pos={pos.get('position_id', '?')}"
                    )
                    row = run_trial(
                        model=model,
                        position=pos,
                        max_tokens=INPUT_GRID_MAX_TOKENS,
                        input_config_id=config_id,
                        thinking=thinking,
                        format_instruction=format_instruction,
                        format_id=best_format,
                    )
                    writer.writerow(row)
                    csvfile.flush()
                    phase2_rows.append(row)
                    all_rows.append(row)

        # =================================================================
        # Phase 3: Combined best
        # Top 3 inputs x top 3 outputs x 15 positions = 135 trials
        # =================================================================
        print("\n=== Phase 3: Combined Best ===")

        top_outputs = _top_n_by_quality(phase1_rows, "max_tokens", n=3)
        top_inputs = _top_n_by_quality(phase2_rows, "input_config_id", n=3)

        print(f"  Top 3 output token values: {top_outputs}")
        print(f"  Top 3 input configs: {top_inputs}")

        total_phase3 = len(top_inputs) * len(top_outputs) * len(positions)
        trial_num = 0

        for config_id in top_inputs:
            for max_tok_str in top_outputs:
                max_tok = int(max_tok_str)
                for pos in positions:
                    trial_num += 1
                    print(
                        f"  Phase 3 [{trial_num}/{total_phase3}] "
                        f"input={config_id} max_tokens={max_tok} "
                        f"pos={pos.get('position_id', '?')}"
                    )
                    # Phase 3 uses thinking=True (best config exploration)
                    row = run_trial(
                        model=model,
                        position=pos,
                        max_tokens=max_tok,
                        input_config_id=config_id,
                        thinking=True,
                        format_instruction=format_instruction,
                        format_id=best_format,
                    )
                    writer.writerow(row)
                    csvfile.flush()
                    all_rows.append(row)

    # Print summary
    total = len(all_rows)
    avg_quality = sum(r["quality_score"] for r in all_rows) / total if total else 0
    avg_latency = sum(r["latency_ms"] for r in all_rows) / total if total else 0
    truncated_count = sum(1 for r in all_rows if r["truncated"])
    fmt_count = sum(1 for r in all_rows if r["format_compliance"])

    print(f"\n{'='*60}")
    print(f"Experiment 3 complete: {total} trials")
    print(f"  Avg quality score: {avg_quality:.2f} / 4")
    print(f"  Avg latency: {avg_latency:.0f} ms")
    print(f"  Truncated: {truncated_count}/{total} ({100*truncated_count/total:.1f}%)")
    print(f"  Format compliance: {fmt_count}/{total} ({100*fmt_count/total:.1f}%)")
    print(f"  Results written to: {OUTPUT_CSV}")
    print(f"{'='*60}")

    return OUTPUT_CSV


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Experiment 3: Token Budget Experiments")
    parser.add_argument(
        "--model",
        type=str,
        default=None,
        help="Path to GGUF model file (default: Models/qwen3-4b-q4_k_m.gguf)",
    )
    args = parser.parse_args()

    run_experiment(model_path=args.model)
