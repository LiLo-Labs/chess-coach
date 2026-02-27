"""Benchmark: single vs double call for robustness on Metal."""
import json, re, time, chess
from llama_cpp import Llama

MODEL_PATH = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Qwen3-4B-Q4_K_M.gguf"
model = Llama(model_path=MODEL_PATH, n_ctx=4096, n_gpu_layers=-1, verbose=False)

with open("test_positions.json") as f:
    positions = json.load(f)

test_positions = positions[:15]
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
        return 0, 0
    refs_text = refs_match.group(1)
    square_refs = re.findall(r'\b([a-h][1-8])\b', refs_text)
    piece_sq_refs = re.findall(r'(knight|bishop|rook|queen|king|pawn)\s+(?:on\s+)?([a-h][1-8])', refs_text, re.IGNORECASE)
    valid = 0
    total = 0
    for sq_name in square_refs:
        total += 1
        sq = chess.parse_square(sq_name)
        if board.piece_at(sq) is not None:
            valid += 1
    for piece_name_str, sq_name in piece_sq_refs:
        total += 1
        sq = chess.parse_square(sq_name)
        piece = board.piece_at(sq)
        if piece is not None:
            expected_type = {"pawn": chess.PAWN, "knight": chess.KNIGHT, "bishop": chess.BISHOP,
                            "rook": chess.ROOK, "queen": chess.QUEEN, "king": chess.KING}.get(piece_name_str.lower())
            if piece.piece_type == expected_type:
                valid += 1
    return valid, total


def check_compliance(text):
    text = strip_thinking(text)
    return (bool(re.search(r"(?i)^REFS\s*:", text, re.MULTILINE)) and
            bool(re.search(r"(?i)^COACHING\s*:", text, re.MULTILINE)))


def single_call(pos, context):
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


def pick_better(resp1, resp2, fen):
    """Pick the response with higher accuracy. Tie goes to resp1."""
    v1, t1 = check_accuracy(resp1, fen)
    v2, t2 = check_accuracy(resp2, fen)
    rate1 = v1 / t1 if t1 > 0 else 0
    rate2 = v2 / t2 if t2 > 0 else 0
    # If both same accuracy, prefer more refs
    if rate1 == rate2:
        return (resp1, v1, t1) if t1 >= t2 else (resp2, v2, t2)
    return (resp1, v1, t1) if rate1 >= rate2 else (resp2, v2, t2)


def consensus_refs(resp1, resp2):
    """Merge: take refs that appear in both responses."""
    def get_refs(text):
        m = re.search(r"(?i)^REFS:\s*(.+)", text, re.MULTILINE)
        if not m: return set()
        return set(r.strip().lower() for r in m.group(1).split(","))
    r1 = get_refs(resp1)
    r2 = get_refs(resp2)
    return r1 & r2  # intersection


print(f"Running 15 positions x 3 strategies on Metal (M4 Max)\n")

single_acc = []
double_best_acc = []
double_consensus_acc = []
single_times = []
double_times = []

for i, pos in enumerate(test_positions):
    fen = pos.get("fen_after", "")
    side = "White" if pos.get("is_white_move") else "Black"
    opening = pos.get("opening_name", "")
    move = pos.get("book_move_san", "")
    plan = pos.get("plan_summary", "")
    goals = pos.get("strategic_goals", "")

    context_parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    context_parts.append(f"\nBoard:\n{board_description(fen)}")
    if opening: context_parts.append(f"Opening: {opening}")
    if move: context_parts.append(f"Last move played: {move}")
    if plan: context_parts.append(f"Plan: {plan}")
    if goals: context_parts.append(f"Goals: {goals}")
    context = "\n".join(context_parts)

    # Single call
    t0 = time.time()
    resp1, tok1 = single_call(pos, context)
    t_single = (time.time() - t0) * 1000
    v1, t1 = check_accuracy(resp1, fen)
    acc1 = v1 / t1 * 100 if t1 > 0 else 0
    single_acc.append(acc1)
    single_times.append(t_single)

    # Double call
    t0 = time.time()
    resp_a, tok_a = single_call(pos, context)
    resp_b, tok_b = single_call(pos, context)
    t_double = (time.time() - t0) * 1000
    double_times.append(t_double)

    # Strategy 1: pick best of two
    best_resp, bv, bt = pick_better(resp_a, resp_b, fen)
    acc_best = bv / bt * 100 if bt > 0 else 0
    double_best_acc.append(acc_best)

    # Strategy 2: consensus refs (intersection)
    common_refs = consensus_refs(resp_a, resp_b)
    # Count how many consensus refs are valid
    board = chess.Board(fen)
    cons_valid = 0
    cons_total = len(common_refs)
    for ref in common_refs:
        sq_match = re.search(r'([a-h][1-8])', ref)
        if sq_match:
            sq = chess.parse_square(sq_match.group(1))
            if board.piece_at(sq) is not None:
                cons_valid += 1
    acc_cons = cons_valid / cons_total * 100 if cons_total > 0 else 0
    double_consensus_acc.append(acc_cons)

    print(f"Pos {i:2d} ({opening}/{move})")
    print(f"  Single:    {acc1:5.0f}% ({v1}/{t1}) | {t_single:.0f}ms")
    print(f"  Best-of-2: {acc_best:5.0f}% ({bv}/{bt}) | {t_double:.0f}ms")
    print(f"  Consensus: {acc_cons:5.0f}% ({cons_valid}/{cons_total} common refs) | same {t_double:.0f}ms")
    print(f"  Resp A: {resp_a[:100]}")
    print(f"  Resp B: {resp_b[:100]}")
    print()

n = len(test_positions)
print("=" * 70)
print("SUMMARY")
print("=" * 70)
print(f"  Single call:    avg acc {sum(single_acc)/n:.0f}% | avg {sum(single_times)/n:.0f}ms")
print(f"  Best-of-2:      avg acc {sum(double_best_acc)/n:.0f}% | avg {sum(double_times)/n:.0f}ms")
print(f"  Consensus refs: avg acc {sum(double_consensus_acc)/n:.0f}% | same timing as best-of-2")
