#!/usr/bin/env python3
"""
Experiment 2: Prompt Architecture Sweep
========================================
Tests 15 radically different prompt structures for coaching responses.

Uses llama-cpp-python to load Qwen3-4B GGUF directly (no Ollama).

Design matrix:
  15 prompt variants x 15 positions x 3 move categories x 2 thinking modes = 1350 trials

Outputs: results/exp2_prompts.csv
"""

import csv
import json
import os
import re
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import chess
from llama_cpp import Llama

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
RESULTS_DIR = SCRIPT_DIR / "results"
POSITIONS_PATH = SCRIPT_DIR / "test_positions.json"
EXP1_RESULTS_PATH = RESULTS_DIR / "exp1_formats.csv"
OUTPUT_PATH = RESULTS_DIR / "exp2_prompts.csv"

DEFAULT_MODEL_PATH = str(
    SCRIPT_DIR.parent.parent
    / "Models"
    / "Qwen3-4B-Q4_K_M.gguf"
)

EXPERIMENT_ID = "exp2_prompts"
MODEL_NAME = "qwen3-4b"

NUM_POSITIONS = 15
MOVE_CATEGORIES = ["good", "okay", "mistake"]

# Fixed sampling parameters
THINKING_PARAMS = {"temperature": 0.6, "top_p": 0.95, "top_k": 20, "min_p": 0.0}
NON_THINKING_PARAMS = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}
MAX_TOKENS = 200

CSV_COLUMNS = [
    "experiment_id",
    "trial_id",
    "timestamp",
    "model",
    "position_id",
    "variant_id",
    "move_category",
    "thinking_mode",
    "max_tokens",
    "tokens_in",
    "tokens_out",
    "format_compliance",
    "hallucination_detected",
    "mentions_opening",
    "mentions_move",
    "word_count",
    "latency_ms",
    "coaching_correctness",
    "raw_prompt",
    "raw_response",
    "params_json",
]


# ===========================================================================
# Determine best format from Experiment 1
# ===========================================================================

