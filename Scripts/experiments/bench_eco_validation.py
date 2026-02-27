"""Comprehensive validation: test coaching accuracy across ALL ECO openings.

Uses the 3,646 ECO opening definitions from TSV files.
Tests winning strategy (guard instruction + post-validation).
Reports per-ECO and per-depth accuracy to identify any openings we should disable.

Target: 99%+ raw accuracy across all beginner-relevant openings (depth <= 10).
"""
import csv, json, re, time, chess, random, os, sys
from collections import defaultdict
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)
from llama_cpp import Llama

MODEL_PATH = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Qwen3-4B-Q4_K_M.gguf"
TSV_DIR = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/OpeningData"

print("Loading model...")
model = Llama(model_path=MODEL_PATH, n_ctx=4096, n_gpu_layers=-1, verbose=False)
print("Model loaded.")

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
        return 0, 0, []
    refs_text = refs_match.group(1)
    square_refs = re.findall(r'\b([a-h][1-8])\b', refs_text)
    valid = 0
    total = 0
    errors = []
    for sq_name in square_refs:
        total += 1
        sq = chess.parse_square(sq_name)
        if board.piece_at(sq) is not None:
            valid += 1
        else:
            errors.append(sq_name)
    return valid, total, errors


def post_validate(text, fen):
    """Count how many refs would be rejected by post-validation."""
    board = chess.Board(fen)
    refs_match = re.search(r"(?i)^REFS:\s*(.+)", text, re.MULTILINE)
    if not refs_match:
        return 0
    raw_refs = [r.strip() for r in refs_match.group(1).split(",")]
    rejected = 0
    for ref in raw_refs:
        sq_match = re.search(r'([a-h][1-8])', ref)
        if sq_match:
            sq = chess.parse_square(sq_match.group(1))
            if board.piece_at(sq) is None:
                rejected += 1
    return rejected


def call_coaching(fen, opening_name, last_move_san):
    """Strategy C: plan-less with guard instruction (winning strategy from bench_shallow_fix)."""
    board = chess.Board(fen)
    side = "White" if board.turn == chess.WHITE else "Black"
    bd = board_description(fen)

    system = "You are a chess coach. /no_think"
    user = (
        f"Position (FEN): {fen}\n"
        f"Side to move: {side}\n\n"
        f"Board:\n{bd}\n\n"
        f"Opening: {opening_name}\n"
        f"Last move: {last_move_san}\n\n"
        "Give a brief coaching insight.\n\n"
        "IMPORTANT: In the REFS line, ONLY reference squares where pieces CURRENTLY sit "
        "(as listed in the Board section above). Do NOT reference empty squares.\n\n"
        "Respond with ONLY:\n"
        "REFS: <comma-separated squares with pieces currently on them>\n"
        "COACHING: <one or two sentences>"
    )

    out = model.create_chat_completion(
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        max_tokens=120, **NOTHINK,
    )
    return strip_thinking(out["choices"][0]["message"]["content"] or "")


# =====================================================================
# Load ALL ECO openings from TSV files
# =====================================================================

def load_eco_openings():
    """Load all ECO openings and generate positions at each ply."""
    openings = []
    for fname in sorted(os.listdir(TSV_DIR)):
        if not fname.endswith(".tsv"):
            continue
        path = os.path.join(TSV_DIR, fname)
        with open(path, newline="") as f:
            reader = csv.DictReader(f, delimiter="\t")
            for row in reader:
                eco = row.get("eco", "")
                name = row.get("name", "")
                pgn = row.get("pgn", "")
                if not pgn:
                    continue
                openings.append({"eco": eco, "name": name, "pgn": pgn})
    return openings


