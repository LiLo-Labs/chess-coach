"""Quick ECO validation: test guard-instruction strategy across diverse openings.

Samples 100 positions (10 per ply, plies 1-10) from the 3641 ECO definitions.
Prints after every position for visibility. Includes timeout protection.
"""
import csv, re, time, chess, random, os, sys, signal
from collections import defaultdict

sys.stdout.reconfigure(line_buffering=True)

from llama_cpp import Llama

MODEL_PATH = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Qwen3-4B-Q4_K_M.gguf"
TSV_DIR = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/OpeningData"

print("Loading model...", flush=True)
model = Llama(model_path=MODEL_PATH, n_ctx=4096, n_gpu_layers=-1, verbose=False)
print("Model loaded.", flush=True)

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


def call_coaching(fen, opening_name, last_move_san):
    board = chess.Board(fen)
    side = "White" if board.turn == chess.WHITE else "Black"
    bd = board_description(fen)

    out = model.create_chat_completion(
        messages=[
            {"role": "system", "content": "You are a chess coach. /no_think"},
            {"role": "user", "content": (
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
            )},
        ],
        max_tokens=120, **NOTHINK,
    )
    return strip_thinking(out["choices"][0]["message"]["content"] or "")


# Load ECO openings and build position pool
print("Loading ECO openings...", flush=True)
positions_by_ply = defaultdict(list)

for fname in sorted(os.listdir(TSV_DIR)):
    if not fname.endswith(".tsv"):
        continue
    with open(os.path.join(TSV_DIR, fname), newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            eco = row.get("eco", "")
            name = row.get("name", "")
            pgn = row.get("pgn", "")
            if not pgn:
                continue
            board = chess.Board()
            tokens = pgn.split()
            ply = 0
            last_san = ""
            for token in tokens:
                if re.match(r'^\d+\.', token):
                    continue
                if token in ("1-0", "0-1", "1/2-1/2", "*"):
                    continue
                try:
                    move = board.parse_san(token)
                    board.push(move)
                    ply += 1
                    last_san = token
                    if ply <= 10:
                        positions_by_ply[ply].append({
                            "fen": board.fen(),
                            "eco": eco,
                            "opening": name,
                            "last_move": last_san,
                            "ply": ply,
                        })
                except:
                    break

total_pool = sum(len(v) for v in positions_by_ply.values())
print(f"Position pool: {total_pool} positions across plies 1-10", flush=True)

# Sample 10 per ply
random.seed(42)
SAMPLES_PER_PLY = 10
sampled = []
for ply in range(1, 11):
    pool = positions_by_ply[ply]
    sample = random.sample(pool, min(SAMPLES_PER_PLY, len(pool)))
    sampled.append((ply, sample))

total_tests = sum(len(s) for _, s in sampled)
print(f"Testing {total_tests} positions ({SAMPLES_PER_PLY} per ply)\n", flush=True)

# Run tests
results_by_ply = {}
all_errors_detail = []
overall_valid = 0
overall_total = 0
overall_clean = 0
overall_n = 0
total_time = 0

for ply, sample in sampled:
    ply_valid = 0
    ply_total = 0
    ply_clean = 0
    ply_errors = []

    for pos in sample:
        t0 = time.time()
        try:
            resp = call_coaching(pos["fen"], pos["opening"], pos["last_move"])
        except Exception as e:
            print(f"  ERROR on {pos['opening']}: {e}", flush=True)
            continue
        elapsed = (time.time() - t0) * 1000
        total_time += elapsed

        valid, total, errors = check_accuracy(resp, pos["fen"])
        acc = valid / total * 100 if total > 0 else 100
        is_clean = len(errors) == 0

        ply_valid += valid
        ply_total += total
        if is_clean:
            ply_clean += 1

        if errors:
            ply_errors.extend(errors)
            all_errors_detail.append({
                "ply": ply, "eco": pos["eco"], "opening": pos["opening"],
                "acc": acc, "errors": errors, "resp": resp[:80]
            })

        status = "OK" if is_clean else f"ERR({errors})"
        print(f"  ply {ply:2d} | {pos['eco']:>4} {pos['opening'][:45]:<45} | "
              f"{acc:5.0f}% ({valid}/{total}) | {elapsed:.0f}ms | {status}", flush=True)

    ply_acc = ply_valid / ply_total * 100 if ply_total > 0 else 100
    ply_clean_pct = ply_clean / len(sample) * 100
    results_by_ply[ply] = {"acc": ply_acc, "clean_pct": ply_clean_pct, "n": len(sample),
                           "valid": ply_valid, "total": ply_total, "errors": ply_errors}
    overall_valid += ply_valid
    overall_total += ply_total
    overall_clean += ply_clean
    overall_n += len(sample)

    print(f"  --- Ply {ply} summary: {ply_acc:.1f}% raw, {ply_clean_pct:.0f}% clean ---\n", flush=True)

# Summary
print(f"\n{'='*80}", flush=True)
print("SUMMARY BY PLY", flush=True)
print(f"{'='*80}", flush=True)
print(f"{'Ply':>4} {'N':>4} {'Raw Acc':>9} {'Clean%':>8}")
print("-" * 30)
for ply in range(1, 11):
    if ply in results_by_ply:
        r = results_by_ply[ply]
        print(f"{ply:>4} {r['n']:>4} {r['acc']:>8.1f}% {r['clean_pct']:>7.0f}%")

overall_acc = overall_valid / overall_total * 100 if overall_total > 0 else 100
overall_clean_pct = overall_clean / overall_n * 100 if overall_n > 0 else 100
print(f"\nOVERALL: {overall_acc:.1f}% raw accuracy, {overall_clean_pct:.0f}% clean")
print(f"Total time: {total_time/1000:.0f}s ({total_time/overall_n:.0f}ms avg)")

if all_errors_detail:
    print(f"\nFAILURES ({len(all_errors_detail)}):")
    for e in all_errors_detail[:15]:
        print(f"  ply {e['ply']} {e['eco']} {e['opening'][:40]}: {e['acc']:.0f}% errors={e['errors']}")
