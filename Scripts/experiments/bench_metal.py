"""Benchmark 2-stage reasoning->formatting on Metal (M4 Max).
Tests with engine-style context (what the app would actually feed) vs raw FEN."""
import json, re, time, chess
from llama_cpp import Llama

MODEL_PATH = "/Users/lifson.mark/Development/chess-coach/ChessCoach/Resources/Qwen3-4B-Q4_K_M.gguf"

model = Llama(model_path=MODEL_PATH, n_ctx=4096, n_gpu_layers=-1, verbose=False)

with open("test_positions.json") as f:
    positions = json.load(f)

test_positions = positions[:10]
NOTHINK = {"temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0.0}


def board_description(fen):
    """Generate a human-readable board description from FEN — simulates what the app could compute."""
    board = chess.Board(fen)
    desc_parts = []

    # Material
    white_pieces = []
    black_pieces = []
    for sq, piece in board.piece_map().items():
        name = chess.square_name(sq)
        pname = chess.piece_name(piece.piece_type)
        if piece.color == chess.WHITE:
            white_pieces.append(f"{pname} on {name}")
        else:
            black_pieces.append(f"{pname} on {name}")

    desc_parts.append(f"White pieces: {', '.join(sorted(white_pieces))}")
    desc_parts.append(f"Black pieces: {', '.join(sorted(black_pieces))}")

    # Center control
    center_squares = [chess.E4, chess.D4, chess.E5, chess.D5]
    white_center = []
    black_center = []
    for sq in center_squares:
        p = board.piece_at(sq)
        if p:
            name = chess.square_name(sq)
            if p.color == chess.WHITE:
                white_center.append(f"{chess.piece_name(p.piece_type)} on {name}")
            else:
                black_center.append(f"{chess.piece_name(p.piece_type)} on {name}")
    if white_center:
        desc_parts.append(f"White controls center: {', '.join(white_center)}")
    if black_center:
        desc_parts.append(f"Black controls center: {', '.join(black_center)}")

    # King safety
    for color, label in [(chess.WHITE, "White"), (chess.BLACK, "Black")]:
        king_sq = board.king(color)
        if king_sq is not None:
            kname = chess.square_name(king_sq)
            castling = []
            if color == chess.WHITE:
                if board.has_kingside_castling_rights(chess.WHITE): castling.append("O-O")
                if board.has_queenside_castling_rights(chess.WHITE): castling.append("O-O-O")
            else:
                if board.has_kingside_castling_rights(chess.BLACK): castling.append("O-O")
                if board.has_queenside_castling_rights(chess.BLACK): castling.append("O-O-O")
            castle_str = f", can castle {' '.join(castling)}" if castling else ", no castling rights"
            desc_parts.append(f"{label} king on {kname}{castle_str}")

    return "\n".join(desc_parts)


def strip_thinking(text):
    m = re.search(r"</think>\s*", text)
    return text[m.end():].strip() if m else text.strip()


def check_compliance(text):
    text = strip_thinking(text)
    has_refs = bool(re.search(r"(?i)^REFS\s*:", text, re.MULTILINE))
    has_coaching = bool(re.search(r"(?i)^COACHING\s*:", text, re.MULTILINE))
    return has_refs and has_coaching


def check_accuracy(text, fen):
    """Check if referenced squares/pieces actually exist on the board."""
    text = strip_thinking(text)
    board = chess.Board(fen)
    piece_map = board.piece_map()

    # Extract REFS line
    refs_match = re.search(r"(?i)^REFS:\s*(.+)", text, re.MULTILINE)
    if not refs_match:
        return 0, 0, []

    refs_text = refs_match.group(1)

    # Extract square references (like e4, f7, c5)
    square_refs = re.findall(r'\b([a-h][1-8])\b', refs_text)
    # Extract piece+square refs (like "knight on f3", "bishop c4")
    piece_sq_refs = re.findall(r'(knight|bishop|rook|queen|king|pawn)\s+(?:on\s+)?([a-h][1-8])', refs_text, re.IGNORECASE)

    valid = 0
    total = 0
    errors = []

    for sq_name in square_refs:
        total += 1
        sq = chess.parse_square(sq_name)
        if board.piece_at(sq) is not None:
            valid += 1
        else:
            errors.append(f"no piece on {sq_name}")

    for piece_name, sq_name in piece_sq_refs:
        total += 1
        sq = chess.parse_square(sq_name)
        piece = board.piece_at(sq)
        if piece is not None:
            expected_type = {
                "pawn": chess.PAWN, "knight": chess.KNIGHT, "bishop": chess.BISHOP,
                "rook": chess.ROOK, "queen": chess.QUEEN, "king": chess.KING
            }.get(piece_name.lower())
            if piece.piece_type == expected_type:
                valid += 1
            else:
                actual = chess.piece_name(piece.piece_type)
                errors.append(f"{sq_name} has {actual} not {piece_name}")
        else:
            errors.append(f"no piece on {sq_name} (claimed {piece_name})")

    return valid, total, errors


fmt_refs_coaching = (
    "REFS: <comma-separated key squares or pieces>\n"
    "COACHING: <one or two sentences>"
)

# =====================================================================
# Test configs
# =====================================================================

configs = [
    {
        "label": "A: 2-pass raw FEN",
        "use_board_desc": False,
        "use_context": False,
    },
    {
        "label": "B: 2-pass FEN + board desc",
        "use_board_desc": True,
        "use_context": False,
    },
    {
        "label": "C: 2-pass FEN + board desc + plan",
        "use_board_desc": True,
        "use_context": True,
    },
    {
        "label": "D: 1-pass FEN + board desc + plan",
        "use_board_desc": True,
        "use_context": True,
        "single_pass": True,
    },
]

print(f"Running on Metal (M4 Max) — {len(configs)} configs x {len(test_positions)} positions\n")

for cfg in configs:
    label = cfg["label"]
    ok_count = 0
    accuracy_scores = []
    tok_list = []
    time_list = []
    single = cfg.get("single_pass", False)

    for pos in test_positions:
        fen = pos.get("fen_after", "")
        side = "White" if pos.get("is_white_move") else "Black"
        opening = pos.get("opening_name", "")
        move = pos.get("book_move_san", "")
        plan = pos.get("plan_summary", "")
        goals = pos.get("strategic_goals", "")

        # Build context
        context_parts = [f"Position (FEN): {fen}", f"Side to move: {side}"]
        if cfg.get("use_board_desc"):
            context_parts.append(f"\nBoard:\n{board_description(fen)}")
        if cfg.get("use_context"):
            if opening:
                context_parts.append(f"Opening: {opening}")
            if move:
                context_parts.append(f"Last move played: {move}")
            if plan:
                context_parts.append(f"Plan: {plan}")
            if goals:
                context_parts.append(f"Goals: {goals}")

        context = "\n".join(context_parts)
        t0 = time.time()

        if single:
            out = model.create_chat_completion(
                messages=[
                    {"role": "system", "content": "You are a chess coach. /no_think"},
                    {"role": "user", "content": (
                        f"{context}\n\n"
                        f"Give a brief coaching insight. Reference specific pieces and squares that exist on the board.\n\n"
                        f"Respond with ONLY:\n{fmt_refs_coaching}"
                    )},
                ],
                max_tokens=120, **NOTHINK,
            )
            formatted = strip_thinking(out["choices"][0]["message"]["content"] or "")
            total_toks = out["usage"]["completion_tokens"]
        else:
            # Pass 1: reasoning
            out1 = model.create_chat_completion(
                messages=[
                    {"role": "system", "content": "You are a chess coach. /no_think"},
                    {"role": "user", "content": (
                        f"{context}\n\n"
                        "In one sentence, what should the student focus on? "
                        "Reference ONLY pieces and squares that are actually on the board."
                    )},
                ],
                max_tokens=60, **NOTHINK,
            )
            analysis = strip_thinking(out1["choices"][0]["message"]["content"] or "")
            toks1 = out1["usage"]["completion_tokens"]

            # Pass 2: formatting
            out2 = model.create_chat_completion(
                messages=[
                    {"role": "system", "content": "You are a text formatter. /no_think"},
                    {"role": "user", "content": (
                        f"Rewrite this chess insight into exactly this format:\n"
                        f"{fmt_refs_coaching}\n\n"
                        f"Insight: {analysis}\n\n"
                        f"Output ONLY those two lines."
                    )},
                ],
                max_tokens=80, **NOTHINK,
            )
            formatted = strip_thinking(out2["choices"][0]["message"]["content"] or "")
            total_toks = toks1 + out2["usage"]["completion_tokens"]

        elapsed = (time.time() - t0) * 1000

        ok = check_compliance(formatted)
        valid, total_refs, errors = check_accuracy(formatted, fen)
        acc = valid / total_refs * 100 if total_refs > 0 else 0

        if ok: ok_count += 1
        accuracy_scores.append(acc)
        tok_list.append(total_toks)
        time_list.append(elapsed)

        status = "OK" if ok else "FAIL"
        print(f"  [{label}] {status} | {total_toks} tok | {elapsed:.0f}ms | acc {valid}/{total_refs} ({acc:.0f}%)")
        print(f"    {formatted[:140]}")
        if errors:
            print(f"    ERRORS: {errors[:3]}")

    n = len(test_positions)
    avg_acc = sum(accuracy_scores) / n
    avg_tok = sum(tok_list) / n
    avg_ms = sum(time_list) / n
    print(f"\n  === {label}: {ok_count}/{n} format | {avg_acc:.0f}% accuracy | avg {avg_tok:.0f} tok | avg {avg_ms:.0f}ms ===\n")