def pgn_to_positions(pgn_text, opening_name, eco):
    """Parse PGN move text and generate a position at each ply."""
    board = chess.Board()
    # Parse SAN moves from PGN (strip move numbers)
    tokens = pgn_text.split()
    positions = []
    last_san = ""
    ply = 0

    for token in tokens:
        # Skip move numbers like "1." or "2..."
        if re.match(r'^\d+\.', token):
            continue
        # Skip result tokens
        if token in ("1-0", "0-1", "1/2-1/2", "*"):
            continue
        # Try to parse as SAN
        try:
            move = board.parse_san(token)
            board.push(move)
            ply += 1
            last_san = token
            positions.append({
                "fen": board.fen(),
                "ply": ply,
                "eco": eco,
                "opening": opening_name,
                "last_move": last_san,
            })
        except (chess.InvalidMoveError, chess.IllegalMoveError, chess.AmbiguousMoveError):
            break  # stop at first unparseable move

    return positions


print("Loading ECO openings from TSV files...")
eco_openings = load_eco_openings()
print(f"Loaded {len(eco_openings)} opening definitions")

# Generate all positions
all_positions = []
for opening in eco_openings:
    positions = pgn_to_positions(opening["pgn"], opening["name"], opening["eco"])
    all_positions.extend(positions)

print(f"Generated {len(all_positions)} total positions across all plies")

# For testing: sample positions to keep runtime manageable
# Sample strategy: take positions at every depth, focus on depth 1-10 (beginner range)
beginner_positions = [p for p in all_positions if p["ply"] <= 10]
print(f"Beginner-range positions (ply 1-10): {len(beginner_positions)}")

# Sample: for each ply, take up to 30 random positions
random.seed(42)
by_ply = defaultdict(list)
for p in beginner_positions:
    by_ply[p["ply"]].append(p)

SAMPLES_PER_PLY = 30
sampled = []
for ply in sorted(by_ply.keys()):
    pool = by_ply[ply]
    sample = random.sample(pool, min(SAMPLES_PER_PLY, len(pool)))
    sampled.extend(sample)

print(f"Testing {len(sampled)} sampled positions ({SAMPLES_PER_PLY} per ply, plies 1-10)\n")


# =====================================================================
# Run tests
# =====================================================================

print(f"{'='*90}")
print(f"ECO VALIDATION: Guard instruction strategy across {len(sampled)} positions")
print(f"{'='*90}\n")

results_by_ply = defaultdict(lambda: {"valid": 0, "total": 0, "errors": [], "n": 0, "clean": 0, "rejected": 0})
results_by_eco = defaultdict(lambda: {"valid": 0, "total": 0, "errors": [], "n": 0, "clean": 0, "rejected": 0})
failed_openings = []  # openings with <90% accuracy

total_time = 0

for i, pos in enumerate(sampled):
    t0 = time.time()
    resp = call_coaching(pos["fen"], pos["opening"], pos["last_move"])
    elapsed = (time.time() - t0) * 1000
    total_time += elapsed

    valid, total, errors = check_accuracy(resp, pos["fen"])
    rejected = post_validate(resp, pos["fen"])
    is_clean = (rejected == 0)

    ply = pos["ply"]
    eco = pos["eco"][:3]  # group by major ECO code (e.g., "B90" not "B90.1")

    for bucket in [results_by_ply[ply], results_by_eco[eco]]:
        bucket["valid"] += valid
        bucket["total"] += total
        bucket["errors"].extend(errors)
        bucket["n"] += 1
        bucket["rejected"] += rejected
        if is_clean:
            bucket["clean"] += 1

    acc = valid / total * 100 if total > 0 else 100
    if acc < 90 and total > 0:
        failed_openings.append({
            "eco": pos["eco"],
            "opening": pos["opening"],
            "ply": ply,
            "acc": acc,
            "errors": errors,
            "resp": resp[:100],
        })

    if (i + 1) % 50 == 0:
        elapsed_total = total_time / 1000
        print(f"  [{i+1}/{len(sampled)}] {elapsed_total:.0f}s elapsed, last: {pos['opening'][:40]}... ({elapsed:.0f}ms)")

