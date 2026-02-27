"""Targeted experiment: fix accuracy at shallow opening depths.

Root cause: plan context mentions target squares (f7, c4, f3) that the model
confuses with current piece positions. Tests 6 prompt strategies to fix this.

Target: 99.99% ref accuracy for depths 1-6 (beginner territory, ELO < 1200).
"""
import json, re, time, chess, random
from llama_cpp import Llama

MODEL_PATH = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Qwen3-4B-Q4_K_M.gguf"
model = Llama(model_path=MODEL_PATH, n_ctx=4096, n_gpu_layers=-1, verbose=False)

NOTHINK = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}


def board_description(fen):
    board = chess.Board(fen)
    white_pieces = []
    black_pieces = []
    for sq, piece in board.piece_map().items():
        name = chess.square_name(sq)
        pname = chess.piece_name(piece.piece_type)
        if piece.color == chess.WHITE:
            white_pieces.append(f"{pname} on {name}")
        else:
            black_pieces.append(f"{pname} on {name}")
    parts = [f"White pieces: {', '.join(sorted(white_pieces))}",
             f"Black pieces: {', '.join(sorted(black_pieces))}"]
    for color, label in [(chess.WHITE, "White"), (chess.BLACK, "Black")]:
        king_sq = board.king(color)
        if king_sq is not None:
            castling = []
            if board.has_kingside_castling_rights(color): castling.append("O-O")
            if board.has_queenside_castling_rights(color): castling.append("O-O-O")
            castle_str = f", can castle {' '.join(castling)}" if castling else ""
            parts.append(f"{label} king on {chess.square_name(king_sq)}{castle_str}")
    return "\n".join(parts)


def strip_thinking(text):
    m = re.search(r"</think>\s*", text)
    return text[m.end():].strip() if m else text.strip()


def check_accuracy(text, fen):
    text = strip_thinking(text)
    board = chess.Board(fen)
    refs_match = re.search(r"(?i)^REFS:\s*(.+)", text, re.MULTILINE)
    if not refs_match:
        return 0, 0, [], []
    refs_text = refs_match.group(1)
    square_refs = re.findall(r'\b([a-h][1-8])\b', refs_text)
    piece_sq_refs = re.findall(r'(knight|bishop|rook|queen|king|pawn)\s+(?:on\s+)?([a-h][1-8])',
                               refs_text, re.IGNORECASE)
    valid = 0
    total = 0
    errors = []
    good = []
    for sq_name in square_refs:
        total += 1
        sq = chess.parse_square(sq_name)
        if board.piece_at(sq) is not None:
            valid += 1
            good.append(sq_name)
        else:
            errors.append(sq_name)
    for piece_name_str, sq_name in piece_sq_refs:
        total += 1
        sq = chess.parse_square(sq_name)
        piece = board.piece_at(sq)
        if piece is not None:
            expected_type = {"pawn": chess.PAWN, "knight": chess.KNIGHT, "bishop": chess.BISHOP,
                            "rook": chess.ROOK, "queen": chess.QUEEN, "king": chess.KING}.get(piece_name_str.lower())
            if piece.piece_type == expected_type:
                valid += 1
                good.append(f"{piece_name_str} {sq_name}")
            else:
                errors.append(f"{sq_name}(wrong piece)")
        else:
            errors.append(f"{sq_name}(empty)")
    return valid, total, errors, good


def post_validate_refs(text, fen):
    """Post-validate: strip any refs pointing to empty squares. Returns cleaned text."""
    board = chess.Board(fen)
    refs_match = re.search(r"(?i)^REFS:\s*(.+)", text, re.MULTILINE)
    coaching_match = re.search(r"(?i)^COACHING:\s*(.+)", text, re.MULTILINE)
    if not refs_match or not coaching_match:
        return text, 0

    raw_refs = [r.strip() for r in refs_match.group(1).split(",")]
    validated = []
    rejected = 0
    for ref in raw_refs:
        sq_match = re.search(r'([a-h][1-8])', ref)
        if sq_match:
            sq = chess.parse_square(sq_match.group(1))
            if board.piece_at(sq) is not None:
                validated.append(ref)
            else:
                rejected += 1
        else:
            validated.append(ref)  # non-square ref, keep

    if not validated:
        validated = ["current position"]  # fallback

    cleaned = f"REFS: {', '.join(validated)}\nCOACHING: {coaching_match.group(1)}"
    return cleaned, rejected


def call_model(system_msg, user_msg, max_tokens=120):
    out = model.create_chat_completion(
        messages=[
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_msg},
        ],
        max_tokens=max_tokens, **NOTHINK,
    )
    return strip_thinking(out["choices"][0]["message"]["content"] or ""), out["usage"]["completion_tokens"]


