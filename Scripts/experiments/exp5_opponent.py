#!/usr/bin/env python3
"""Experiment 5: Opponent Move Coaching — tests prompt variants for explaining the opponent's move.

8 prompt variants x 10 positions x thinking on/off = 160 trials.
Uses llama-cpp-python to load GGUF directly (no Ollama).
Outputs results/exp5_opponent.csv
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

# Add parent dir for imports
sys.path.insert(0, str(Path(__file__).parent))
from evaluator import (
    format_ok,
    hallucination_score,
    mentions_opening as eval_mentions_opening,
    mentions_move as eval_mentions_move,
    word_count,
)

RESULTS_DIR = Path(__file__).parent / "results"
MODEL_PATH = os.environ.get("GGUF_MODEL_PATH", "Qwen3-4B-Q4_K_M.gguf")
MODEL_NAME = "Qwen3-4B-Q4_K_M"
NUM_POSITIONS = 10
MAX_TOKENS = 200

# Qwen3 sampling params
THINKING_PARAMS = {"temperature": 0.6, "top_p": 0.95, "top_k": 20, "min_p": 0.0}
NON_THINKING_PARAMS = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}


# ---------------------------------------------------------------------------
# Determine best format from Experiment 1 results
# ---------------------------------------------------------------------------

def determine_best_format() -> str:
    """Read exp1 results CSV and return the variant_id with highest format_compliance rate.

    Falls back to 'refs_coaching' if the CSV is missing or unreadable.
    """
    exp1_csv = RESULTS_DIR / "exp1_formats.csv"
    if not exp1_csv.exists():
        return "refs_coaching"

    try:
        variant_stats: dict[str, dict] = {}  # variant_id -> {total, compliant}
        with open(exp1_csv, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                vid = row.get("variant_id", "")
                if not vid:
                    continue
                if vid not in variant_stats:
                    variant_stats[vid] = {"total": 0, "compliant": 0}
                variant_stats[vid]["total"] += 1
                if row.get("format_compliance", "").lower() in ("true", "1", "yes"):
                    variant_stats[vid]["compliant"] += 1

        if not variant_stats:
            return "refs_coaching"

        best_vid = max(
            variant_stats,
            key=lambda v: variant_stats[v]["compliant"] / max(variant_stats[v]["total"], 1),
        )
        return best_vid
    except Exception:
        return "refs_coaching"


def get_format_instruction(format_id: str) -> str:
    """Return the format instruction string for a given format variant id.

    This maps the best format from exp1 to its instruction text so that
    prompt variants can embed the chosen output format consistently.
    """
    FORMAT_INSTRUCTIONS = {
        "refs_coaching": (
            "Response format (REQUIRED):\n"
            "REFS: <list each piece and square you mention, e.g. \"bishop e5, knight c3\". "
            "Write \"none\" if you don't reference specific pieces>\n"
            "COACHING: <your coaching text>"
        ),
        "coaching_only": (
            "Respond with only a short coaching explanation (one or two sentences). "
            "Do not include any structured data, labels, or formatting -- just plain coaching text."
        ),
        "json_flat": (
            "Respond with a single JSON object on one line containing two keys:\n"
            "- \"coaching\": a short coaching explanation\n"
            "- \"refs\": an array of referenced squares or pieces\n"
            "Output only the JSON, nothing else."
        ),
        "json_nested": (
            "Respond with a JSON object containing:\n"
            "- \"coaching\": a short explanation\n"
            "- \"refs\": an array of referenced squares or pieces\n"
            "- \"quality\": one of \"good\", \"neutral\", or \"bad\" describing the position\n"
            "Output only the JSON, nothing else."
        ),
        "xml_tags": (
            "Respond using XML tags. Use <refs> for referenced squares/pieces and "
            "<coaching> for the explanation. Output only the XML, nothing else."
        ),
        "xml_cdata": (
            "Respond using XML tags with CDATA sections:\n"
            "<refs><![CDATA[...]]></refs>\n"
            "<coaching><![CDATA[...]]></coaching>\n"
            "Output only the XML, nothing else."
        ),
        "markdown_headers": (
            "Respond using Markdown with two sections:\n"
            "## Refs\n"
            "<comma-separated squares or pieces>\n\n"
            "## Coaching\n"
            "<one or two sentences>"
        ),
        "numbered_lines": (
            "Respond with exactly two numbered lines:\n"
            "1. REFS: <comma-separated squares or pieces>\n"
            "2. COACHING: <one or two sentences>"
        ),
        "yaml_format": (
            "Respond in YAML format with two keys: refs (a list) and coaching (a string).\n"
            "Output only the YAML, nothing else."
        ),
        "pipe_delimited": (
            "Respond with a single line using pipe (|) as delimiter:\n"
            "refs|coaching\n"
            "Where refs is a comma-separated list and coaching is a short explanation."
        ),
        "single_line_json": (
            "Respond with a compact JSON object using short keys:\n"
            "{\"r\": \"<comma-separated refs>\", \"c\": \"<coaching text>\"}\n"
            "Output only the JSON, nothing else."
        ),
        "fenced_json": (
            "Respond with a JSON object inside a Markdown code fence:\n"
            "```json\n"
            "{\"coaching\": \"...\", \"refs\": [\"...\"]}\n"
            "```\n"
            "Output only the fenced JSON, nothing else."
        ),
    }
    return FORMAT_INSTRUCTIONS.get(format_id, FORMAT_INSTRUCTIONS["refs_coaching"])


# ---------------------------------------------------------------------------
# 8 prompt variants
# ---------------------------------------------------------------------------

def _build_current(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 1: current — existing opponentMovePrompt from PromptCatalog."""
    elo = pos.get("elo", 1200)
    level = "beginner" if elo < 1000 else "intermediate" if elo < 1600 else "advanced"
    opening = pos.get("opening_name", "Italian Game")
    # Determine student/opponent colors from the position
    # Odd ply = opponent (white) just moved, student is black
    is_white_move = pos.get("is_white_move", True)
    if is_white_move:
        color = "Black"
        opponent_color = "White"
    else:
        color = "White"
        opponent_color = "Black"

    move = pos.get("book_move_san", "")
    explanation = pos.get("move_explanation", "")
    ply = pos.get("ply", 1)
    move_number = ply // 2 + 1
    main_line = pos.get("main_line_so_far", "")
    board_state = pos.get("board_summary", "")

    guidance = (
        f"The opponent played {move}. Explain WHY the opponent wants to make this move "
        f"-- what is the opponent trying to achieve? {explanation} "
        f"Help the student understand the opponent's reasoning so they can anticipate it in future games."
    )

    system_msg = (
        f"You are a chess coach inside an opening trainer app. Your student "
        f"(ELO ~{elo}, {level}) is learning the {opening} as {color}. "
        f"The app plays the {opponent_color} side automatically. Your job is to help the student "
        f"understand what the opponent's move means for THEIR position and THEIR plan.\n"
        f"System: {opening}\n"
        f"Main line so far: {main_line}\n\n"
        f"The OPPONENT ({opponent_color}) just played: {move} (move {move_number})\n\n"
        f"Current board position:\n{board_state}\n\n"
        f"{guidance}\n\n"
        f"{format_instruction}\n\n"
        f"Rules:\n"
        f"- ONLY reference pieces that exist on the squares listed above.\n"
        f"- REFS must exactly match pieces you mention in COACHING.\n"
        f"- Address the student as \"you\". Say \"your opponent\" or \"they\" for the other side.\n"
        f"- When naming pieces, always specify the color: \"{opponent_color}'s knight\" not just \"the knight\".\n"
        f"- Frame it from the student's perspective: what does this opponent move mean for YOU?\n"
        f"- ONE or TWO short sentences (max 25 words total).\n"
        f"- Relate to the {opening} system.\n"
        f"- Use simple language. Spell out piece names, no algebraic notation."
    )
    user_msg = f"Explain the opponent's move {move} in this position."
    return system_msg, user_msg


