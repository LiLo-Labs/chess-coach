"""Test accuracy at increasing depth down opening lines + off-book positions.
Find where the model breaks down."""
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
    piece_sq_refs = re.findall(r'(knight|bishop|rook|queen|king|pawn)\s+(?:on\s+)?([a-h][1-8])', refs_text, re.IGNORECASE)
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


def check_coaching_hallucination(text, fen):
    """Check coaching text for references to squares with no pieces."""
    text = strip_thinking(text)
    coaching_match = re.search(r"(?i)^COACHING:\s*(.+)", text, re.MULTILINE)
    if not coaching_match:
        return 0, 0
    coaching = coaching_match.group(1)
    board = chess.Board(fen)
    # Find all square references in coaching text
    squares = re.findall(r'\b([a-h][1-8])\b', coaching)
    valid = 0
    total = len(squares)
    for sq_name in squares:
        sq = chess.parse_square(sq_name)
        if board.piece_at(sq) is not None:
            valid += 1
    return valid, total


def single_call(context):
    out = model.create_chat_completion(
        messages=[
            {"role": "system", "content": "You are a chess coach. /no_think"},
            {"role": "user", "content": (
                f"{context}\n\n"
                "Give a brief coaching insight. Reference specific pieces and squares on the board.\n\n"
                "Respond with ONLY:\n"
                "REFS: <comma-separated key squares or pieces>\n"
                "COACHING: <one or two sentences>"
            )},
        ],
        max_tokens=120, **NOTHINK,
    )
    return strip_thinking(out["choices"][0]["message"]["content"] or ""), out["usage"]["completion_tokens"]


# =====================================================================
# Generate positions at various depths from opening trees
# =====================================================================

def walk_opening_tree(tree_path, opening_name):
    """Walk an opening tree and collect positions at every depth."""
    with open(tree_path) as f:
        data = json.load(f)

    # The tree is nested under "tree" key
    tree = data.get("tree", data)
    # Top-level plan applies to all positions in this opening
    top_plan = data.get("plan", {})
    top_plan_summary = top_plan.get("summary", "") if isinstance(top_plan, dict) else ""
    top_goals = top_plan.get("strategicGoals", []) if isinstance(top_plan, dict) else []

    positions = []

    def walk(node, depth, move_history):
        if "move" not in node:
            # Root node — just recurse into children
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

        # Use node-level plan if available, otherwise top-level
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
            "move_history": move_history + [uci],
            "explanation": explanation,
            "plan_summary": plan_summary,
            "strategic_goals": goals,
            "is_white_move": b.turn == chess.WHITE,
        })

        for child in node.get("children", []):
            walk(child, depth + 1, move_history + [uci])

    walk(tree, 1, [])
    return positions


# Load both opening trees
italian_positions = walk_opening_tree(
    "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Openings/italian.json",
    "Italian Game"
)
london_positions = walk_opening_tree(
    "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Openings/london.json",
    "London System"
)

all_book = italian_positions + london_positions
max_depth = max(p["depth"] for p in all_book)
print(f"Loaded {len(italian_positions)} Italian + {len(london_positions)} London positions, max depth {max_depth}")

# Group by depth
by_depth = {}
for p in all_book:
    d = p["depth"]
    if d not in by_depth:
        by_depth[d] = []
    by_depth[d].append(p)

# =====================================================================
# Generate off-book positions (random legal moves from book positions)
# =====================================================================
def make_offbook(book_pos, num_random_moves=2):
    """From a book position, play random legal moves to go off-book."""
    board = chess.Board(book_pos["fen"])
    moves_played = []
    for _ in range(num_random_moves):
        legal = list(board.legal_moves)
        if not legal:
            break
        move = random.choice(legal)
        moves_played.append(board.san(move))
        board.push(move)
    return {
        "fen": board.fen(),
        "depth": book_pos["depth"] + num_random_moves,
        "opening": book_pos["opening"] + " (off-book)",
        "move_san": "+".join(moves_played),
        "is_white_move": board.turn == chess.WHITE,
        "plan_summary": "",  # no plan for off-book
        "strategic_goals": [],
        "explanation": "",
    }


# =====================================================================
# Run tests
# =====================================================================
print(f"\n{'='*80}")
print("PART 1: IN-BOOK — accuracy by depth")
print(f"{'='*80}\n")

random.seed(42)
depth_results = {}