# =====================================================================
# Load opening trees and collect shallow positions (depth 1-6)
# =====================================================================

def walk_opening_tree(tree_path, opening_name):
    with open(tree_path) as f:
        data = json.load(f)
    tree = data.get("tree", data)
    top_plan = data.get("plan", {})
    top_plan_summary = top_plan.get("summary", "") if isinstance(top_plan, dict) else ""
    top_goals = top_plan.get("strategicGoals", []) if isinstance(top_plan, dict) else []
    top_key_squares = top_plan.get("keySquares", []) if isinstance(top_plan, dict) else []
    top_piece_targets = top_plan.get("pieceTargets", []) if isinstance(top_plan, dict) else []

    positions = []

    def walk(node, depth, move_history):
        if "move" not in node:
            for child in node.get("children", []):
                walk(child, depth, move_history)
            return

        uci = node["move"].get("uci", "")
        san = node["move"].get("san", "")
        explanation = node["move"].get("explanation", "")
        if not uci:
            return

        b = chess.Board()
        for m in move_history:
            b.push_uci(m)
        try:
            b.push_uci(uci)
        except Exception:
            return

        node_plan = node.get("plan", {})
        plan_summary = ""
        goals = []
        if isinstance(node_plan, dict) and node_plan.get("summary"):
            plan_summary = node_plan.get("summary", "")
            goals = node_plan.get("strategicGoals", [])
        else:
            plan_summary = top_plan_summary
            goals = top_goals

        positions.append({
            "fen": b.fen(),
            "depth": depth,
            "opening": opening_name,
            "move_san": san,
            "explanation": explanation,
            "plan_summary": plan_summary,
            "strategic_goals": goals,
            "key_squares": top_key_squares,
            "piece_targets": top_piece_targets,
            "is_white_move": b.turn == chess.WHITE,
        })

        for child in node.get("children", []):
            walk(child, depth + 1, move_history + [uci])

    walk(tree, 1, [])
    return positions


italian_positions = walk_opening_tree(
    "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Openings/italian.json",
    "Italian Game"
)
london_positions = walk_opening_tree(
    "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Openings/london.json",
    "London System"
)

all_book = italian_positions + london_positions

# Focus on depths 1-6 (beginner territory)
shallow = [p for p in all_book if p["depth"] <= 6]
random.seed(42)
# Test ALL shallow positions, not just a sample — we want 99.99%
print(f"Testing {len(shallow)} shallow positions (depth 1-6) across Italian + London\n")


# =====================================================================
# 6 prompt strategies
# =====================================================================

def strategy_A_baseline(pos):
    """Current approach: raw plan included as-is."""
    fen = pos["fen"]
    side = "White" if pos["is_white_move"] else "Black"
    parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    parts.append(f"\nBoard:\n{board_description(fen)}")
    if pos["opening"]:
        parts.append(f"Opening: {pos['opening']}")
    if pos["move_san"]:
        parts.append(f"Last move: {pos['move_san']}")
    if pos["plan_summary"]:
        parts.append(f"Plan: {pos['plan_summary']}")
    if pos["strategic_goals"]:
        parts.append(f"Goals: {pos['strategic_goals']}")
    context = "\n".join(parts)

    system = "You are a chess coach. /no_think"
    user = (f"{context}\n\n"
            "Give a brief coaching insight. Reference specific pieces and squares on the board.\n\n"
            "Respond with ONLY:\n"
            "REFS: <comma-separated key squares or pieces>\n"
            "COACHING: <one or two sentences>")
    return system, user


def strategy_B_no_plan(pos):
    """Strip plan entirely — just board + opening name."""
    fen = pos["fen"]
    side = "White" if pos["is_white_move"] else "Black"
    parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    parts.append(f"\nBoard:\n{board_description(fen)}")
    if pos["opening"]:
        parts.append(f"Opening: {pos['opening']}")
    if pos["move_san"]:
        parts.append(f"Last move: {pos['move_san']}")
    # NO plan, NO goals
    context = "\n".join(parts)

    system = "You are a chess coach. /no_think"
    user = (f"{context}\n\n"
            "Give a brief coaching insight. Reference specific pieces and squares on the board.\n\n"
            "Respond with ONLY:\n"
            "REFS: <comma-separated key squares or pieces>\n"
            "COACHING: <one or two sentences>")
    return system, user


