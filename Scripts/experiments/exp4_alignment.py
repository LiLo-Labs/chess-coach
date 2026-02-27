#!/usr/bin/env python3
"""Experiment 4: Alignment Prompt + Format — does Qwen3-4B reliably score 0-100
and return parseable JSON for PES alignment?

Tests 8 prompt variants x 20 positions (10 book + 10 deviations) x thinking on/off = 320 trials.
Uses llama-cpp-python to load a GGUF model directly (no Ollama).
Outputs results/exp4_alignment.csv
"""

import csv
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

RESULTS_DIR = Path(__file__).parent / "results"
MODEL_PATH = os.environ.get("GGUF_MODEL_PATH", "Qwen3-4B-Q4_K_M.gguf")
MODEL_NAME = "Qwen3-4B-Q4_K_M"
NUM_BOOK = 10
NUM_DEVIATION = 10
MAX_TOKENS = 500

# Qwen3 sampling params
THINKING_PARAMS = {"temperature": 0.6, "top_p": 0.95, "top_k": 20, "min_p": 0.0}
NON_THINKING_PARAMS = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}

# ---------------------------------------------------------------------------
# 8 alignment prompt variants
# ---------------------------------------------------------------------------

VARIANT_IDS = [
    "current",
    "simplified",
    "strict_json",
    "fenced_json",
    "discrete_5",
    "discrete_3",
    "no_rubric",
    "xml_alignment",
]


def _opening_plan_block(pos: dict) -> str:
    """Build THE OPENING PLAN block from position data."""
    parts = []
    if pos.get("plan_summary"):
        parts.append(f"Summary: {pos['plan_summary']}")
    if pos.get("strategic_goals"):
        parts.append(f"Strategic Goals (in priority order):\n{pos['strategic_goals']}")
    if pos.get("pawn_structure_target"):
        parts.append(f"Pawn Structure Target: {pos['pawn_structure_target']}")
    if pos.get("key_squares"):
        parts.append(f"Key Squares: {pos['key_squares']}")
    if pos.get("piece_targets"):
        parts.append(f"Piece Development Targets:\n{pos['piece_targets']}")
    return "\n".join(parts) if parts else "No plan data available."


def _engine_block(pos: dict) -> str:
    """Build ENGINE DATA block."""
    soundness = pos.get("soundness", "?")
    cp_loss = pos.get("cp_loss", "?")
    sf_top = pos.get("stockfish_top3", "N/A")
    return (
        f"Soundness: {soundness}/100 (centipawn loss: {cp_loss})\n"
        f"Stockfish top 3 moves at this position:\n{sf_top}"
    )


def _human_block(pos: dict) -> str:
    """Build HUMAN PLAY DATA block."""
    move_san = pos.get("move_san", "?")
    maia_prob = pos.get("maia_prob", "N/A")
    maia_top = pos.get("maia_top", "N/A")
    polyglot_freq = pos.get("polyglot_freq", "N/A")
    elo = pos.get("user_elo", 1200)
    return (
        f"Maia probability for played move ({move_san}): {maia_prob}\n"
        f"Maia top predictions (what a ~{elo}-rated player would likely play):\n{maia_top}\n"
        f"Polyglot book frequency for this move: {polyglot_freq}"
    )


def _board_context(pos: dict) -> str:
    """Build the shared position context lines."""
    opening = pos.get("opening_name", "Unknown Opening")
    opening_desc = pos.get("opening_description", "")
    color = "White" if pos.get("player_is_white", True) else "Black"
    elo = pos.get("user_elo", 1200)
    move_san = pos.get("move_san", "?")
    move_uci = pos.get("move_uci", "?")
    ply = pos.get("ply", 1)
    move_num = ply // 2 + 1
    move_history = pos.get("move_history", "")
    board_before = pos.get("board_summary_before", pos.get("fen_before", ""))
    board_after = pos.get("board_summary", pos.get("fen_after", ""))

    return (
        f"OPENING: {opening} -- {opening_desc}\n"
        f"STUDENT: {color}, ELO ~{elo}\n"
        f"MOVE PLAYED: {move_san} ({move_uci}) at ply {ply} (move {move_num})\n"
        f"MOVE HISTORY: {move_history}\n\n"
        f"BOARD BEFORE MOVE:\n{board_before}\n\n"
        f"BOARD AFTER MOVE:\n{board_after}"
    )