def _build_minimal(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 2: minimal — bare-bones one-sentence prompt."""
    move = pos.get("book_move_san", "")
    system_msg = "You are a chess coach."
    user_msg = f"Opponent played {move}. Why? One sentence."
    return system_msg, user_msg


def _build_perspective_flip(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 3: perspective_flip — coach speaks as the opponent."""
    move = pos.get("book_move_san", "")
    opening = pos.get("opening_name", "Italian Game")
    board_state = pos.get("board_summary", "")

    system_msg = (
        f"You are the opponent in a chess opening trainer. "
        f"You just played {move} in the {opening}. "
        f"Explain your move to a student watching."
    )
    user_msg = (
        f"Current board position:\n{board_state}\n\n"
        f"You just played {move}. Explain your move to the student who is learning this opening.\n\n"
        f"{format_instruction}"
    )
    return system_msg, user_msg


def _build_threat_focused(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 4: threat_focused — focus on threats and responses."""
    move = pos.get("book_move_san", "")
    opening = pos.get("opening_name", "Italian Game")
    board_state = pos.get("board_summary", "")

    system_msg = "You are a chess coach helping a student understand opponent threats."
    user_msg = (
        f"Opening: {opening}\n"
        f"Board position:\n{board_state}\n\n"
        f"What threat does {move} create? How should the student respond?\n\n"
        f"{format_instruction}"
    )
    return system_msg, user_msg


def _build_plan_context(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 5: plan_context — include the opening plan in the prompt."""
    move = pos.get("book_move_san", "")
    opening = pos.get("opening_name", "Italian Game")
    board_state = pos.get("board_summary", "")
    plan_summary = pos.get("plan_summary", "")
    strategic_goals = pos.get("strategic_goals", [])
    goals_text = "\n".join(f"- {g}" for g in strategic_goals) if strategic_goals else "N/A"

    system_msg = "You are a chess coach explaining opponent moves in the context of the opening plan."
    user_msg = (
        f"Opening: {opening}\n"
        f"Plan summary: {plan_summary}\n"
        f"Strategic goals:\n{goals_text}\n\n"
        f"Board position:\n{board_state}\n\n"
        f"Relative to the {opening} plan, the opponent played {move}. "
        f"Explain how this move fits into or disrupts the opening plan.\n\n"
        f"{format_instruction}"
    )
    return system_msg, user_msg


def _build_compare(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 6: compare — compare with what student might have expected."""
    move = pos.get("book_move_san", "")
    opening = pos.get("opening_name", "Italian Game")
    board_state = pos.get("board_summary", "")

    system_msg = "You are a chess coach helping a student understand opening moves."
    user_msg = (
        f"Opening: {opening}\n"
        f"Board position:\n{board_state}\n\n"
        f"Compare {move} with what the student might have expected. "
        f"What makes this move the book choice?\n\n"
        f"{format_instruction}"
    )
    return system_msg, user_msg


def _build_q_and_a(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 7: q_and_a — simple Q&A format."""
    move = pos.get("book_move_san", "")
    opening = pos.get("opening_name", "Italian Game")
    board_state = pos.get("board_summary", "")

    system_msg = "You are a chess coach. Answer concisely."
    user_msg = (
        f"Opening: {opening}\n"
        f"Board position:\n{board_state}\n\n"
        f"Q: Why did the opponent play {move}?\nA:"
    )
    return system_msg, user_msg


def _build_no_format_rules(pos: dict, format_instruction: str) -> tuple[str, str]:
    """Variant 8: no_format_rules — current prompt but remove all format/rules instructions."""
    elo = pos.get("elo", 1200)
    level = "beginner" if elo < 1000 else "intermediate" if elo < 1600 else "advanced"
    opening = pos.get("opening_name", "Italian Game")
    is_white_move = pos.get("is_white_move", True)
    if is_white_move:
        color = "Black"
        opponent_color = "White"
    else:
        color = "White"
        opponent_color = "Black"

    move = pos.get("book_move_san", "")
    explanation = pos.get("move_explanation", "")
    ply = pos.get("ply", 1)
    move_number = ply // 2 + 1
    main_line = pos.get("main_line_so_far", "")
    board_state = pos.get("board_summary", "")

    guidance = (
        f"The opponent played {move}. Explain WHY the opponent wants to make this move "
        f"-- what is the opponent trying to achieve? {explanation} "
        f"Help the student understand the opponent's reasoning so they can anticipate it in future games."
    )

    # Same as current but WITHOUT format instruction and rules
    system_msg = (
        f"You are a chess coach inside an opening trainer app. Your student "
        f"(ELO ~{elo}, {level}) is learning the {opening} as {color}. "
        f"The app plays the {opponent_color} side automatically. Your job is to help the student "
        f"understand what the opponent's move means for THEIR position and THEIR plan.\n"
        f"System: {opening}\n"
        f"Main line so far: {main_line}\n\n"
        f"The OPPONENT ({opponent_color}) just played: {move} (move {move_number})\n\n"
        f"Current board position:\n{board_state}\n\n"
        f"{guidance}"
    )
    user_msg = f"Explain the opponent's move {move} in this position."
    return system_msg, user_msg


PROMPT_VARIANTS = [
    {"id": "current",          "name": "Current opponentMovePrompt",       "builder": _build_current},
    {"id": "minimal",          "name": "Minimal one-sentence",             "builder": _build_minimal},
    {"id": "perspective_flip", "name": "Perspective flip (speak as opp.)",  "builder": _build_perspective_flip},
    {"id": "threat_focused",   "name": "Threat focused",                   "builder": _build_threat_focused},
    {"id": "plan_context",     "name": "Plan context",                     "builder": _build_plan_context},
    {"id": "compare",          "name": "Compare with expectations",        "builder": _build_compare},
    {"id": "q_and_a",          "name": "Q&A format",                       "builder": _build_q_and_a},
    {"id": "no_format_rules",  "name": "No format/rules (context only)",   "builder": _build_no_format_rules},
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
# Position selection: pick 10 positions where ply is odd (opponent moves)
# ---------------------------------------------------------------------------

def select_opponent_positions(all_positions: list[dict], count: int = NUM_POSITIONS) -> list[dict]:
    """Select positions where ply is odd (opponent moves).

    In the Italian Game as White, odd-ply positions correspond to Black's
    (opponent's) moves. We select these to test opponent-move coaching.
    If not enough odd-ply positions, we include even-ply ones with flipped
    perspective.
    """
    odd_ply = [p for p in all_positions if p.get("ply", 0) % 2 == 1]

    if len(odd_ply) >= count:
        # Sort by ply for spread, then sample evenly
        odd_ply.sort(key=lambda p: p["ply"])
        step = max(len(odd_ply) // count, 1)
        selected = [odd_ply[i * step] for i in range(min(count, len(odd_ply)))]
        return selected[:count]

    # Not enough odd-ply; supplement with even-ply (flip perspective)
    selected = list(odd_ply)
    even_ply = [p for p in all_positions if p.get("ply", 0) % 2 == 0 and p.get("ply", 0) > 0]
    needed = count - len(selected)
    even_ply.sort(key=lambda p: p["ply"])
    step = max(len(even_ply) // needed, 1) if needed > 0 else 1
    for i in range(min(needed, len(even_ply))):
        pos = dict(even_ply[i * step])
        # Flip perspective: swap is_white_move
        pos["is_white_move"] = not pos.get("is_white_move", True)
        selected.append(pos)

    return selected[:count]


# ---------------------------------------------------------------------------
# Evaluation helpers
# ---------------------------------------------------------------------------

def evaluate_response(response_text: str, position: dict, best_format: str) -> dict:
    """Evaluate a response for opponent-move coaching quality.

    Returns dict with: format_compliance, hallucination_detected, mentions_opening,
    mentions_move, word_count, perspective_correct
    """
    result = {
        "format_compliance": False,
        "hallucination_detected": False,
        "mentions_opening": False,
        "mentions_move": False,
        "word_count": 0,
        "perspective_correct": False,
    }

    if not response_text or not response_text.strip():
        return result

    text = response_text.strip()

    # format_compliance: does the response follow the best format from exp1?
    try:
        result["format_compliance"] = format_ok(text, best_format)
    except Exception:
        result["format_compliance"] = False

    # hallucination_detected
    try:
        h_score = hallucination_score(text, position.get("fen_after", position.get("fen_before", "")))
        result["hallucination_detected"] = h_score > 0.5
    except Exception:
        result["hallucination_detected"] = False

    # mentions_opening
    opening_name = position.get("opening_name", "")
    if opening_name:
        result["mentions_opening"] = eval_mentions_opening(text, opening_name)

    # mentions_move
    move_san = position.get("book_move_san", "")
    if move_san:
        result["mentions_move"] = eval_mentions_move(text, move_san)

    # word_count
    result["word_count"] = word_count(text)

    # perspective_correct: does the response address the student with "you"/"your"?
    text_lower = text.lower()
    result["perspective_correct"] = bool(
        re.search(r"\byou\b", text_lower) or re.search(r"\byour\b", text_lower)
    )

    return result


# ---------------------------------------------------------------------------
# Trial runner
# ---------------------------------------------------------------------------

def run_trial(
    model,
    position: dict,
    variant: dict,
    thinking: bool,
    best_format: str,
    format_instruction: str,
) -> dict:
    """Run a single trial: generate a response and evaluate it.

    Returns a dict with all measurements.
    """
    builder = variant["builder"]
    system_msg, user_msg = builder(position, format_instruction)

    # Add thinking mode tag to system message
    think_tag = "/think" if thinking else "/no_think"
    system_msg = f"{system_msg}\n{think_tag}"

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

    # Evaluate
    eval_result = evaluate_response(response_text, position, best_format)

    return {
        "response_text": response_text,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "latency_ms": round(latency_ms, 1),
        "format_compliance": eval_result["format_compliance"],
        "hallucination_detected": eval_result["hallucination_detected"],
        "mentions_opening": eval_result["mentions_opening"],
        "mentions_move": eval_result["mentions_move"],
        "word_count": eval_result["word_count"],
        "perspective_correct": eval_result["perspective_correct"],
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
    "hallucination_detected",
    "mentions_opening",
    "mentions_move",
    "word_count",
    "perspective_correct",
    "latency_ms",
    "raw_prompt",
    "raw_response",
    "params_json",
]


def run_experiment(model_path: str | None = None) -> Path:
    """Run the full Experiment 5 and write results to CSV.

    Returns the path to the output CSV.
    """
    experiment_id = f"exp5_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = RESULTS_DIR / "exp5_opponent.csv"

    # Determine best format from exp1
    best_format = determine_best_format()
    format_instruction = get_format_instruction(best_format)
    print(f"Best format from exp1: {best_format}")

    # Load test positions
    positions_file = Path(__file__).parent / "test_positions.json"
    if not positions_file.exists():
        print(f"ERROR: {positions_file} not found. Please create it first.")
        sys.exit(1)

    with open(positions_file) as f:
        all_positions = json.load(f)

    # Select 10 opponent-move positions (odd ply)
    positions = select_opponent_positions(all_positions, NUM_POSITIONS)
    print(f"Using {len(positions)} opponent-move positions.")

    # Load model
    model = load_model(model_path)

    # Total trials: 8 variants x 10 positions x 2 thinking modes = 160
    total_trials = len(PROMPT_VARIANTS) * len(positions) * 2
    print(
        f"Running {total_trials} trials "
        f"({len(PROMPT_VARIANTS)} variants x {len(positions)} positions x 2 thinking modes)"
    )
    print(f"Output: {csv_path}")
    print()

    trial_count = 0

    with open(csv_path, "w", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=CSV_COLUMNS)
        writer.writeheader()

        for variant in PROMPT_VARIANTS:
            for position in positions:
                for thinking in [True, False]:
                    trial_count += 1
                    trial_id = str(uuid.uuid4())[:12]
                    thinking_label = "thinking" if thinking else "non_thinking"
                    params = THINKING_PARAMS if thinking else NON_THINKING_PARAMS
                    position_id = position.get(
                        "position_id",
                        position.get("id", position.get("fen_before", "unknown")[:20]),
                    )

                    print(
                        f"  [{trial_count}/{total_trials}] {variant['id']} | "
                        f"{position_id} | {thinking_label}"
                    )

                    result = run_trial(
                        model, position, variant, thinking, best_format, format_instruction
                    )

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
                        "max_tokens": MAX_TOKENS,
                        "tokens_in": result["tokens_in"],
                        "tokens_out": result["tokens_out"],
                        "format_compliance": result["format_compliance"],
                        "hallucination_detected": result["hallucination_detected"],
                        "mentions_opening": result["mentions_opening"],
                        "mentions_move": result["mentions_move"],
                        "word_count": result["word_count"],
                        "perspective_correct": result["perspective_correct"],
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