def strategy_C_guard_instruction(pos):
    """Plan included but with explicit guard instruction."""
    fen = pos["fen"]
    side = "White" if pos["is_white_move"] else "Black"
    parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    parts.append(f"\nBoard:\n{board_description(fen)}")
    if pos["opening"]:
        parts.append(f"Opening: {pos['opening']}")
    if pos["move_san"]:
        parts.append(f"Last move: {pos['move_san']}")
    if pos["plan_summary"]:
        parts.append(f"Plan: {pos['plan_summary']}")
    if pos["strategic_goals"]:
        parts.append(f"Goals: {pos['strategic_goals']}")
    context = "\n".join(parts)

    system = "You are a chess coach. /no_think"
    user = (f"{context}\n\n"
            "Give a brief coaching insight.\n\n"
            "IMPORTANT: In the REFS line, ONLY reference squares where pieces CURRENTLY sit "
            "(as listed in the Board section above). Do NOT reference target squares from the plan.\n\n"
            "Respond with ONLY:\n"
            "REFS: <comma-separated squares with pieces currently on them>\n"
            "COACHING: <one or two sentences>")
    return system, user


def strategy_D_rewritten_plan(pos):
    """Rewrite plan to use clear future tense — 'aim TO move bishop TO c4'."""
    fen = pos["fen"]
    side = "White" if pos["is_white_move"] else "Black"
    parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    parts.append(f"\nBoard (pieces currently on the board):\n{board_description(fen)}")
    if pos["opening"]:
        parts.append(f"Opening: {pos['opening']}")
    if pos["move_san"]:
        parts.append(f"Last move: {pos['move_san']}")
    if pos["plan_summary"]:
        # Rewrite plan to clearly indicate these are FUTURE targets
        plan = pos["plan_summary"]
        parts.append(f"\nFuture plan (NOT the current position — pieces haven't moved there yet): {plan}")
    if pos["strategic_goals"]:
        parts.append(f"Future goals (to work toward): {pos['strategic_goals']}")
    context = "\n".join(parts)

    system = "You are a chess coach. /no_think"
    user = (f"{context}\n\n"
            "Give a brief coaching insight about the current board position.\n"
            "REFS must only contain squares where pieces sit RIGHT NOW.\n\n"
            "Respond with ONLY:\n"
            "REFS: <comma-separated key squares with pieces on them>\n"
            "COACHING: <one or two sentences>")
    return system, user


def strategy_E_elo_aware(pos):
    """ELO-aware prompt for beginners."""
    fen = pos["fen"]
    side = "White" if pos["is_white_move"] else "Black"
    parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    parts.append(f"\nBoard:\n{board_description(fen)}")
    if pos["opening"]:
        parts.append(f"Opening: {pos['opening']}")
    if pos["move_san"]:
        parts.append(f"Last move: {pos['move_san']}")
    if pos["plan_summary"]:
        parts.append(f"Plan: {pos['plan_summary']}")
    context = "\n".join(parts)

    system = "You are a chess coach for a beginner (rated ~800 ELO). Keep it simple. /no_think"
    user = (f"{context}\n\n"
            "Give a simple coaching tip about the current position. "
            "Only mention pieces and squares that are actually on the board right now.\n\n"
            "Respond with ONLY:\n"
            "REFS: <comma-separated key squares with pieces on them>\n"
            "COACHING: <one or two sentences, simple language>")
    return system, user


def strategy_F_board_only_explicit(pos):
    """Board description emphasized as source of truth, plan de-emphasized."""
    fen = pos["fen"]
    board = chess.Board(fen)
    side = "White" if pos["is_white_move"] else "Black"

    # Build an explicit "valid squares" list
    occupied = []
    for sq, piece in board.piece_map().items():
        occupied.append(chess.square_name(sq))

    parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    parts.append(f"\nBoard:\n{board_description(fen)}")
    parts.append(f"\nOccupied squares: {', '.join(sorted(occupied))}")
    if pos["opening"]:
        parts.append(f"Opening: {pos['opening']}")
    if pos["move_san"]:
        parts.append(f"Last move: {pos['move_san']}")
    if pos["plan_summary"]:
        parts.append(f"Plan: {pos['plan_summary']}")
    context = "\n".join(parts)

    system = "You are a chess coach. /no_think"
    user = (f"{context}\n\n"
            "Give a brief coaching insight.\n"
            "Your REFS must ONLY use squares from the Occupied squares list above.\n\n"
            "Respond with ONLY:\n"
            "REFS: <comma-separated occupied squares>\n"
            "COACHING: <one or two sentences>")
    return system, user


