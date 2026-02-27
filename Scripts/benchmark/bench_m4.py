#!/usr/bin/env python3
"""
M4 benchmark: thinking vs non-thinking, varying token budgets and prompt types.
Uses llama-cpp-python to load the same GGUF the app uses.

Measures wall-clock latency, tokens generated, tokens/sec for each scenario.
"""

import json
import time
import re
import sys
import os
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import Optional

from llama_cpp import Llama

# ── Paths ────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent.parent
MODEL_PATH = ROOT / "ChessCoach" / "Resources" / "Qwen3-4B-Q4_K_M.gguf"
ITALIAN_PATH = ROOT / "ChessCoach" / "Resources" / "Openings" / "italian.json"
LONDON_PATH = ROOT / "ChessCoach" / "Resources" / "Openings" / "london.json"
RESULTS_DIR = Path(__file__).resolve().parent / "results"
RESULTS_DIR.mkdir(exist_ok=True)

# ── Sampling params (Qwen3 docs) ────────────────────────────────────────────
THINKING_PARAMS = dict(temperature=0.6, top_p=0.95, top_k=20, min_p=0.0)
NON_THINKING_PARAMS = dict(temperature=0.7, top_p=0.8, top_k=20, min_p=0.0)

SYSTEM_MSG = "You are a chess coach."


# ── Test positions ───────────────────────────────────────────────────────────
@dataclass
class TestPosition:
    name: str
    fen: str
    board_summary: str
    last_move_san: str
    opening_name: str
    move_category: str  # "good", "opponent", "deviation"
    expected_san: Optional[str] = None
    coaching_text: str = ""  # pre-filled for explanation prompts
    move_history: str = ""


def build_board_summary(fen: str) -> str:
    """Minimal board summary from FEN — piece placement only."""
    import chess
    board = chess.Board(fen)
    white_pieces = []
    black_pieces = []
    piece_names = {
        chess.PAWN: "pawn", chess.KNIGHT: "knight", chess.BISHOP: "bishop",
        chess.ROOK: "rook", chess.QUEEN: "queen", chess.KING: "king"
    }
    for sq in chess.SQUARES:
        piece = board.piece_at(sq)
        if piece:
            name = piece_names[piece.piece_type]
            coord = chess.square_name(sq)
            if piece.color == chess.WHITE:
                white_pieces.append(f"{name} on {coord}")
            else:
                black_pieces.append(f"{name} on {coord}")
    lines = [f"White: {', '.join(white_pieces)}", f"Black: {', '.join(black_pieces)}"]

    # Castling
    wk = "O-O" if board.has_kingside_castling_rights(chess.WHITE) else None
    wq = "O-O-O" if board.has_queenside_castling_rights(chess.WHITE) else None
    bk = "O-O" if board.has_kingside_castling_rights(chess.BLACK) else None
    bq = "O-O-O" if board.has_queenside_castling_rights(chess.BLACK) else None
    wc = [x for x in [wk, wq] if x]
    bc = [x for x in [bk, bq] if x]
    if wc:
        lines.append(f"White king can castle {' '.join(wc)}")
    if bc:
        lines.append(f"Black king can castle {' '.join(bc)}")
    return "\n".join(lines)


def walk_tree(node, moves_so_far=None, fen_so_far=None, opening_name=""):
    """Walk opening tree and collect test positions."""
    import chess
    if moves_so_far is None:
        moves_so_far = []
    if fen_so_far is None:
        fen_so_far = chess.STARTING_FEN

    positions = []
    for child in node.get("children", []):
        move_data = child.get("move", {})
        uci = move_data.get("uci", "")
        san = move_data.get("san", "")
        if not uci:
            continue

        board = chess.Board(fen_so_far)
        try:
            m = chess.Move.from_uci(uci)
            board.push(m)
        except Exception:
            continue

        new_fen = board.fen()
        new_moves = moves_so_far + [san]
        history_str = " ".join(
            f"{i // 2 + 1}. {m}" if i % 2 == 0 else m
            for i, m in enumerate(new_moves)
        )

        # Determine if this is a user or opponent move (for Italian = white)
        is_user_move = len(new_moves) % 2 == 1  # odd plies = white just moved

        if child.get("isMainLine", False) and len(new_moves) >= 2:
            cat = "good" if is_user_move else "opponent"
            positions.append(TestPosition(
                name=f"{opening_name} ply {len(new_moves)}: {san}",
                fen=new_fen,
                board_summary=build_board_summary(new_fen),
                last_move_san=san,
                opening_name=opening_name,
                move_category=cat,
                expected_san=san,
                coaching_text=move_data.get("explanation", ""),
                move_history=history_str,
            ))

        positions.extend(walk_tree(child, new_moves, new_fen, opening_name))

    return positions


