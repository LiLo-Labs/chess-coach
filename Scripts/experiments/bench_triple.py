"""Benchmark: 1 vs 2 vs 3 calls, plus majority-vote and union/intersection strategies."""
import json, re, time, chess
from collections import Counter
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


def get_refs_set(text):
    """Extract normalized ref tokens from REFS line."""
    m = re.search(r"(?i)^REFS:\s*(.+)", text, re.MULTILINE)
    if not m:
        return set()
    return set(r.strip().lower() for r in m.group(1).split(",") if r.strip())


def get_coaching(text):
    m = re.search(r"(?i)^COACHING:\s*(.+)", text, re.MULTILINE)
    return m.group(1).strip() if m else ""


def check_ref_accuracy(refs_set, fen):
    """Check what fraction of refs point to occupied squares."""
    board = chess.Board(fen)
    valid = 0
    total = 0
    for ref in refs_set:
        sq_match = re.search(r'([a-h][1-8])', ref)
        if sq_match:
            total += 1
            sq = chess.parse_square(sq_match.group(1))
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
    return strip_thinking(out["choices"][0]["message"]["content"] or "")


def build_context(pos):
    fen = pos.get("fen_after", "")
    side = "White" if pos.get("is_white_move") else "Black"
    parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
    parts.append(f"\nBoard:\n{board_description(fen)}")
    for key, label in [("opening_name", "Opening"), ("book_move_san", "Last move played"),
                        ("plan_summary", "Plan"), ("strategic_goals", "Goals")]:
        val = pos.get(key, "")
        if val:
            parts.append(f"{label}: {val}")
    return "\n".join(parts)


print(f"Running 15 positions on Metal (M4 Max)\n")

# Collect all data
all_results = []

for i, pos in enumerate(test_positions):
    fen = pos.get("fen_after", "")
    context = build_context(pos)
    opening = pos.get("opening_name", "")
    move = pos.get("book_move_san", "")

    t0 = time.time()
    r1 = single_call(context)
    t1 = (time.time() - t0) * 1000

    t0 = time.time()
    r2 = single_call(context)
    t2 = (time.time() - t0) * 1000

    t0 = time.time()
    r3 = single_call(context)
    t3 = (time.time() - t0) * 1000

    responses = [r1, r2, r3]
    ref_sets = [get_refs_set(r) for r in responses]
    coachings = [get_coaching(r) for r in responses]

    # --- Strategies ---

    # 1-call
    v1, t1_refs = check_ref_accuracy(ref_sets[0], fen)
    acc_1 = v1 / t1_refs * 100 if t1_refs > 0 else 0

    # 2-call best
    accs_2 = []
    for j in range(2):
        v, t_r = check_ref_accuracy(ref_sets[j], fen)
        accs_2.append((v / t_r * 100 if t_r > 0 else 0, v, t_r))
    best_2 = max(accs_2, key=lambda x: x[0])

    # 2-call intersection
    inter_2 = ref_sets[0] & ref_sets[1]
    vi2, ti2 = check_ref_accuracy(inter_2, fen)
    acc_inter_2 = vi2 / ti2 * 100 if ti2 > 0 else 0

    # 3-call best
    accs_3 = []
    for j in range(3):
        v, t_r = check_ref_accuracy(ref_sets[j], fen)
        accs_3.append((v / t_r * 100 if t_r > 0 else 0, v, t_r))
    best_3 = max(accs_3, key=lambda x: x[0])

    # 3-call majority vote on refs (keep refs appearing in 2+ of 3)
    all_refs = []
    for rs in ref_sets:
        all_refs.extend(rs)
    ref_counts = Counter(all_refs)
    majority_refs = set(r for r, c in ref_counts.items() if c >= 2)
    vm, tm = check_ref_accuracy(majority_refs, fen)
    acc_majority = vm / tm * 100 if tm > 0 else 0

    # 3-call intersection (all 3 agree)
    inter_3 = ref_sets[0] & ref_sets[1] & ref_sets[2]
    vi3, ti3 = check_ref_accuracy(inter_3, fen)
    acc_inter_3 = vi3 / ti3 * 100 if ti3 > 0 else 0

    # 3-call union (any ref from any call)
    union_3 = ref_sets[0] | ref_sets[1] | ref_sets[2]
    vu3, tu3 = check_ref_accuracy(union_3, fen)
    acc_union_3 = vu3 / tu3 * 100 if tu3 > 0 else 0

    all_results.append({
        "pos": f"{opening}/{move}",
        "1-call": acc_1,
        "2-best": best_2[0],
        "2-inter": acc_inter_2,
        "3-best": best_3[0],
        "3-majority": acc_majority,
        "3-inter": acc_inter_3,
        "3-union": acc_union_3,
        "t1": t1, "t2": t1 + t2, "t3": t1 + t2 + t3,
        "refs": [ref_sets[0], ref_sets[1], ref_sets[2]],
        "majority_refs": majority_refs,
        "inter_3_refs": inter_3,
    })

    print(f"Pos {i:2d} ({opening}/{move})")
    print(f"  Call 1: {ref_sets[0]}")
    print(f"  Call 2: {ref_sets[1]}")
    print(f"  Call 3: {ref_sets[2]}")
    print(f"  Majority (2/3): {majority_refs}")
    print(f"  1-call: {acc_1:.0f}% | 2-best: {best_2[0]:.0f}% | 2-inter: {acc_inter_2:.0f}% | 3-best: {best_3[0]:.0f}% | 3-majority: {acc_majority:.0f}% | 3-inter: {acc_inter_3:.0f}% | 3-union: {acc_union_3:.0f}%")
    print(f"  Times: 1-call={t1:.0f}ms, 2-call={t1+t2:.0f}ms, 3-call={t1+t2+t3:.0f}ms")
    print()

# Summary
n = len(all_results)
print("=" * 80)
print("SUMMARY (avg across 15 positions)")
print("=" * 80)
strategies = [
    ("1-call",       "1-call",     "t1"),
    ("2-call best",  "2-best",     "t2"),
    ("2-call inter", "2-inter",    "t2"),
    ("3-call best",  "3-best",     "t3"),
    ("3-call majority", "3-majority", "t3"),
    ("3-call inter", "3-inter",    "t3"),
    ("3-call union", "3-union",    "t3"),
]
print(f"{'Strategy':<20} {'Accuracy':>10} {'Avg Time':>10} {'~iPhone':>10}")
print("-" * 52)
for label, key, tkey in strategies:
    avg_acc = sum(r[key] for r in all_results) / n
    avg_t = sum(r[tkey] for r in all_results) / n
    iphone_est = avg_t * 2.0  # rough M4 Max -> iPhone scaling
    print(f"{label:<20} {avg_acc:>9.1f}% {avg_t:>9.0f}ms {iphone_est:>9.0f}ms")