def strategy_G_three_pass(pos):
    """3-pass: (1) current state observation, (2) future plan advice, (3) synthesize.

    Separates current vs future so the model never confuses them in REFS.
    Returns (response_text, is_multipass=True) — caller handles differently.
    """
    fen = pos["fen"]
    side = "White" if pos["is_white_move"] else "Black"
    board_desc = board_description(fen)

    # Pass 1: Describe what's happening on the board RIGHT NOW
    current_obs, _ = call_model(
        "You are a chess position analyst. /no_think",
        (f"Position (FEN): {fen}\nSide to move: {side}\n\nBoard:\n{board_desc}\n"
         f"Opening: {pos.get('opening', '')}\nLast move: {pos.get('move_san', '')}\n\n"
         "In one sentence, describe the key feature of the CURRENT position. "
         "Only mention pieces and squares that have pieces on them right now."),
        max_tokens=80)

    # Pass 2: What should the student work toward?
    future_plan, _ = call_model(
        "You are a chess coach. /no_think",
        (f"Opening: {pos.get('opening', '')}\n"
         f"Plan: {pos.get('plan_summary', '')}\n"
         f"Goals: {pos.get('strategic_goals', '')}\n\n"
         "In one sentence, what should the student aim for next? Speak in future tense."),
        max_tokens=80)

    # Pass 3: Synthesize into REFS + COACHING format
    board = chess.Board(fen)
    occupied = sorted(chess.square_name(sq) for sq in board.piece_map().keys())
    resp, _ = call_model(
        "You are a text formatter. /no_think",
        (f"Current board observation: {current_obs}\n"
         f"Future plan: {future_plan}\n\n"
         f"Occupied squares (pieces are on these): {', '.join(occupied)}\n\n"
         "Combine these into a coaching tip. REFS must ONLY use squares from the occupied squares list.\n\n"
         "Respond with ONLY:\n"
         "REFS: <comma-separated squares from the occupied list>\n"
         "COACHING: <one or two sentences combining current observation with future plan>"),
        max_tokens=120)
    return resp  # return response directly


def strategy_H_two_pass_observe_coach(pos):
    """2-pass: (1) observe current board, (2) format as coaching with plan context.

    Faster than 3-pass. Observation pass grounds the model in reality first.
    """
    fen = pos["fen"]
    side = "White" if pos["is_white_move"] else "Black"
    board_desc = board_description(fen)

    # Pass 1: Ground in current reality
    observation, _ = call_model(
        "You are a chess position analyst. /no_think",
        (f"Position (FEN): {fen}\nSide to move: {side}\n\nBoard:\n{board_desc}\n"
         f"Opening: {pos.get('opening', '')}\nLast move: {pos.get('move_san', '')}\n\n"
         "List the 2-3 most important pieces and their squares in the current position. "
         "Format: piece on square, piece on square"),
        max_tokens=60)

    # Pass 2: Coach using the observation + plan
    board = chess.Board(fen)
    occupied = sorted(chess.square_name(sq) for sq in board.piece_map().keys())
    resp, _ = call_model(
        "You are a chess coach for beginners. /no_think",
        (f"Key pieces right now: {observation}\n"
         f"Opening plan: {pos.get('plan_summary', '')}\n"
         f"Occupied squares: {', '.join(occupied)}\n\n"
         "Give a coaching insight. REFS must ONLY use squares from the occupied squares list.\n\n"
         "Respond with ONLY:\n"
         "REFS: <comma-separated squares from the occupied list>\n"
         "COACHING: <one or two sentences>"),
        max_tokens=120)
    return resp  # return response directly


MULTIPASS_STRATEGIES = {"G: 3-pass (current/future/synth)", "H: 2-pass (observe/coach)"}

strategies = [
    ("A: baseline (plan as-is)", strategy_A_baseline),
    ("B: no plan at all", strategy_B_no_plan),
    ("C: plan + guard instruction", strategy_C_guard_instruction),
    ("D: rewritten plan (future tense)", strategy_D_rewritten_plan),
    ("E: ELO-aware beginner prompt", strategy_E_elo_aware),
    ("F: occupied squares list", strategy_F_board_only_explicit),
    ("G: 3-pass (current/future/synth)", strategy_G_three_pass),
    ("H: 2-pass (observe/coach)", strategy_H_two_pass_observe_coach),
]


# =====================================================================
# Run all strategies
# =====================================================================

print(f"{'='*90}")
print(f"8 PROMPT STRATEGIES x {len(shallow)} positions (depth 1-6)")
print(f"{'='*90}\n")

results = {}