def load_test_positions(max_per_opening=8):
    positions = []
    for path, name in [(ITALIAN_PATH, "Italian Game"), (LONDON_PATH, "London System")]:
        with open(path) as f:
            data = json.load(f)
        all_pos = walk_tree(data.get("tree", {}), opening_name=name)
        # Pick evenly spaced positions
        step = max(1, len(all_pos) // max_per_opening)
        positions.extend(all_pos[::step][:max_per_opening])
    return positions


# ── Prompt builders (mirror Swift PromptCatalog) ─────────────────────────────

def coaching_prompt(pos: TestPosition) -> str:
    if pos.move_category == "good":
        feedback = f"The student played the correct {pos.opening_name} move ({pos.last_move_san}). Tell them why this move is good."
    elif pos.move_category == "opponent":
        feedback = f"The opponent played {pos.last_move_san}. Explain what this move means for the student's position."
    else:
        feedback = f"The student played {pos.last_move_san}. Explain what happened."

    return f"""Side to move: White

Board:
{pos.board_summary}

Opening: {pos.opening_name}
Last move: {pos.last_move_san}

{feedback}

IMPORTANT: REFS must ONLY list squares where pieces currently sit on the board.

Respond with ONLY:
REFS: <up to 3 key squares with pieces on them>
COACHING: <one sentence>"""


def get_occupied_squares(fen: str) -> str:
    """Return comma-separated list of occupied square names from FEN."""
    import chess
    board = chess.Board(fen)
    squares = []
    for sq in chess.SQUARES:
        if board.piece_at(sq):
            squares.append(chess.square_name(sq))
    return ", ".join(sorted(squares))


def explanation_prompt(pos: TestPosition) -> str:
    occupied = get_occupied_squares(pos.fen)
    return f"""You are a friendly chess coach inside an opening trainer app. A student is learning the {pos.opening_name} as White (ELO ~800).
The app plays the Black side automatically. Your job is to help the student understand EVERY move.

CRITICAL: Always use colors (White/Black) or "the opponent" to identify whose piece you mean.

Moves so far: {pos.move_history}
Current board position:
{pos.board_summary}

The move {pos.last_move_san} was just played.
Quick summary already shown: "{pos.coaching_text}"

Give a deeper explanation (3-5 sentences) of WHY this move matters:
- What squares or pieces does it affect?
- What plan or idea does it support?
- How does it fit into the {pos.opening_name} strategy?

Squares that currently have pieces: {occupied}
REFS must ONLY use squares from the list above. Any square not listed is EMPTY.

Respond with ONLY:
REFS: <up to 3 squares from the occupied list, or "none">
COACHING: <your explanation>

Rules:
- Use simple language a beginner can understand.
- Do not use algebraic notation symbols — spell out piece names.
- Always speak TO the student."""


def alignment_prompt(pos: TestPosition) -> str:
    return f"""You are evaluating a chess move for plan alignment in an opening trainer.

OPENING: {pos.opening_name}
STUDENT: White, ELO ~800
MOVE PLAYED: {pos.last_move_san} at ply {len(pos.move_history.split())}
MOVE HISTORY: {pos.move_history}

BOARD AFTER MOVE:
{pos.board_summary}

THE OPENING PLAN:
Summary: Develop pieces toward the center and kingside, castle early, prepare d4.
Strategic Goals (in priority order):
1. Control the center with e4/d4
2. Develop knights and bishops toward active squares
3. Castle kingside for king safety
4. Connect rooks

EVALUATION RUBRIC — Score 0-100 on plan alignment:
1. Development progress: Does this move develop a piece or improve piece activity?
2. Pawn structure alignment: Does this maintain the opening's target pawn structure?
3. Strategic goal advancement: Does this move work toward the opening's objectives?
4. King safety: Does this move contribute to getting the king safe?

REASONING REQUIREMENTS:
- Lead with what this move accomplishes for the plan
- Keep reasoning to 2-3 sentences, suitable for a beginner

Respond in EXACTLY this JSON format (no markdown, no extra text):
{{"alignment": <0-100>, "reasoning": "<2-3 sentence explanation>", "development": <true/false>, "pawnStructure": <true/false>, "strategicGoal": <true/false>, "kingSafety": "<positive/negative/neutral>"}}"""


# ── Validation (mirrors CoachingValidator) ───────────────────────────────────

SQUARE_RE = re.compile(r'\b([a-h][1-8])\b')
PIECE_MAP = {
    "king": "k", "queen": "q", "rook": "r",
    "bishop": "b", "knight": "n", "pawn": "p"
}


def parse_refs_coaching(response: str):
    """Parse REFS/COACHING format. Returns (coaching_text, refs_list, raw_refs)."""
    lines = response.strip().split("\n")
    coaching = response
    refs = []
    raw_refs = ""
    for line in lines:
        t = line.strip()
        if t.upper().startswith("REFS:"):
            raw_refs = t[5:].strip()
            refs = parse_refs(raw_refs)
        elif t.upper().startswith("COACHING:"):
            coaching = t[9:].strip()
    if "COACHING:" not in response.upper():
        coaching = " ".join(
            l for l in lines if not l.strip().upper().startswith("REFS:")
        ).strip()
    return coaching, refs, raw_refs


def parse_refs(s: str):
    """Parse refs string into list of (square, piece_kind_or_None)."""
    if not s or s.strip().lower() == "none":
        return []
    results = []
    for part in s.split(","):
        trimmed = part.strip().lower()
        tokens = trimmed.split()
        kind = PIECE_MAP.get(tokens[0]) if tokens else None
        match = SQUARE_RE.search(trimmed)
        if match:
            results.append((match.group(1), kind))
    return results


def validate_refs(refs, fen: str) -> tuple[int, int]:
    """Validate refs against board. Returns (valid_count, invalid_count)."""
    import chess
    board = chess.Board(fen)
    valid = 0
    invalid = 0
    for sq_str, expected_kind in refs:
        sq = chess.parse_square(sq_str)
        piece = board.piece_at(sq)
        if piece is None:
            invalid += 1
        elif expected_kind:
            actual = {chess.PAWN: "p", chess.KNIGHT: "n", chess.BISHOP: "b",
                      chess.ROOK: "r", chess.QUEEN: "q", chess.KING: "k"}[piece.piece_type]
            if actual == expected_kind:
                valid += 1
            else:
                invalid += 1
        else:
            valid += 1
    return valid, invalid


def parse_alignment_json(response: str) -> Optional[dict]:
    """Try to parse alignment JSON from response."""
    text = response.strip()

    # Strip <think> tags if present
    text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL).strip()

    # Find JSON boundaries
    start = text.find('{')
    end = text.rfind('}')
    if start < 0 or end < 0:
        return None

    txt = text[start:end + 1]

    # Fix extra trailing braces (Qwen3 bug with nested objects)
    while txt.endswith('}}}'):
        txt = txt[:-1]

    # Fix common LLM issues
    txt = re.sub(r':\s*(True|False)\b', lambda m: f': {m.group(1).lower()}', txt)
    txt = re.sub(r':\s*(positive|negative|neutral)\b', r': "\1"', txt)

    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        pass

    # Last resort: try to find a simpler JSON match
    match = re.search(r'\{[^{}]*"alignment"\s*:\s*\d+[^{}]*\}', text)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass
    return None