# -- Rubric + reasoning blocks (reused across variants) --------------------

_RUBRIC_BLOCK = (
    "EVALUATION RUBRIC -- Score 0-100 on plan alignment:\n"
    "1. Development progress: Does this move develop a piece or improve piece activity?\n"
    "2. Pawn structure alignment: Does this maintain or advance the opening's target pawn structure?\n"
    "3. Strategic goal advancement: Does this move work toward the opening's specific objectives?\n"
    "4. King safety: Does this move contribute to getting the king safe?\n"
    "5. Was there a significantly better plan-aligned alternative?"
)

_REASONING_BLOCK = (
    "REASONING REQUIREMENTS:\n"
    "- Lead with what this move accomplishes for the plan\n"
    "- If alignment < 80, briefly mention ONE better alternative and what it achieves -- phrase it "
    "as a constructive tip rather than criticizing the played move\n"
    "- Do NOT say \"However\" or contradict yourself -- frame the reasoning so positive and "
    "constructive parts flow naturally together\n"
    "- Keep reasoning to 2-3 sentences, suitable for a beginner"
)

_JSON_FORMAT_LINE = (
    'Respond in EXACTLY this JSON format (no markdown, no extra text):\n'
    '{"alignment": <0-100>, "reasoning": "<2-3 sentence explanation>", '
    '"rubric": {"development": <true/false>, "pawnStructure": <true/false>, '
    '"strategicGoal": <true/false>, "kingSafety": "<positive/negative/neutral>"}}'
)


# ---------------------------------------------------------------------------
# Variant prompt builders: each returns (system_msg, user_msg)
# ---------------------------------------------------------------------------

def _variant_current(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Reconstruct the existing alignmentPrompt from PromptCatalog."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        "ENGINE DATA:",
        _engine_block(pos),
        "",
        "HUMAN PLAY DATA:",
        _human_block(pos),
        "",
        _RUBRIC_BLOCK,
        "",
        _REASONING_BLOCK,
        "",
        _JSON_FORMAT_LINE,
    ]
    return system_msg, "\n".join(user_parts)


def _variant_simplified(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Remove Maia/Polyglot/Stockfish data -- just board + plan + move."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        _RUBRIC_BLOCK,
        "",
        _REASONING_BLOCK,
        "",
        _JSON_FORMAT_LINE,
    ]
    return system_msg, "\n".join(user_parts)


def _variant_strict_json(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Add strict JSON-only instruction at the end."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        "ENGINE DATA:",
        _engine_block(pos),
        "",
        "HUMAN PLAY DATA:",
        _human_block(pos),
        "",
        _RUBRIC_BLOCK,
        "",
        _REASONING_BLOCK,
        "",
        _JSON_FORMAT_LINE,
        "",
        "Respond ONLY with valid JSON. No other text.",
    ]
    return system_msg, "\n".join(user_parts)


def _variant_fenced_json(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Ask for ```json ... ``` fenced output."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    fenced_format = (
        "Respond with your answer inside a JSON code fence like this:\n"
        "```json\n"
        '{"alignment": <0-100>, "reasoning": "<2-3 sentence explanation>", '
        '"rubric": {"development": <true/false>, "pawnStructure": <true/false>, '
        '"strategicGoal": <true/false>, "kingSafety": "<positive/negative/neutral>"}}\n'
        "```\n"
        "Output only the fenced JSON block, nothing else."
    )

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        "ENGINE DATA:",
        _engine_block(pos),
        "",
        "HUMAN PLAY DATA:",
        _human_block(pos),
        "",
        _RUBRIC_BLOCK,
        "",
        _REASONING_BLOCK,
        "",
        fenced_format,
    ]
    return system_msg, "\n".join(user_parts)