for depth in sorted(by_depth.keys()):
    pool = by_depth[depth]
    sample = random.sample(pool, min(5, len(pool)))

    ref_accs = []
    coaching_accs = []
    errors_list = []
    times = []

    for pos in sample:
        fen = pos["fen"]
        side = "White" if pos["is_white_move"] else "Black"
        context_parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
        context_parts.append(f"\nBoard:\n{board_description(fen)}")
        if pos["opening"]:
            context_parts.append(f"Opening: {pos['opening']}")
        if pos["move_san"]:
            context_parts.append(f"Last move: {pos['move_san']}")
        if pos["plan_summary"]:
            context_parts.append(f"Plan: {pos['plan_summary']}")
        if pos["strategic_goals"]:
            context_parts.append(f"Goals: {pos['strategic_goals']}")
        context = "\n".join(context_parts)

        t0 = time.time()
        resp, toks = single_call(context)
        elapsed = (time.time() - t0) * 1000
        times.append(elapsed)

        valid, total, errors, good = check_accuracy(resp, fen)
        ref_acc = valid / total * 100 if total > 0 else 100
        ref_accs.append(ref_acc)
        errors_list.extend(errors)

        cv, ct = check_coaching_hallucination(resp, fen)
        c_acc = cv / ct * 100 if ct > 0 else 100
        coaching_accs.append(c_acc)

    avg_ref = sum(ref_accs) / len(ref_accs)
    avg_coach = sum(coaching_accs) / len(coaching_accs)
    avg_time = sum(times) / len(times)
    depth_results[depth] = {"ref_acc": avg_ref, "coach_acc": avg_coach, "n": len(sample),
                            "errors": errors_list, "time": avg_time}

    err_str = f" | errors: {errors_list[:5]}" if errors_list else ""
    print(f"  Depth {depth:2d}: {len(sample)} positions | ref_acc={avg_ref:5.1f}% | coaching_acc={avg_coach:5.1f}% | {avg_time:.0f}ms{err_str}")

print(f"\n{'='*80}")
print("PART 2: OFF-BOOK — accuracy with no plan context")
print(f"{'='*80}\n")

# Generate off-book from various depths
offbook_results = {}
for source_depth in [2, 4, 6, 8]:
    pool = by_depth.get(source_depth, [])
    if not pool:
        continue
    sample_book = random.sample(pool, min(3, len(pool)))

    for num_random in [1, 2, 3, 4]:
        key = f"depth{source_depth}+{num_random}rand"
        ref_accs = []
        coaching_accs = []
        errors_list = []
        times = []

        for book_pos in sample_book:
            pos = make_offbook(book_pos, num_random)
            fen = pos["fen"]
            side = "White" if pos["is_white_move"] else "Black"

            # Off-book: no plan, no goals — just board + opening name
            context_parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
            context_parts.append(f"\nBoard:\n{board_description(fen)}")
            context_parts.append(f"Opening origin: {book_pos['opening']}")
            context = "\n".join(context_parts)

            t0 = time.time()
            resp, toks = single_call(context)
            elapsed = (time.time() - t0) * 1000
            times.append(elapsed)

            valid, total, errors, good = check_accuracy(resp, fen)
            ref_acc = valid / total * 100 if total > 0 else 100
            ref_accs.append(ref_acc)
            errors_list.extend(errors)

            cv, ct = check_coaching_hallucination(resp, fen)
            c_acc = cv / ct * 100 if ct > 0 else 100
            coaching_accs.append(c_acc)

        avg_ref = sum(ref_accs) / len(ref_accs)
        avg_coach = sum(coaching_accs) / len(coaching_accs)
        avg_time = sum(times) / len(times)
        offbook_results[key] = {"ref_acc": avg_ref, "coach_acc": avg_coach, "n": len(ref_accs),
                                "errors": errors_list, "time": avg_time}

        err_str = f" | errors: {errors_list[:5]}" if errors_list else ""
        print(f"  {key}: {len(ref_accs)} positions | ref_acc={avg_ref:5.1f}% | coaching_acc={avg_coach:5.1f}% | {avg_time:.0f}ms{err_str}")

print(f"\n{'='*80}")
print("PART 3: COMPLEX MIDDLEGAME + ENDGAME positions")
print(f"{'='*80}\n")