def determine_best_format() -> str:
    """
    Read results/exp1_formats.csv, find the format_id with the highest average
    format_compliance score. Falls back to 'refs_coaching' if the file is
    missing or unreadable.
    """
    if not EXP1_RESULTS_PATH.exists():
        print("[exp2] exp1 results not found, falling back to 'refs_coaching'")
        return "refs_coaching"

    try:
        with open(EXP1_RESULTS_PATH, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            scores: dict[str, list[float]] = {}
            for row in reader:
                fmt = row.get("format_id", "")
                compliance = row.get("format_compliance", "")
                if fmt and compliance:
                    try:
                        scores.setdefault(fmt, []).append(float(compliance))
                    except ValueError:
                        continue

        if not scores:
            return "refs_coaching"

        best_format = max(scores, key=lambda k: sum(scores[k]) / len(scores[k]))
        best_avg = sum(scores[best_format]) / len(scores[best_format])
        print(f"[exp2] Best format from exp1: {best_format} (avg compliance={best_avg:.3f})")
        return best_format

    except Exception as exc:
        print(f"[exp2] Error reading exp1 results: {exc}, falling back to 'refs_coaching'")
        return "refs_coaching"


def get_format_instruction(format_id: str) -> str:
    """Return the format instruction string for the winning format from exp1."""
    FORMAT_INSTRUCTIONS = {
        "refs_coaching": (
            "Response format (REQUIRED):\n"
            "REFS: <list each piece and square you mention, e.g. \"bishop e5, knight c3\". "
            "Write \"none\" if you don't reference specific pieces>\n"
            "COACHING: <your coaching text>"
        ),
        "json": (
            'Response format (REQUIRED):\n'
            'Respond with ONLY valid JSON, no markdown:\n'
            '{"refs": [{"piece": "bishop", "square": "e5"}], "coaching": "<your text>"}'
        ),
        "xml": (
            "Response format (REQUIRED):\n"
            "<refs><ref piece=\"bishop\" square=\"e5\"/></refs>\n"
            "<coaching>Your coaching text here</coaching>"
        ),
        "markdown": (
            "Response format (REQUIRED):\n"
            "**Refs:** bishop e5, knight c3 (or \"none\")\n"
            "**Coaching:** Your coaching text here"
        ),
        "yaml": (
            "Response format (REQUIRED):\n"
            "refs:\n"
            "  - piece: bishop\n"
            "    square: e5\n"
            "coaching: Your coaching text here"
        ),
        "pipe_delimited": (
            "Response format (REQUIRED):\n"
            "REFS|bishop e5, knight c3\n"
            "COACHING|Your coaching text here"
        ),
        "freeform": (
            "Respond with a short coaching message (1-2 sentences). "
            "Mention specific pieces and squares when relevant."
        ),
        "tagged": (
            "Response format (REQUIRED):\n"
            "[REFS] bishop e5, knight c3 [/REFS]\n"
            "[COACHING] Your coaching text here [/COACHING]"
        ),
    }
    return FORMAT_INSTRUCTIONS.get(format_id, FORMAT_INSTRUCTIONS["refs_coaching"])


# ===========================================================================
# Prompt variant builders
# ===========================================================================
# Each returns (system_message, user_message).
# The `position` dict mirrors test_positions.json fields.
# `move_category` is "good", "okay", or "mistake".
# ===========================================================================

def _get_played_move(position: dict, move_category: str) -> tuple[str, str]:
    """Return (san, uci) for the move the student 'played' in this trial."""
    if move_category == "good":
        return position["book_move_san"], position["book_move_uci"]
    elif move_category == "mistake":
        return position["wrong_move_san"], position["wrong_move_uci"]
    else:  # okay
        # Pick a semi-reasonable alternative via python-chess:
        # first legal move that is not the book move but is a capture or develops a piece
        board = chess.Board(position["fen_before"])
        book = chess.Move.from_uci(position["book_move_uci"])
        wrong = (
            chess.Move.from_uci(position["wrong_move_uci"])
            if position.get("wrong_move_uci")
            else None
        )
        for move in board.legal_moves:
            if move == book:
                continue
            if wrong and move == wrong:
                continue
            # Prefer captures or non-pawn piece moves
            if board.is_capture(move) or board.piece_type_at(move.from_square) != chess.PAWN:
                return board.san(move), move.uci()
        # Fallback: any legal move that isn't book
        for move in board.legal_moves:
            if move != book:
                return board.san(move), move.uci()
        # Absolute fallback
        return position["book_move_san"], position["book_move_uci"]


def _feedback_text(position: dict, move_category: str, move_san: str) -> str:
    """Generate feedback text similar to the Swift PromptCatalog logic."""
    opening = position["opening_name"]
    book = position["book_move_san"]
    explanation = position.get("move_explanation", "")

    if move_category == "good":
        return (
            f"The student played the correct {opening} move ({move_san}). "
            f"Tell them why this move is good in the {opening} -- what plan or idea does it serve?"
        )
    elif move_category == "okay":
        return (
            f"The student played {move_san}, which is playable but not the {opening} main line. "
            f"The book move was {book}. Briefly explain why {book} is preferred in this system."
        )
    else:  # mistake
        return (
            f"The student played {move_san}, deviating from the {opening}. "
            f"The book move was {book}. {explanation} "
            f"Gently explain what they should have played and why."
        )


def _color_str(position: dict) -> str:
    return "White" if position.get("is_white_move") else "Black"


def _move_number(position: dict) -> int:
    return position.get("ply", 0) // 2 + 1


# ---- Variant 1: current (reconstructed from Swift PromptCatalog) ----------

def build_current(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    color = _color_str(position)
    opening = position["opening_name"]
    feedback = _feedback_text(position, move_category, move_san)
    board = position.get("board_summary", "")
    move_num = _move_number(position)

    prompt = (
        f"You are a chess coach. Your student (ELO ~1000, beginner) is learning the {opening} as {color}.\n"
        f"System: {opening}\n"
        f"\n"
        f"The student just played: {move_san} (move {move_num})\n"
        f"\n"
        f"Current board position:\n"
        f"{board}\n"
        f"\n"
        f"{feedback}\n"
        f"\n"
        f"Response format (REQUIRED):\n"
        f"REFS: <list each piece and square you mention, e.g. \"bishop e5, knight c3\". "
        f"Write \"none\" if you don't reference specific pieces>\n"
        f"COACHING: <your coaching text>\n"
        f"\n"
        f"Rules:\n"
        f"- ONLY reference pieces that exist on the squares listed above.\n"
        f"- REFS must exactly match pieces you mention in COACHING.\n"
        f"- Address the student as \"you\". You are talking TO the student about THEIR move.\n"
        f"- ONE or TWO short sentences (max 25 words total).\n"
        f"- Relate advice to the {opening} system.\n"
        f"- Use simple language. Spell out piece names, no algebraic notation."
    )
    return ("", prompt)


# ---- Variant 2: minimal --------------------------------------------------

def build_minimal(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    return (
        "",
        f"You are a chess coach. Student played {move_san} in the {opening}. One sentence.",
    )


# ---- Variant 3: system_user_split ----------------------------------------

def build_system_user_split(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    color = _color_str(position)
    opening = position["opening_name"]

    system = (
        "You are an expert chess coach for beginners. "
        "You give concise, encouraging feedback in 1-2 sentences. "
        "Spell out piece names, no algebraic notation. "
        "Address the student as 'you'."
    )
    user = (
        f"Opening: {opening}\n"
        f"Student plays as: {color}\n"
        f"Position (FEN): {position['fen_before']}\n"
        f"Board: {position.get('board_summary', '')}\n"
        f"Student's move: {move_san}\n"
        f"Move category: {move_category}\n"
        f"Book move: {position['book_move_san']}"
    )
    return (system, user)


# ---- Variant 4: few_shot_2 -----------------------------------------------

def build_few_shot_2(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")
    feedback = _feedback_text(position, move_category, move_san)

    examples = (
        "Example 1:\n"
        "Student played Nf3 in the Italian Game (good move).\n"
        "REFS: knight f3\n"
        "COACHING: Great move! Your knight on f3 controls the center and prepares to castle.\n"
        "\n"
        "Example 2:\n"
        "Student played h3 in the London System (okay move).\n"
        "REFS: pawn h3\n"
        "COACHING: That's playable, but developing your dark-squared bishop to f4 first "
        "would follow the London plan more closely.\n"
    )

    user = (
        f"{examples}\n"
        f"Now coach this position:\n"
        f"Opening: {opening}\n"
        f"Board: {board}\n"
        f"Student's move: {move_san}\n"
        f"{feedback}\n"
        f"\n"
        f"REFS: \n"
        f"COACHING: "
    )
    return ("You are a chess coach. Respond in the same format as the examples.", user)


# ---- Variant 5: few_shot_4 -----------------------------------------------

def build_few_shot_4(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")
    feedback = _feedback_text(position, move_category, move_san)

    examples = (
        "Example 1 (good move):\n"
        "Student played Nf3 in the Italian Game.\n"
        "REFS: knight f3\n"
        "COACHING: Great move! Your knight on f3 controls the center and prepares to castle.\n"
        "\n"
        "Example 2 (okay move):\n"
        "Student played h3 in the London System.\n"
        "REFS: pawn h3\n"
        "COACHING: That's playable, but developing your dark-squared bishop to f4 first "
        "would follow the London plan more closely.\n"
        "\n"
        "Example 3 (mistake):\n"
        "Student played a4 in the Italian Game.\n"
        "REFS: pawn a4\n"
        "COACHING: That pawn move doesn't help your development. "
        "Try bringing your bishop to c4 to target the center.\n"
        "\n"
        "Example 4 (good move):\n"
        "Student played Bf4 in the London System.\n"
        "REFS: bishop f4\n"
        "COACHING: Perfect! Your bishop on f4 is the key piece in the London -- "
        "it controls the dark squares and supports your center.\n"
    )

    user = (
        f"{examples}\n"
        f"Now coach this position:\n"
        f"Opening: {opening}\n"
        f"Board: {board}\n"
        f"Student's move: {move_san}\n"
        f"{feedback}\n"
        f"\n"
        f"REFS: \n"
        f"COACHING: "
    )
    return ("You are a chess coach. Respond in the same format as the examples.", user)


# ---- Variant 6: chain_of_thought -----------------------------------------

def build_chain_of_thought(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")
    color = _color_str(position)

    user = (
        f"You are a chess coach for a beginner learning the {opening} as {color}.\n"
        f"\n"
        f"Board: {board}\n"
        f"Student's move: {move_san}\n"
        f"Book move: {position['book_move_san']}\n"
        f"\n"
        f"First, analyze the position step by step:\n"
        f"1. What does the student's move do?\n"
        f"2. How does it compare to the book move?\n"
        f"3. Does it fit the {opening} plan?\n"
        f"\n"
        f"Then give your coaching response in 1-2 sentences.\n"
        f"\n"
        f"REFS: <pieces and squares you mention>\n"
        f"COACHING: <your coaching>"
    )
    return ("", user)


# ---- Variant 7: role_play ------------------------------------------------

def build_role_play(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")

    system = (
        "Pretend you are Magnus Carlsen coaching a child who is just learning chess openings. "
        "Be warm, encouraging, and use very simple language. "
        "Keep it to 1-2 short sentences."
    )
    user = (
        f"The child is learning the {opening}.\n"
        f"Board: {board}\n"
        f"They just played: {move_san}\n"
        f"The book move was: {position['book_move_san']}\n"
        f"\n"
        f"REFS: <pieces you mention>\n"
        f"COACHING: <your response as Magnus>"
    )
    return (system, user)


# ---- Variant 8: structured_input -----------------------------------------

def build_structured_input(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    color = _color_str(position)
    feedback = _feedback_text(position, move_category, move_san)

    # Parse the board summary into structured fields
    board_text = position.get("board_summary", "")
    # Board summary format: "White: King g1, ... | Black: King e8, ..."

    user = (
        f"POSITION DATA:\n"
        f"  Opening: {opening}\n"
        f"  Student color: {color}\n"
        f"  Move number: {_move_number(position)}\n"
        f"  Student's move: {move_san}\n"
        f"  Book move: {position['book_move_san']}\n"
        f"  Move category: {move_category}\n"
        f"\n"
        f"PIECES ON BOARD:\n"
        f"  {board_text}\n"
        f"\n"
        f"TASK: {feedback}\n"
        f"\n"
        f"OUTPUT FORMAT:\n"
        f"REFS: <piece square pairs>\n"
        f"COACHING: <1-2 sentences>"
    )
    return ("You are a chess coach for beginners.", user)


# ---- Variant 9: fen_only -------------------------------------------------

def build_fen_only(position: dict, move_category: str) -> tuple[str, str]:
    move_san, move_uci = _get_played_move(position, move_category)

    user = (
        f"FEN: {position['fen_before']}\n"
        f"Move: {move_san} ({move_uci})\n"
        f"Book move: {position['book_move_san']}\n"
        f"Coach this."
    )
    return ("", user)


# ---- Variant 10: plan_injected -------------------------------------------

def build_plan_injected(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    color = _color_str(position)
    opening = position["opening_name"]
    feedback = _feedback_text(position, move_category, move_san)
    board = position.get("board_summary", "")
    move_num = _move_number(position)

    # Plan data
    plan_summary = position.get("plan_summary", "")
    strategic_goals = position.get("strategic_goals", [])
    goals_str = "\n".join(f"  - {g}" for g in strategic_goals) if strategic_goals else "  (none)"
    piece_targets = position.get("piece_targets", [])
    targets_str = "\n".join(
        f"  - {pt['piece']} -> {', '.join(pt['ideal_squares'])} ({pt['reasoning']})"
        for pt in piece_targets
    ) if piece_targets else "  (none)"

    # Start with the current prompt, then inject plan data
    prompt = (
        f"You are a chess coach. Your student (ELO ~1000, beginner) is learning the {opening} as {color}.\n"
        f"System: {opening}\n"
        f"\n"
        f"OPENING PLAN:\n"
        f"  Summary: {plan_summary}\n"
        f"  Strategic goals:\n"
        f"{goals_str}\n"
        f"  Piece development targets:\n"
        f"{targets_str}\n"
        f"\n"
        f"The student just played: {move_san} (move {move_num})\n"
        f"\n"
        f"Current board position:\n"
        f"{board}\n"
        f"\n"
        f"{feedback}\n"
        f"\n"
        f"Response format (REQUIRED):\n"
        f"REFS: <piece square pairs>\n"
        f"COACHING: <your coaching text>\n"
        f"\n"
        f"Rules:\n"
        f"- ONLY reference pieces that exist on the squares listed above.\n"
        f"- REFS must exactly match pieces you mention in COACHING.\n"
        f"- Address the student as \"you\".\n"
        f"- ONE or TWO short sentences (max 25 words total).\n"
        f"- Relate advice to the {opening} plan and goals above.\n"
        f"- Use simple language. Spell out piece names, no algebraic notation."
    )
    return ("", prompt)


# ---- Variant 11: negative_examples ---------------------------------------

def build_negative_examples(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")
    feedback = _feedback_text(position, move_category, move_san)

    user = (
        f"You are a chess coach for a beginner learning the {opening}.\n"
        f"\n"
        f"Board: {board}\n"
        f"Student's move: {move_san}\n"
        f"Book move: {position['book_move_san']}\n"
        f"\n"
        f"{feedback}\n"
        f"\n"
        f"STRICT RULES - DO NOT VIOLATE:\n"
        f"- DO NOT mention pieces that are NOT on the squares listed in the board above.\n"
        f"- DO NOT use algebraic notation (like Nf3, Bc4, e4). Spell out piece names.\n"
        f"- DO NOT write more than 25 words in your coaching.\n"
        f"- DO NOT start with \"Great\" or \"Good\" if the move is a mistake.\n"
        f"- DO NOT be vague. Reference specific pieces and squares.\n"
        f"\n"
        f"REFS: <pieces you mention>\n"
        f"COACHING: <your coaching>"
    )
    return ("", user)


# ---- Variant 12: template_fill -------------------------------------------

def build_template_fill(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")

    quality = {"good": "good", "okay": "okay", "mistake": "bad"}[move_category]

    user = (
        f"You are a chess coach. Complete the template below.\n"
        f"\n"
        f"Opening: {opening}\n"
        f"Board: {board}\n"
        f"Book move: {position['book_move_san']}\n"
        f"\n"
        f"Complete this:\n"
        f"REFS: ___\n"
        f"COACHING: \"{move_san} is a {quality} move because ___\""
    )
    return ("", user)


# ---- Variant 13: q_and_a -------------------------------------------------

def build_q_and_a(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")

    user = (
        f"Opening: {opening}\n"
        f"Board: {board}\n"
        f"Book move: {position['book_move_san']}\n"
        f"\n"
        f"Q: Why did the student play {move_san}? Is it the right choice in the {opening}?\n"
        f"A:"
    )
    return ("You are a chess coach. Answer in 1-2 sentences.", user)


# ---- Variant 14: bullet_rules --------------------------------------------

def build_bullet_rules(position: dict, move_category: str) -> tuple[str, str]:
    move_san, _ = _get_played_move(position, move_category)
    opening = position["opening_name"]
    board = position.get("board_summary", "")
    color = _color_str(position)
    feedback = _feedback_text(position, move_category, move_san)

    user = (
        f"RULES (follow ALL of these):\n"
        f"1. You are a chess coach for a beginner.\n"
        f"2. The student is learning the {opening} as {color}.\n"
        f"3. The student played {move_san} (move {_move_number(position)}).\n"
        f"4. The book move is {position['book_move_san']}.\n"
        f"5. Current board: {board}\n"
        f"6. {feedback}\n"
        f"7. Address the student as 'you'.\n"
        f"8. Use 1-2 sentences, max 25 words.\n"
        f"9. Spell out piece names, no algebraic notation.\n"
        f"10. Only reference pieces that are actually on the board.\n"
        f"11. Relate your advice to the {opening} plan.\n"
        f"\n"
        f"REFS: <pieces and squares you mention>\n"
        f"COACHING: <your coaching>"
    )
    return ("", user)


# ---- Variant 15: json_prompt ---------------------------------------------

def build_json_prompt(position: dict, move_category: str) -> tuple[str, str]:
    move_san, move_uci = _get_played_move(position, move_category)
    opening = position["opening_name"]

    input_json = json.dumps(
        {
            "task": "chess_coaching",
            "opening": opening,
            "student": {"elo": 1000, "level": "beginner", "color": _color_str(position)},
            "position": {
                "fen": position["fen_before"],
                "board_summary": position.get("board_summary", ""),
                "move_number": _move_number(position),
            },
            "move": {
                "played": move_san,
                "played_uci": move_uci,
                "book_move": position["book_move_san"],
                "category": move_category,
            },
            "rules": {
                "max_words": 25,
                "sentences": "1-2",
                "no_notation": True,
                "reference_real_pieces_only": True,
                "address_as_you": True,
            },
            "output_format": {
                "refs": "<piece square pairs or none>",
                "coaching": "<your coaching text>",
            },
        },
        indent=2,
    )

    user = (
        f"Process this coaching request and respond with REFS and COACHING lines:\n\n"
        f"{input_json}"
    )
    return ("You are a chess coaching AI. Read the JSON input and produce coaching output.", user)


# ===========================================================================
# Variant registry
# ===========================================================================

PROMPT_VARIANTS: dict[str, callable] = {
    "current": build_current,
    "minimal": build_minimal,
    "system_user_split": build_system_user_split,
    "few_shot_2": build_few_shot_2,
    "few_shot_4": build_few_shot_4,
    "chain_of_thought": build_chain_of_thought,
    "role_play": build_role_play,
    "structured_input": build_structured_input,
    "fen_only": build_fen_only,
    "plan_injected": build_plan_injected,
    "negative_examples": build_negative_examples,
    "template_fill": build_template_fill,
    "q_and_a": build_q_and_a,
    "bullet_rules": build_bullet_rules,
    "json_prompt": build_json_prompt,
}


# ===========================================================================
# Model loading
# ===========================================================================

def load_model(model_path: str | None = None) -> Llama:
    """Load the Qwen3-4B GGUF model via llama-cpp-python."""
    path = model_path or DEFAULT_MODEL_PATH
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"Model not found at {path}. Download the GGUF or set model_path."
        )
    print(f"[exp2] Loading model from {path} ...")
    model = Llama(
        model_path=path,
        n_ctx=2048,
        n_gpu_layers=-1,  # offload all layers to GPU if available
        verbose=False,
    )
    print("[exp2] Model loaded.")
    return model


# ===========================================================================
# Evaluation helpers
# ===========================================================================

def _check_format_compliance(response: str) -> float:
    """
    Score 0.0-1.0 for how well the response follows the REFS/COACHING format.
    """
    text = response.strip()
    has_refs = bool(re.search(r"(?i)^REFS\s*:", text, re.MULTILINE))
    has_coaching = bool(re.search(r"(?i)^COACHING\s*:", text, re.MULTILINE))

    if has_refs and has_coaching:
        return 1.0
    elif has_refs or has_coaching:
        return 0.5
    # Check for other structured formats
    if re.search(r'"refs"', text, re.IGNORECASE) and re.search(r'"coaching"', text, re.IGNORECASE):
        return 0.8
    return 0.0


def _check_hallucination(response: str, board_summary: str) -> bool:
    """
    Basic hallucination check: does the response mention piece-square combos
    that don't appear in the board summary?
    """
    # Extract piece-square references from response
    piece_names = ["king", "queen", "rook", "bishop", "knight", "pawn"]
    squares = [f"{f}{r}" for f in "abcdefgh" for r in "12345678"]

    board_lower = board_summary.lower()
    response_lower = response.lower()

    for piece in piece_names:
        for square in squares:
            # If response mentions "piece square" but board doesn't have it
            pattern = f"{piece}\\s+{square}"
            if re.search(pattern, response_lower) and not re.search(pattern, board_lower):
                # Also check without space (e.g., "bishop on e5")
                on_pattern = f"{piece}\\s+on\\s+{square}"
                if re.search(on_pattern, response_lower) or re.search(pattern, response_lower):
                    if f"{piece} {square}" not in board_lower:
                        return True
    return False


def _check_mentions_opening(response: str, opening_name: str) -> bool:
    """Does the response mention the opening name or key words from it?"""
    response_lower = response.lower()
    opening_lower = opening_name.lower()
    # Check full name or major keywords
    if opening_lower in response_lower:
        return True
    for word in opening_lower.split():
        if len(word) > 3 and word in response_lower:
            return True
    return False


def _check_mentions_move(response: str, move_san: str) -> bool:
    """Does the response reference the played move (by name or description)?"""
    return move_san.lower() in response.lower()


def _check_coaching_correctness(
    response: str, move_category: str
) -> float:
    """
    Score 0.0-1.0: does the coaching correctly identify the quality of the move?
    - good: should praise or affirm
    - okay: should acknowledge but suggest improvement
    - mistake: should identify the error and suggest better
    """
    resp = response.lower()

    positive_words = {"great", "good", "nice", "well done", "correct", "perfect", "excellent", "right"}
    negative_words = {"mistake", "error", "wrong", "better", "instead", "should have", "try", "consider", "preferred"}
    mixed_words = {"playable", "okay", "not the best", "but", "however", "although", "instead"}

    pos_count = sum(1 for w in positive_words if w in resp)
    neg_count = sum(1 for w in negative_words if w in resp)
    mix_count = sum(1 for w in mixed_words if w in resp)

    if move_category == "good":
        if pos_count > 0 and neg_count == 0:
            return 1.0
        elif pos_count > neg_count:
            return 0.7
        elif pos_count > 0:
            return 0.5
        return 0.2

    elif move_category == "mistake":
        if neg_count > 0 and pos_count == 0:
            return 1.0
        elif neg_count > pos_count:
            return 0.7
        elif neg_count > 0:
            return 0.5
        return 0.2

    else:  # okay
        if mix_count > 0 or (pos_count > 0 and neg_count > 0):
            return 1.0
        elif neg_count > 0 or pos_count > 0:
            return 0.5
        return 0.3


# ===========================================================================
# Trial runner
# ===========================================================================

def run_trial(
    model: Llama,
    position: dict,
    variant_id: str,
    move_category: str,
    thinking: bool,
    format_instruction: str,
) -> dict:
    """
    Run a single trial: build prompt, call model, evaluate response.
    Returns a dict matching CSV_COLUMNS.
    """
    build_fn = PROMPT_VARIANTS[variant_id]
    system_msg, user_msg = build_fn(position, move_category)

    # Append format instruction if the variant doesn't already include format guidance
    # (skip for variants that have their own format embedded)
    format_embedded_variants = {
        "current", "few_shot_2", "few_shot_4", "chain_of_thought",
        "role_play", "structured_input", "negative_examples",
        "template_fill", "bullet_rules", "json_prompt", "plan_injected",
    }
    if variant_id not in format_embedded_variants:
        user_msg = f"{user_msg}\n\n{format_instruction}"

    # Build messages list
    messages = []
    if system_msg:
        messages.append({"role": "system", "content": system_msg})
    messages.append({"role": "user", "content": user_msg})

    # Select sampling params
    params = THINKING_PARAMS if thinking else NON_THINKING_PARAMS

    # Add /think or /no_think tag for Qwen3 thinking mode control
    if thinking:
        # Prepend thinking enabler
        if messages[-1]["role"] == "user":
            messages[-1]["content"] = messages[-1]["content"] + "\n/think"
    else:
        if messages[-1]["role"] == "user":
            messages[-1]["content"] = messages[-1]["content"] + "\n/no_think"

    raw_prompt = json.dumps(messages, ensure_ascii=False)

    # Call model
    t0 = time.perf_counter()
    try:
        output = model.create_chat_completion(
            messages=messages,
            max_tokens=MAX_TOKENS,
            temperature=params["temperature"],
            top_p=params["top_p"],
            top_k=params["top_k"],
            min_p=params["min_p"],
        )
        t1 = time.perf_counter()
        latency_ms = round((t1 - t0) * 1000, 1)

        raw_response = output["choices"][0]["message"]["content"] or ""
        tokens_in = output.get("usage", {}).get("prompt_tokens", 0)
        tokens_out = output.get("usage", {}).get("completion_tokens", 0)
    except Exception as exc:
        t1 = time.perf_counter()
        latency_ms = round((t1 - t0) * 1000, 1)
        raw_response = f"[ERROR] {exc}"
        tokens_in = 0
        tokens_out = 0

    # Strip thinking tags from response for evaluation
    eval_response = re.sub(
        r"<think>.*?</think>", "", raw_response, flags=re.DOTALL
    ).strip()

    # Evaluate
    move_san, _ = _get_played_move(position, move_category)
    board_summary = position.get("board_summary", "")

    format_compliance = _check_format_compliance(eval_response)
    hallucination_detected = _check_hallucination(eval_response, board_summary)
    mentions_opening = _check_mentions_opening(eval_response, position["opening_name"])
    mentions_move = _check_mentions_move(eval_response, move_san)
    word_count = len(eval_response.split())
    coaching_correctness = _check_coaching_correctness(eval_response, move_category)

    return {
        "experiment_id": EXPERIMENT_ID,
        "trial_id": str(uuid.uuid4())[:8],
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "model": MODEL_NAME,
        "position_id": position.get("position_id", "unknown"),
        "variant_id": variant_id,
        "move_category": move_category,
        "thinking_mode": "on" if thinking else "off",
        "max_tokens": MAX_TOKENS,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "format_compliance": format_compliance,
        "hallucination_detected": hallucination_detected,
        "mentions_opening": mentions_opening,
        "mentions_move": mentions_move,
        "word_count": word_count,
        "latency_ms": latency_ms,
        "coaching_correctness": coaching_correctness,
        "raw_prompt": raw_prompt,
        "raw_response": raw_response,
        "params_json": json.dumps(params),
    }


# ===========================================================================
# Main experiment runner
# ===========================================================================

def run_experiment(model_path: str | None = None) -> str:
    """
    Run the full Experiment 2 sweep and write results to CSV.
    Returns the output CSV path.
    """
    # Load positions
    if not POSITIONS_PATH.exists():
        raise FileNotFoundError(
            f"Test positions not found at {POSITIONS_PATH}. "
            f"Run generate_test_positions.py first."
        )

    with open(POSITIONS_PATH, "r", encoding="utf-8") as f:
        all_positions = json.load(f)

    # Select subset of positions
    positions = all_positions[:NUM_POSITIONS]
    if len(positions) < NUM_POSITIONS:
        print(
            f"[exp2] WARNING: Only {len(positions)} positions available "
            f"(wanted {NUM_POSITIONS})"
        )

    # Determine best format from exp1
    best_format = determine_best_format()
    format_instruction = get_format_instruction(best_format)
    print(f"[exp2] Using format: {best_format}")

    # Load model
    model = load_model(model_path)

    # Prepare output
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    output_path = str(OUTPUT_PATH)

    variant_ids = list(PROMPT_VARIANTS.keys())
    thinking_modes = [True, False]

    total_trials = len(variant_ids) * len(positions) * len(MOVE_CATEGORIES) * len(thinking_modes)
    print(
        f"[exp2] Starting experiment: "
        f"{len(variant_ids)} variants x {len(positions)} positions x "
        f"{len(MOVE_CATEGORIES)} categories x {len(thinking_modes)} thinking modes "
        f"= {total_trials} trials"
    )

    trial_count = 0
    with open(output_path, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=CSV_COLUMNS)
        writer.writeheader()

        for variant_id in variant_ids:
            for position in positions:
                for move_category in MOVE_CATEGORIES:
                    for thinking in thinking_modes:
                        trial_count += 1
                        pos_id = position.get("position_id", "?")
                        think_str = "think" if thinking else "no_think"
                        print(
                            f"  [{trial_count}/{total_trials}] "
                            f"{variant_id} | {pos_id} | {move_category} | {think_str}",
                            end=" ... ",
                            flush=True,
                        )

                        result = run_trial(
                            model=model,
                            position=position,
                            variant_id=variant_id,
                            move_category=move_category,
                            thinking=thinking,
                            format_instruction=format_instruction,
                        )
                        writer.writerow(result)
                        csvfile.flush()

                        print(
                            f"compliance={result['format_compliance']:.1f} "
                            f"correct={result['coaching_correctness']:.1f} "
                            f"words={result['word_count']} "
                            f"{result['latency_ms']}ms"
                        )

    print(f"\n[exp2] Done. {trial_count} trials written to {output_path}")
    return output_path


# ===========================================================================
# CLI entry point
# ===========================================================================

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Experiment 2: Prompt Architecture Sweep")
    parser.add_argument(
        "--model-path",
        type=str,
        default=None,
        help=f"Path to GGUF model file (default: {DEFAULT_MODEL_PATH})",
    )
    args = parser.parse_args()

    run_experiment(model_path=args.model_path)