def _variant_discrete_5(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Replace 0-100 with 5 discrete levels: 0, 25, 50, 75, 100."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    discrete_rubric = (
        "EVALUATION RUBRIC -- Score the plan alignment using one of these 5 levels:\n"
        "  0   = Completely unrelated to the opening plan\n"
        "  25  = Weakly related, mostly off-plan\n"
        "  50  = Partially aligned, neutral\n"
        "  75  = Well-aligned with the opening plan\n"
        "  100 = Perfectly aligned, textbook move for this plan\n\n"
        "Consider: development progress, pawn structure alignment, strategic goal advancement, "
        "king safety, and whether a significantly better plan-aligned alternative exists."
    )

    format_line = (
        'Respond in EXACTLY this JSON format (no markdown, no extra text):\n'
        '{"alignment": <0|25|50|75|100>, "reasoning": "<2-3 sentence explanation>", '
        '"rubric": {"development": <true/false>, "pawnStructure": <true/false>, '
        '"strategicGoal": <true/false>, "kingSafety": "<positive/negative/neutral>"}}'
    )

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        "ENGINE DATA:",
        _engine_block(pos),
        "",
        "HUMAN PLAY DATA:",
        _human_block(pos),
        "",
        discrete_rubric,
        "",
        _REASONING_BLOCK,
        "",
        format_line,
    ]
    return system_msg, "\n".join(user_parts)


def _variant_discrete_3(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Replace 0-100 with 3 levels: low (0-33), medium (34-66), high (67-100)."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    discrete_rubric = (
        "EVALUATION RUBRIC -- Score the plan alignment as one of three levels:\n"
        '  "low"    = Poorly aligned (equivalent to 0-33)\n'
        '  "medium" = Partially aligned (equivalent to 34-66)\n'
        '  "high"   = Well aligned (equivalent to 67-100)\n\n'
        "Consider: development progress, pawn structure alignment, strategic goal advancement, "
        "king safety, and whether a significantly better plan-aligned alternative exists."
    )

    format_line = (
        'Respond in EXACTLY this JSON format (no markdown, no extra text):\n'
        '{"alignment": "<low|medium|high>", "reasoning": "<2-3 sentence explanation>", '
        '"rubric": {"development": <true/false>, "pawnStructure": <true/false>, '
        '"strategicGoal": <true/false>, "kingSafety": "<positive/negative/neutral>"}}'
    )

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        "ENGINE DATA:",
        _engine_block(pos),
        "",
        "HUMAN PLAY DATA:",
        _human_block(pos),
        "",
        discrete_rubric,
        "",
        _REASONING_BLOCK,
        "",
        format_line,
    ]
    return system_msg, "\n".join(user_parts)


def _variant_no_rubric(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Just alignment + reasoning, drop the rubric sub-object."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    format_line = (
        'Respond in EXACTLY this JSON format (no markdown, no extra text):\n'
        '{"alignment": <0-100>, "reasoning": "<2-3 sentence explanation>"}'
    )

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        "ENGINE DATA:",
        _engine_block(pos),
        "",
        "HUMAN PLAY DATA:",
        _human_block(pos),
        "",
        _RUBRIC_BLOCK,
        "",
        _REASONING_BLOCK,
        "",
        format_line,
    ]
    return system_msg, "\n".join(user_parts)


def _variant_xml_alignment(pos: dict, is_book_move: bool, thinking: bool) -> tuple[str, str]:
    """Use XML tags for output."""
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"You are evaluating a chess move for plan alignment in an opening trainer. {think_tag}"

    format_line = (
        "Respond using ONLY these XML tags (no other text):\n"
        "<alignment>0-100</alignment>\n"
        "<reasoning>2-3 sentence explanation</reasoning>"
    )

    user_parts = [
        _board_context(pos),
        "",
        "THE OPENING PLAN:",
        _opening_plan_block(pos),
        "",
        "ENGINE DATA:",
        _engine_block(pos),
        "",
        "HUMAN PLAY DATA:",
        _human_block(pos),
        "",
        _RUBRIC_BLOCK,
        "",
        _REASONING_BLOCK,
        "",
        format_line,
    ]
    return system_msg, "\n".join(user_parts)


# Map variant IDs to builder functions
VARIANT_BUILDERS = {
    "current": _variant_current,
    "simplified": _variant_simplified,
    "strict_json": _variant_strict_json,
    "fenced_json": _variant_fenced_json,
    "discrete_5": _variant_discrete_5,
    "discrete_3": _variant_discrete_3,
    "no_rubric": _variant_no_rubric,
    "xml_alignment": _variant_xml_alignment,
}