# Hand-crafted tricky positions
complex_positions = [
    {
        "name": "Sicilian middlegame (pieces everywhere)",
        "fen": "r1b2rk1/2q1bppp/p2ppn2/1p4B1/3NP3/2N5/PPPQ1PPP/2KR3R w - - 0 12",
        "description": "Sharp Sicilian with opposite-side castling",
    },
    {
        "name": "Ruy Lopez endgame",
        "fen": "8/5pk1/3p2p1/2pP4/1pP1K3/1P6/P7/8 w - - 0 40",
        "description": "King and pawn endgame",
    },
    {
        "name": "Queen's Gambit Declined middlegame",
        "fen": "r1bq1rk1/ppp2ppp/2nb1n2/3pp3/2PP4/2N1PN2/PP3PPP/R1BQKB1R w KQ - 0 7",
        "description": "Classical QGD structure",
    },
    {
        "name": "King's Indian Attack",
        "fen": "r1bqk2r/ppp2ppp/2n1pn2/3p4/1bPP4/2N1PN2/PP3PPP/R1BQKB1R w KQkq - 0 6",
        "description": "Closed center, maneuvering",
    },
    {
        "name": "Tactical position (hanging pieces)",
        "fen": "r2qkb1r/ppp2ppp/2n2n2/3pp1B1/2B1P1b1/2NP1N2/PPP2PPP/R2QK2R w KQkq - 4 6",
        "description": "Multiple pieces under attack",
    },
    {
        "name": "Rook endgame",
        "fen": "8/8/4kpp1/3p4/3P1P2/4K1P1/7r/4R3 w - - 0 45",
        "description": "Complex rook endgame",
    },
    {
        "name": "Early opening (move 2)",
        "fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
        "description": "Very early — almost no development",
    },
    {
        "name": "Closed Catalan",
        "fen": "rnbq1rk1/ppp1bppp/4pn2/3p4/2PP4/5NP1/PP2PPBP/RNBQK2R w KQ - 0 6",
        "description": "Catalan with fianchetto bishop",
    },
    {
        "name": "Wild tactical mess",
        "fen": "r1b1k2r/ppppqppp/2n2n2/2b1p1N1/2B1P3/3P4/PPP2PPP/RNBQK2R w KQkq - 0 6",
        "description": "Knight on g5 attacking f7, bishop on c5",
    },
    {
        "name": "Pawnless endgame",
        "fen": "4k3/8/8/8/3BK3/8/8/8 w - - 0 60",
        "description": "King + bishop vs king (draw)",
    },
]

for pos in complex_positions:
    fen = pos["fen"]
    board = chess.Board(fen)
    side = "White" if board.turn == chess.WHITE else "Black"

    context_parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    context_parts.append(f"\nBoard:\n{board_description(fen)}")
    # No opening context — model is on its own
    context = "\n".join(context_parts)

    t0 = time.time()
    resp, toks = single_call(context)
    elapsed = (time.time() - t0) * 1000

    valid, total, errors, good = check_accuracy(resp, fen)
    ref_acc = valid / total * 100 if total > 0 else 100

    cv, ct = check_coaching_hallucination(resp, fen)
    c_acc = cv / ct * 100 if ct > 0 else 100

    num_pieces = len(board.piece_map())
    err_str = f" | BAD: {errors}" if errors else ""
    print(f"  {pos['name']} ({num_pieces} pieces)")
    print(f"    ref_acc={ref_acc:.0f}% ({valid}/{total}) | coaching_acc={c_acc:.0f}% | {elapsed:.0f}ms{err_str}")
    print(f"    {resp[:150]}")
    print()

print(f"\n{'='*80}")
print("PART 4: POST-VALIDATION FILTER (backup plan)")
print(f"{'='*80}\n")

# Re-run complex positions with post-validation
print("Re-running complex positions with board-validated refs:\n")
for pos in complex_positions:
    fen = pos["fen"]
    board = chess.Board(fen)
    side = "White" if board.turn == chess.WHITE else "Black"

    context_parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    context_parts.append(f"\nBoard:\n{board_description(fen)}")
    context = "\n".join(context_parts)

    resp, toks = single_call(context)

    # Extract and validate refs
    refs_match = re.search(r"(?i)^REFS:\s*(.+)", resp, re.MULTILINE)
    coaching_match = re.search(r"(?i)^COACHING:\s*(.+)", resp, re.MULTILINE)

    if refs_match:
        raw_refs = [r.strip() for r in refs_match.group(1).split(",")]
        validated_refs = []
        rejected_refs = []
        for ref in raw_refs:
            sq_match = re.search(r'([a-h][1-8])', ref)
            if sq_match:
                sq = chess.parse_square(sq_match.group(1))
                if board.piece_at(sq) is not None:
                    validated_refs.append(ref)
                else:
                    rejected_refs.append(ref)
            else:
                # Non-square ref (like "central pawns") — keep it
                validated_refs.append(ref)

        coaching = coaching_match.group(1) if coaching_match else ""
        print(f"  {pos['name']}")
        print(f"    Raw refs:      {raw_refs}")
        print(f"    Validated:     {validated_refs}")
        if rejected_refs:
            print(f"    REJECTED:      {rejected_refs}")
        print(f"    Coaching:      {coaching[:120]}")
        print(f"    Valid rate:    {len(validated_refs)}/{len(raw_refs)}")
        print()