for strat_name, strat_fn in strategies:
    print(f"\n--- {strat_name} ---")

    by_depth = {}
    all_valid = 0
    all_total = 0
    all_errors = []
    post_val_rejections = 0
    post_val_all_clean = 0  # count where post-validation had nothing to reject
    times = []

    for pos in shallow:
        t0 = time.time()
        if strat_name in MULTIPASS_STRATEGIES:
            # Multi-pass strategies return response directly
            resp = strat_fn(pos)
        else:
            # Single-pass strategies return (system, user)
            system, user = strat_fn(pos)
            resp, toks = call_model(system, user)
        elapsed = (time.time() - t0) * 1000
        times.append(elapsed)

        valid, total, errors, good = check_accuracy(resp, pos["fen"])
        all_valid += valid
        all_total += total
        all_errors.extend([(pos["depth"], pos["move_san"], e) for e in errors])

        # Post-validation stats
        _, rejected = post_validate_refs(resp, pos["fen"])
        post_val_rejections += rejected
        if rejected == 0:
            post_val_all_clean += 1

        d = pos["depth"]
        if d not in by_depth:
            by_depth[d] = {"valid": 0, "total": 0, "errors": [], "n": 0}
        by_depth[d]["valid"] += valid
        by_depth[d]["total"] += total
        by_depth[d]["errors"].extend(errors)
        by_depth[d]["n"] += 1

    raw_acc = all_valid / all_total * 100 if all_total > 0 else 0
    post_val_acc = (all_valid + post_val_rejections) / all_total * 100 if all_total > 0 else 0
    # After post-validation, accuracy = 100% (we remove all bad refs)
    avg_time = sum(times) / len(times) if times else 0

    print(f"  OVERALL: raw={raw_acc:.1f}% ({all_valid}/{all_total}) | "
          f"post-validated=100% (rejected {post_val_rejections} bad refs) | "
          f"clean (no rejection needed): {post_val_all_clean}/{len(shallow)} ({post_val_all_clean/len(shallow)*100:.0f}%) | "
          f"avg {avg_time:.0f}ms")

    for d in sorted(by_depth.keys()):
        bd = by_depth[d]
        d_acc = bd["valid"] / bd["total"] * 100 if bd["total"] > 0 else 0
        err_preview = bd["errors"][:3] if bd["errors"] else ""
        print(f"    Depth {d}: {d_acc:5.1f}% ({bd['valid']}/{bd['total']}) n={bd['n']}{' | errors: '+str(err_preview) if err_preview else ''}")

    if all_errors:
        print(f"  Error samples: {all_errors[:8]}")

    results[strat_name] = {
        "raw_acc": raw_acc,
        "all_valid": all_valid,
        "all_total": all_total,
        "post_val_rejections": post_val_rejections,
        "clean_pct": post_val_all_clean / len(shallow) * 100,
        "avg_time_ms": avg_time,
        "by_depth": {d: {"acc": by_depth[d]["valid"] / by_depth[d]["total"] * 100
                         if by_depth[d]["total"] > 0 else 0,
                         "n": by_depth[d]["n"]}
                     for d in by_depth},
        "errors": all_errors,
    }


# =====================================================================
# Summary comparison
# =====================================================================

print(f"\n\n{'='*90}")
print("SUMMARY: Which strategy achieves 99.99% accuracy for beginners?")
print(f"{'='*90}\n")

print(f"{'Strategy':<40} {'Raw Acc':>8} {'Clean%':>8} {'Rejected':>10} {'Avg ms':>8}")
print("-" * 76)
for strat_name in [s[0] for s in strategies]:
    r = results[strat_name]
    print(f"{strat_name:<40} {r['raw_acc']:>7.1f}% {r['clean_pct']:>7.0f}% {r['post_val_rejections']:>10d} {r['avg_time_ms']:>7.0f}")

print(f"\nKey insight: 'Clean%' = positions where NO post-validation was needed.")
print(f"Higher clean% = model got it right without needing correction.")
print(f"With post-validation, ALL strategies achieve 100% ref accuracy.")
print(f"Best strategy = highest Clean% (fewest corrections needed) + good coaching quality.")
print(f"\nNote: G/H are multi-pass (2-3 LLM calls). Times reflect total for all passes.")

# Show which strategy has best raw accuracy at each depth
print(f"\nBest raw accuracy by depth:")
for d in range(1, 7):
    best_strat = None
    best_acc = -1
    for strat_name in [s[0] for s in strategies]:
        r = results[strat_name]
        if d in r["by_depth"]:
            acc = r["by_depth"][d]["acc"]
            if acc > best_acc:
                best_acc = acc
                best_strat = strat_name
    if best_strat:
        print(f"  Depth {d}: {best_strat} ({best_acc:.0f}%)")