# ---------------------------------------------------------------------------
# Parsing helpers -- extract alignment score from various formats
# ---------------------------------------------------------------------------

def parse_alignment_json(text: str) -> dict | None:
    """Parse a plain JSON response. Returns dict with alignment + reasoning or None."""
    text = text.strip()
    # Try direct parse
    try:
        obj = json.loads(text)
        if isinstance(obj, dict) and "alignment" in obj:
            return obj
    except json.JSONDecodeError:
        pass

    # Try to find JSON object in the text
    match = re.search(r"\{[^{}]*\"alignment\"[^{}]*\}", text, re.DOTALL)
    if match:
        try:
            obj = json.loads(match.group(0))
            if isinstance(obj, dict) and "alignment" in obj:
                return obj
        except json.JSONDecodeError:
            pass

    # Try more permissive: find any { ... } and parse
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            obj = json.loads(match.group(0))
            if isinstance(obj, dict) and "alignment" in obj:
                return obj
        except json.JSONDecodeError:
            pass

    return None


def parse_alignment_fenced_json(text: str) -> dict | None:
    """Parse a ```json ... ``` fenced response."""
    fence_match = re.search(r"```(?:json)?\s*\n?(.*?)\n?\s*```", text, re.DOTALL)
    if fence_match:
        return parse_alignment_json(fence_match.group(1))
    # Fall back to plain JSON parse
    return parse_alignment_json(text)


def parse_alignment_xml(text: str) -> dict | None:
    """Parse XML-tagged alignment response."""
    alignment_match = re.search(r"<alignment>\s*(\d+)\s*</alignment>", text)
    reasoning_match = re.search(r"<reasoning>(.*?)</reasoning>", text, re.DOTALL)

    if alignment_match:
        try:
            score = int(alignment_match.group(1))
            reasoning = reasoning_match.group(1).strip() if reasoning_match else ""
            return {"alignment": score, "reasoning": reasoning}
        except (ValueError, IndexError):
            pass
    return None


def parse_discrete_3_score(value) -> int | None:
    """Convert a discrete-3 level string to a numeric 0-100 score."""
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        v = value.strip().lower()
        mapping = {"low": 16, "medium": 50, "high": 83}
        if v in mapping:
            return mapping[v]
        # Try numeric parse
        try:
            return int(v)
        except ValueError:
            pass
    return None


def extract_alignment_score(variant_id: str, raw_response: str) -> tuple[bool, int | None, bool]:
    """Extract alignment score from a raw response based on the variant format.

    Returns (json_parse_success, alignment_score, reasoning_present).
    """
    if not raw_response or not raw_response.strip():
        return False, None, False

    text = raw_response.strip()

    # Strip thinking tags if present
    think_match = re.search(r"</think>\s*(.*)", text, re.DOTALL)
    if think_match:
        text = think_match.group(1).strip()

    parsed = None

    if variant_id == "xml_alignment":
        parsed = parse_alignment_xml(text)
    elif variant_id == "fenced_json":
        parsed = parse_alignment_fenced_json(text)
    else:
        # All other variants use JSON (plain, strict, discrete, no_rubric, etc.)
        parsed = parse_alignment_json(text)

    if parsed is None:
        return False, None, False

    raw_score = parsed.get("alignment")
    reasoning = parsed.get("reasoning", "")
    reasoning_present = bool(reasoning and str(reasoning).strip())

    # Convert score to 0-100 integer
    if variant_id == "discrete_3":
        score = parse_discrete_3_score(raw_score)
    elif variant_id == "discrete_5":
        if isinstance(raw_score, (int, float)):
            score = int(raw_score)
            if score not in (0, 25, 50, 75, 100):
                # Accept anyway but clamp to nearest
                nearest = min([0, 25, 50, 75, 100], key=lambda x: abs(x - score))
                score = nearest
        else:
            try:
                score = int(raw_score)
            except (ValueError, TypeError):
                score = None
    else:
        try:
            score = int(raw_score)
        except (ValueError, TypeError):
            score = None

    if score is not None:
        score = max(0, min(100, score))

    return True, score, reasoning_present


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
# Position selection
# ---------------------------------------------------------------------------