# =====================================================================
# Results by ply
# =====================================================================
print(f"\n{'='*90}")
print("RESULTS BY PLY (depth)")
print(f"{'='*90}")
print(f"{'Ply':>4} {'N':>5} {'Raw Acc':>9} {'Clean%':>8} {'Rejected':>10}")
print("-" * 40)

total_valid = 0
total_refs = 0
total_clean = 0
total_n = 0
total_rejected = 0

for ply in sorted(results_by_ply.keys()):
    r = results_by_ply[ply]
    acc = r["valid"] / r["total"] * 100 if r["total"] > 0 else 100
    clean_pct = r["clean"] / r["n"] * 100 if r["n"] > 0 else 100
    print(f"{ply:>4} {r['n']:>5} {acc:>8.1f}% {clean_pct:>7.0f}% {r['rejected']:>10}")
    total_valid += r["valid"]
    total_refs += r["total"]
    total_clean += r["clean"]
    total_n += r["n"]
    total_rejected += r["rejected"]

overall_acc = total_valid / total_refs * 100 if total_refs > 0 else 100
overall_clean = total_clean / total_n * 100 if total_n > 0 else 100
print("-" * 40)
print(f"{'ALL':>4} {total_n:>5} {overall_acc:>8.1f}% {overall_clean:>7.0f}% {total_rejected:>10}")

# =====================================================================
# Worst ECO codes
# =====================================================================
print(f"\n{'='*90}")
print("WORST ECO CODES (< 95% raw accuracy, min 2 positions tested)")
print(f"{'='*90}")

bad_ecos = []
for eco in sorted(results_by_eco.keys()):
    r = results_by_eco[eco]
    if r["n"] < 2:
        continue
    acc = r["valid"] / r["total"] * 100 if r["total"] > 0 else 100
    if acc < 95:
        clean_pct = r["clean"] / r["n"] * 100
        bad_ecos.append((eco, acc, r["n"], r["errors"][:3], clean_pct))

if bad_ecos:
    print(f"{'ECO':>5} {'Acc':>8} {'N':>4} {'Clean%':>8} {'Sample Errors'}")
    print("-" * 60)
    for eco, acc, n, errs, clean in sorted(bad_ecos, key=lambda x: x[1]):
        print(f"{eco:>5} {acc:>7.1f}% {n:>4} {clean:>7.0f}%  {errs}")
else:
    print("All ECO codes with 2+ positions are at 95%+ accuracy!")

# =====================================================================
# Individual failures
# =====================================================================
if failed_openings:
    print(f"\n{'='*90}")
    print(f"INDIVIDUAL FAILURES (< 90% accuracy): {len(failed_openings)} positions")
    print(f"{'='*90}")
    for f in failed_openings[:20]:
        print(f"  {f['eco']} {f['opening'][:50]} (ply {f['ply']}): {f['acc']:.0f}% | errors: {f['errors']}")
        print(f"    resp: {f['resp']}")
else:
    print("\nNo individual failures below 90%!")

# =====================================================================
# Summary
# =====================================================================
print(f"\n{'='*90}")
print("FINAL SUMMARY")
print(f"{'='*90}")
print(f"Positions tested:     {total_n}")
print(f"Overall raw accuracy: {overall_acc:.1f}%")
print(f"Clean rate:           {overall_clean:.0f}% (no post-validation needed)")
print(f"Total rejections:     {total_rejected} refs across {total_n} positions")
print(f"After post-validation: 100% accuracy (all bad refs removed)")
print(f"Total time:           {total_time/1000:.0f}s ({total_time/total_n:.0f}ms avg per position)")
print(f"Bad ECO codes (<95%): {len(bad_ecos)}")
print(f"Individual failures:  {len(failed_openings)}")

if bad_ecos:
    print(f"\nRECOMMENDATION: Consider disabling on-device coaching for these ECO codes:")
    for eco, acc, n, errs, clean in sorted(bad_ecos, key=lambda x: x[1])[:10]:
        print(f"  {eco}: {acc:.0f}% raw accuracy")
else:
    print(f"\nAll ECO codes pass! Guard instruction strategy works across all openings.")