# ── Benchmark runner ─────────────────────────────────────────────────────────

@dataclass
class Trial:
    scenario: str
    position: str
    thinking: bool
    max_tokens: int
    prompt_tokens: int
    completion_tokens: int
    wall_time_s: float
    tokens_per_sec: float
    format_ok: bool
    refs_valid: int
    refs_invalid: int
    coaching_text: str
    raw_response: str
    json_parse_ok: Optional[bool] = None
    alignment_score: Optional[int] = None


def run_trial(llm: Llama, prompt: str, max_tokens: int, use_thinking: bool,
              scenario: str, pos: TestPosition) -> Trial:
    """Run a single inference trial and measure everything."""
    think_tag = "/think" if use_thinking else "/no_think"
    messages = [
        {"role": "system", "content": f"{SYSTEM_MSG}\n{think_tag}"},
        {"role": "user", "content": prompt},
    ]
    params = THINKING_PARAMS if use_thinking else NON_THINKING_PARAMS

    t0 = time.perf_counter()
    result = llm.create_chat_completion(
        messages=messages,
        max_tokens=max_tokens,
        **params,
    )
    wall = time.perf_counter() - t0

    raw = result["choices"][0]["message"]["content"]
    usage = result.get("usage", {})
    prompt_tok = usage.get("prompt_tokens", 0)
    comp_tok = usage.get("completion_tokens", 0)
    tps = comp_tok / wall if wall > 0 else 0

    # Strip thinking tags if present
    clean = re.sub(r'<think>.*?</think>', '', raw, flags=re.DOTALL).strip()

    # Validate based on scenario
    format_ok = False
    refs_valid = 0
    refs_invalid = 0
    coaching = ""
    json_ok = None
    alignment = None

    if scenario.startswith("alignment"):
        parsed = parse_alignment_json(clean)
        json_ok = parsed is not None
        if parsed:
            alignment = parsed.get("alignment")
            coaching = parsed.get("reasoning", "")
            format_ok = True
        else:
            coaching = clean
    else:
        coaching, refs, raw_refs = parse_refs_coaching(clean)
        format_ok = "COACHING:" in raw.upper() or "REFS:" in raw.upper()
        if refs:
            v, iv = validate_refs(refs, pos.fen)
            refs_valid = v
            refs_invalid = iv
        else:
            # no refs claimed — that's ok for coaching-only
            pass

    return Trial(
        scenario=scenario,
        position=pos.name,
        thinking=use_thinking,
        max_tokens=max_tokens,
        prompt_tokens=prompt_tok,
        completion_tokens=comp_tok,
        wall_time_s=round(wall, 3),
        tokens_per_sec=round(tps, 1),
        format_ok=format_ok,
        refs_valid=refs_valid,
        refs_invalid=refs_invalid,
        coaching_text=coaching[:200],
        raw_response=raw[:500],
        json_parse_ok=json_ok,
        alignment_score=alignment,
    )