def select_positions(all_positions: list[dict]) -> list[tuple[dict, bool]]:
    """Select 10 book-move positions and 10 deviation positions.

    Returns list of (position_dict, is_book_move) tuples.
    """
    book_candidates = []
    deviation_candidates = []

    for pos in all_positions:
        # A position with a wrong_move field can serve as a deviation
        if pos.get("wrong_move"):
            deviation_candidates.append(pos)
        # All positions can serve as book-move positions (using the book move)
        if pos.get("book_move") or pos.get("move_san"):
            book_candidates.append(pos)

    import random

    # Select up to NUM_BOOK book positions
    if len(book_candidates) > NUM_BOOK:
        book_selected = random.sample(book_candidates, NUM_BOOK)
    else:
        book_selected = book_candidates[:NUM_BOOK]

    # Select up to NUM_DEVIATION deviation positions
    if len(deviation_candidates) > NUM_DEVIATION:
        dev_selected = random.sample(deviation_candidates, NUM_DEVIATION)
    else:
        dev_selected = deviation_candidates[:NUM_DEVIATION]

    result = []
    for pos in book_selected:
        # For book moves, use the book_move as the move_san
        enriched = dict(pos)
        if pos.get("book_move"):
            enriched["move_san"] = pos["book_move"]
        result.append((enriched, True))

    for pos in dev_selected:
        # For deviations, use the wrong_move
        enriched = dict(pos)
        enriched["move_san"] = pos["wrong_move"]
        result.append((enriched, False))

    return result


# ---------------------------------------------------------------------------
# Trial runner
# ---------------------------------------------------------------------------

def run_trial(
    model,
    position: dict,
    variant_id: str,
    is_book_move: bool,
    thinking: bool,
) -> dict:
    """Run a single alignment trial.

    Returns a dict with all measurements.
    """
    builder = VARIANT_BUILDERS[variant_id]
    system_msg, user_msg = builder(position, is_book_move, thinking)
    params = THINKING_PARAMS if thinking else NON_THINKING_PARAMS

    t0 = time.perf_counter()
    try:
        output = model.create_chat_completion(
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user", "content": user_msg},
            ],
            max_tokens=MAX_TOKENS,
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

    # Parse alignment
    json_parse_success, alignment_score, reasoning_present = extract_alignment_score(
        variant_id, response_text
    )

    return {
        "response_text": response_text,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "latency_ms": round(latency_ms, 1),
        "json_parse_success": json_parse_success,
        "alignment_score": alignment_score,
        "reasoning_present": reasoning_present,
        "system_msg": system_msg,
        "user_msg": user_msg,
    }


# ---------------------------------------------------------------------------
# Summary statistics
# ---------------------------------------------------------------------------

def compute_summary(rows: list[dict]) -> None:
    """Print per-variant summary: parse rate, avg scores, score separation."""
    from collections import defaultdict

    stats = defaultdict(lambda: {
        "total": 0,
        "parsed": 0,
        "book_scores": [],
        "dev_scores": [],
        "reasoning_present": 0,
    })

    for row in rows:
        vid = row["variant_id"]
        s = stats[vid]
        s["total"] += 1
        if row["json_parse_success"] == "True" or row["json_parse_success"] is True:
            s["parsed"] += 1
        if row["reasoning_present"] == "True" or row["reasoning_present"] is True:
            s["reasoning_present"] += 1
        score = row.get("alignment_score")
        if score is not None and score != "":
            try:
                score_val = int(score) if not isinstance(score, int) else score
            except (ValueError, TypeError):
                continue
            if row["is_book_move"] == "True" or row["is_book_move"] is True:
                s["book_scores"].append(score_val)
            else:
                s["dev_scores"].append(score_val)

    print("\n" + "=" * 90)
    print("EXPERIMENT 4 SUMMARY: Alignment Prompt Variants")
    print("=" * 90)
    print(
        f"{'Variant':<18} {'Parse%':>7} {'Reason%':>8} "
        f"{'Book Avg':>9} {'Dev Avg':>8} {'Separation':>11} {'N':>4}"
    )
    print("-" * 90)

    for vid in VARIANT_IDS:
        s = stats[vid]
        if s["total"] == 0:
            continue
        parse_pct = 100.0 * s["parsed"] / s["total"]
        reason_pct = 100.0 * s["reasoning_present"] / s["total"]
        book_avg = sum(s["book_scores"]) / len(s["book_scores"]) if s["book_scores"] else float("nan")
        dev_avg = sum(s["dev_scores"]) / len(s["dev_scores"]) if s["dev_scores"] else float("nan")
        separation = book_avg - dev_avg if s["book_scores"] and s["dev_scores"] else float("nan")
        print(
            f"{vid:<18} {parse_pct:>6.1f}% {reason_pct:>7.1f}% "
            f"{book_avg:>9.1f} {dev_avg:>8.1f} {separation:>+10.1f} {s['total']:>4}"
        )

    print("-" * 90)
    print("Score separation = avg(book_scores) - avg(deviation_scores). HIGHER IS BETTER.")
    print("Book moves: expect alignment > 70.  Deviations: expect alignment < 50.")
    print()


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
    "is_book_move",
    "max_tokens",
    "tokens_in",
    "tokens_out",
    "json_parse_success",
    "alignment_score",
    "reasoning_present",
    "latency_ms",
    "raw_prompt",
    "raw_response",
    "params_json",
]


