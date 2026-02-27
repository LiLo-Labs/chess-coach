"""Mini ECO test: 20 diverse positions, guard instruction strategy.
Prints after EVERY inference call. Focuses on verifying accuracy across varied openings.
"""
import csv, re, time, chess, random, os, sys
sys.stdout.reconfigure(line_buffering=True)
from llama_cpp import Llama

MODEL_PATH = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Qwen3-4B-Q4_K_M.gguf"
TSV_DIR = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/OpeningData"

print("Loading model...", flush=True)
model = Llama(model_path=MODEL_PATH, n_ctx=4096, n_gpu_layers=-1, verbose=False)
print("Model loaded.\n", flush=True)

NOTHINK = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}


def board_description(fen):
    board = chess.Board(fen)
    wp, bp = [], []
    for sq, piece in board.piece_map().items():
        name = chess.square_name(sq)
        pname = chess.piece_name(piece.piece_type)
        (wp if piece.color == chess.WHITE else bp).append(f"{pname} on {name}")
    parts = [f"White: {', '.join(sorted(wp))}", f"Black: {', '.join(sorted(bp))}"]
    for color, label in [(chess.WHITE, "White"), (chess.BLACK, "Black")]:
        ksq = board.king(color)
        if ksq is not None:
            c = []
            if board.has_kingside_castling_rights(color): c.append("O-O")
            if board.has_queenside_castling_rights(color): c.append("O-O-O")
            cs = f", can castle {' '.join(c)}" if c else ""
            parts.append(f"{label} king on {chess.square_name(ksq)}{cs}")
    return "\n".join(parts)


def strip_think(t):
    m = re.search(r"</think>\s*", t)
    return t[m.end():].strip() if m else t.strip()


def check_refs(text, fen):
    text = strip_think(text)
    board = chess.Board(fen)
    m = re.search(r"(?i)^REFS:\s*(.+)", text, re.MULTILINE)
    if not m: return 0, 0, []
    sqs = re.findall(r'\b([a-h][1-8])\b', m.group(1))
    v, t, errs = 0, 0, []
    for s in sqs:
        t += 1
        if board.piece_at(chess.parse_square(s)) is not None: v += 1
        else: errs.append(s)
    return v, t, errs


# Load diverse positions
print("Loading ECO positions...", flush=True)
all_positions = []
for fname in sorted(os.listdir(TSV_DIR)):
    if not fname.endswith(".tsv"): continue
    with open(os.path.join(TSV_DIR, fname), newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            pgn = row.get("pgn", "")
            if not pgn: continue
            board = chess.Board()
            tokens = pgn.split()
            ply = 0
            last_san = ""
            for token in tokens:
                if re.match(r'^\d+\.', token): continue
                if token in ("1-0", "0-1", "1/2-1/2", "*"): continue
                try:
                    move = board.parse_san(token)
                    board.push(move)
                    ply += 1
                    last_san = token
                except: break
            if ply >= 1:
                all_positions.append({
                    "fen": board.fen(), "ply": ply,
                    "eco": row.get("eco", ""), "opening": row.get("name", ""),
                    "last_move": last_san
                })

print(f"Total: {len(all_positions)} positions", flush=True)

# Sample 20: 2 per ply from 1-10
random.seed(42)
from collections import defaultdict
by_ply = defaultdict(list)
for p in all_positions:
    if p["ply"] <= 10:
        by_ply[p["ply"]].append(p)

test_set = []
for ply in range(1, 11):
    pool = by_ply[ply]
    test_set.extend(random.sample(pool, min(2, len(pool))))

print(f"Testing {len(test_set)} positions\n", flush=True)

# Test
valid_total = 0
refs_total = 0
clean = 0
failures = []

for i, pos in enumerate(test_set):
    fen = pos["fen"]
    side = "White" if chess.Board(fen).turn == chess.WHITE else "Black"
    bd = board_description(fen)

    t0 = time.time()
    out = model.create_chat_completion(
        messages=[
            {"role": "system", "content": "You are a chess coach. /no_think"},
            {"role": "user", "content": (
                f"Position (FEN): {fen}\nSide to move: {side}\n\nBoard:\n{bd}\n\n"
                f"Opening: {pos['opening']}\nLast move: {pos['last_move']}\n\n"
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
    resp = strip_think(out["choices"][0]["message"]["content"] or "")
    ms = (time.time() - t0) * 1000

    v, t, errs = check_refs(resp, fen)
    acc = v / t * 100 if t > 0 else 100
    ok = len(errs) == 0
    valid_total += v
    refs_total += t
    if ok: clean += 1
    else: failures.append((pos, errs, resp[:80]))

    status = "CLEAN" if ok else f"ERR {errs}"
    print(f"{i+1:2d}. ply {pos['ply']:2d} | {pos['eco']:>4} {pos['opening'][:40]:<40} | "
          f"{acc:5.0f}% ({v}/{t}) {ms:5.0f}ms | {status}", flush=True)

# Summary
print(f"\n{'='*70}", flush=True)
overall = valid_total / refs_total * 100 if refs_total > 0 else 100
print(f"OVERALL: {overall:.1f}% raw ({valid_total}/{refs_total}), "
      f"{clean}/{len(test_set)} clean ({clean/len(test_set)*100:.0f}%)", flush=True)

if failures:
    print(f"\nFailed positions ({len(failures)}):", flush=True)
    for pos, errs, resp in failures:
        print(f"  {pos['eco']} {pos['opening'][:40]} ply={pos['ply']}: {errs}", flush=True)
        print(f"    {resp}", flush=True)

print(f"\nWith post-validation: 100% accuracy (remove {refs_total - valid_total} bad refs)", flush=True)