def main():
    print("=" * 70)
    print("Chess Coach M4 Benchmark")
    print("=" * 70)

    # Check deps
    try:
        import chess
    except ImportError:
        print("Installing python-chess...")
        os.system(f"{sys.executable} -m pip install chess")
        import chess

    if not MODEL_PATH.exists():
        print(f"ERROR: Model not found at {MODEL_PATH}")
        sys.exit(1)

    # Load positions
    print("\nLoading test positions...")
    positions = load_test_positions(max_per_opening=6)
    print(f"  {len(positions)} positions loaded")

    # Load model
    print(f"\nLoading model: {MODEL_PATH.name}")
    t0 = time.perf_counter()
    llm = Llama(
        model_path=str(MODEL_PATH),
        n_ctx=4096,
        n_threads=8,
        n_gpu_layers=0,  # CPU only to match simulator; set -1 for GPU
        verbose=False,
        chat_format="chatml",
    )
    load_time = time.perf_counter() - t0
    print(f"  Model loaded in {load_time:.1f}s")

    # ── Define scenarios ─────────────────────────────────────────────────
    scenarios = [
        # (name, prompt_fn, max_tokens, use_thinking)
        ("coaching_no_think_80", coaching_prompt, 80, False),
        ("explanation_no_think_200", explanation_prompt, 200, False),
        ("alignment_no_think_200", alignment_prompt, 200, False),
    ]

    trials: list[Trial] = []
    total = len(scenarios) * len(positions)
    done = 0

    for scenario_name, prompt_fn, max_tok, thinking in scenarios:
        print(f"\n{'─' * 60}")
        print(f"Scenario: {scenario_name}")
        print(f"  max_tokens={max_tok}, thinking={thinking}")
        print(f"{'─' * 60}")

        for pos in positions:
            done += 1
            prompt = prompt_fn(pos)
            print(f"  [{done}/{total}] {pos.name}...", end=" ", flush=True)

            trial = run_trial(llm, prompt, max_tok, thinking, scenario_name, pos)
            trials.append(trial)

            status = "OK" if trial.format_ok else "FORMAT?"
            ref_str = f"refs={trial.refs_valid}v/{trial.refs_invalid}iv" if "alignment" not in scenario_name else ""
            json_str = f"json={'OK' if trial.json_parse_ok else 'FAIL'}" if trial.json_parse_ok is not None else ""
            align_str = f"score={trial.alignment_score}" if trial.alignment_score is not None else ""

            print(f"{trial.wall_time_s:.2f}s  {trial.completion_tokens}tok  "
                  f"{trial.tokens_per_sec:.0f}t/s  {status}  {ref_str}{json_str}{align_str}")

    # ── Summary ──────────────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)

    scenario_names = sorted(set(t.scenario for t in trials))
    for sname in scenario_names:
        st = [t for t in trials if t.scenario == sname]
        avg_wall = sum(t.wall_time_s for t in st) / len(st)
        avg_tok = sum(t.completion_tokens for t in st) / len(st)
        avg_tps = sum(t.tokens_per_sec for t in st) / len(st)
        fmt_rate = sum(1 for t in st if t.format_ok) / len(st) * 100
        total_refs_v = sum(t.refs_valid for t in st)
        total_refs_iv = sum(t.refs_invalid for t in st)

        print(f"\n  {sname}:")
        print(f"    avg wall time:   {avg_wall:.2f}s")
        print(f"    avg tokens:      {avg_tok:.0f}")
        print(f"    avg tok/s:       {avg_tps:.0f}")
        print(f"    format ok:       {fmt_rate:.0f}%")

        if "alignment" in sname:
            json_ok_count = sum(1 for t in st if t.json_parse_ok)
            json_rate = json_ok_count / len(st) * 100
            scores = [t.alignment_score for t in st if t.alignment_score is not None]
            avg_score = sum(scores) / len(scores) if scores else 0
            print(f"    JSON parse:      {json_rate:.0f}%")
            print(f"    avg alignment:   {avg_score:.0f}")
        else:
            if total_refs_v + total_refs_iv > 0:
                acc = total_refs_v / (total_refs_v + total_refs_iv) * 100
                print(f"    refs accuracy:   {acc:.0f}% ({total_refs_v}v/{total_refs_iv}iv)")

    # ── Save results ─────────────────────────────────────────────────────
    import csv
    csv_path = RESULTS_DIR / "bench_m4_v3.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "scenario", "position", "thinking", "max_tokens",
            "prompt_tokens", "completion_tokens", "wall_time_s",
            "tokens_per_sec", "format_ok", "refs_valid", "refs_invalid",
            "json_parse_ok", "alignment_score", "coaching_text",
        ])
        writer.writeheader()
        for t in trials:
            d = asdict(t)
            del d["raw_response"]
            writer.writerow(d)

    print(f"\n  Results saved to {csv_path}")

    # Save raw responses for inspection
    raw_path = RESULTS_DIR / "bench_m4_v3_raw.json"
    with open(raw_path, "w") as f:
        json.dump([asdict(t) for t in trials], f, indent=2)
    print(f"  Raw responses saved to {raw_path}")


if __name__ == "__main__":
    main()