def run_experiment(model_path: str | None = None) -> Path:
    """Run the full Experiment 4 and write results to CSV.

    Returns the path to the output CSV.
    """
    experiment_id = f"exp4_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = RESULTS_DIR / "exp4_alignment.csv"

    # Load test positions
    positions_file = Path(__file__).parent / "test_positions.json"
    if not positions_file.exists():
        print(f"ERROR: {positions_file} not found. Please create it first.")
        sys.exit(1)

    with open(positions_file) as f:
        all_positions = json.load(f)

    # Select 10 book + 10 deviation positions
    test_cases = select_positions(all_positions)
    n_book = sum(1 for _, b in test_cases if b)
    n_dev = sum(1 for _, b in test_cases if not b)
    print(f"Selected {n_book} book-move positions and {n_dev} deviation positions.")

    # Load model
    model = load_model(model_path)

    # Total trials: 8 variants x 20 positions x 2 thinking modes = 320
    total_trials = len(VARIANT_IDS) * len(test_cases) * 2
    print(
        f"Running {total_trials} trials "
        f"({len(VARIANT_IDS)} variants x {len(test_cases)} positions x 2 thinking modes)"
    )
    print(f"Output: {csv_path}")
    print()

    trial_count = 0
    all_rows = []

    with open(csv_path, "w", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=CSV_COLUMNS)
        writer.writeheader()

        for variant_id in VARIANT_IDS:
            for position, is_book_move in test_cases:
                for thinking in [True, False]:
                    trial_count += 1
                    trial_id = str(uuid.uuid4())[:12]
                    thinking_label = "thinking" if thinking else "non_thinking"
                    params = THINKING_PARAMS if thinking else NON_THINKING_PARAMS
                    position_id = position.get("position_id", position.get("fen_after", "unknown")[:20])
                    book_label = "book" if is_book_move else "deviation"

                    print(
                        f"  [{trial_count}/{total_trials}] {variant_id} | "
                        f"{position_id} | {thinking_label} | {book_label}"
                    )

                    result = run_trial(model, position, variant_id, is_book_move, thinking)

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
                        "variant_id": variant_id,
                        "thinking_mode": thinking_label,
                        "is_book_move": is_book_move,
                        "max_tokens": MAX_TOKENS,
                        "tokens_in": result["tokens_in"],
                        "tokens_out": result["tokens_out"],
                        "json_parse_success": result["json_parse_success"],
                        "alignment_score": result["alignment_score"] if result["alignment_score"] is not None else "",
                        "reasoning_present": result["reasoning_present"],
                        "latency_ms": result["latency_ms"],
                        "raw_prompt": raw_prompt,
                        "raw_response": result["response_text"],
                        "params_json": json.dumps(params),
                    }
                    writer.writerow(row)
                    all_rows.append(row)

    print()
    print(f"Done. {trial_count} trials written to {csv_path}")

    # Print summary
    compute_summary(all_rows)

    return csv_path


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    path_arg = sys.argv[1] if len(sys.argv) > 1 else None
    result_path = run_experiment(model_path=path_arg)
    print(f"\nResults: {result_path}")
