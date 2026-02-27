#!/usr/bin/env python3
"""
Generate test positions for LLM experiments from opening tree JSON files.

Reads italian.json and london.json opening trees, walks them using python-chess
to track board state, and generates test positions with book moves, wrong moves,
and contextual metadata for LLM evaluation.

Output: test_positions.json (~50 sampled positions across both openings)
"""

import json
import os
import random
from pathlib import Path

import chess

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent  # chess-coach/
OPENINGS_DIR = REPO_ROOT / "ChessCoach" / "Resources" / "Openings"

OPENING_FILES = [
    OPENINGS_DIR / "italian.json",
    OPENINGS_DIR / "london.json",
]

OUTPUT_PATH = SCRIPT_DIR / "test_positions.json"

TARGET_POSITIONS = 50


# ---------------------------------------------------------------------------
# Board summary helpers
# ---------------------------------------------------------------------------

PIECE_NAMES = {
    chess.PAWN: "Pawn",
    chess.KNIGHT: "Knight",
    chess.BISHOP: "Bishop",
    chess.ROOK: "Rook",
    chess.QUEEN: "Queen",
    chess.KING: "King",
}


def square_name(sq: int) -> str:
    """Return the algebraic name for a square index (e.g. 0 -> 'a1')."""
    return chess.square_name(sq)


def board_summary(board: chess.Board) -> str:
    """
    Produce a human-readable summary of piece placement, e.g.:
    "White: King g1, Queen d1, Rook a1, Rook f1, ... Black: King e8, ..."
    """
    sides = []
    for color, label in [(chess.WHITE, "White"), (chess.BLACK, "Black")]:
        pieces = []
        for piece_type in [chess.KING, chess.QUEEN, chess.ROOK, chess.BISHOP, chess.KNIGHT, chess.PAWN]:
            for sq in board.pieces(piece_type, color):
                pieces.append(f"{PIECE_NAMES[piece_type]} {square_name(sq)}")
        sides.append(f"{label}: {', '.join(pieces)}")
    return " | ".join(sides)


# ---------------------------------------------------------------------------
# Wrong-move selection
# ---------------------------------------------------------------------------

def pick_wrong_move(board: chess.Board, book_move: chess.Move) -> chess.Move | None:
    """
    Pick a legal move that is NOT the book move.  Prefer piece moves over
    pawn moves for more interesting wrong answers, but fall back to anything.
    """
    legal = list(board.legal_moves)
    candidates = [m for m in legal if m != book_move]
    if not candidates:
        return None

    # Prefer non-pawn moves for more plausible wrong answers
    piece_moves = [
        m for m in candidates
        if board.piece_type_at(m.from_square) != chess.PAWN
    ]
    pool = piece_moves if piece_moves else candidates
    return random.choice(pool)


# ---------------------------------------------------------------------------
# Tree walker
# ---------------------------------------------------------------------------

def walk_tree(node: dict, board: chess.Board, opening_meta: dict,
              ply: int, results: list) -> None:
    """
    Recursively walk the opening tree.  For each node that contains a move,
    record the position before/after and metadata.
    """
    move_data = node.get("move")
    if move_data:
        uci_str = move_data["uci"]
        san_str = move_data["san"]
        explanation = move_data.get("explanation", "")

        fen_before = board.fen()
        book_move = chess.Move.from_uci(uci_str)

        # Validate the move is legal on the current board
        if book_move not in board.legal_moves:
            # Some UCI strings (like castling) might need mapping
            # Try parsing SAN as fallback
            try:
                book_move = board.parse_san(san_str)
            except (chess.InvalidMoveError, chess.IllegalMoveError):
                # Skip this node if we can't parse the move at all
                return

        wrong = pick_wrong_move(board, book_move)

        # Push the book move to get fen_after
        board.push(book_move)
        fen_after = board.fen()

        entry = {
            "position_id": node.get("id", f"{opening_meta['opening_id']}/ply{ply}"),
            "opening_name": opening_meta["opening_name"],
            "opening_id": opening_meta["opening_id"],
            "fen_before": fen_before,
            "fen_after": fen_after,
            "book_move_uci": book_move.uci(),
            "book_move_san": san_str,
            "move_explanation": explanation,
            "wrong_move_uci": wrong.uci() if wrong else None,
            "wrong_move_san": (
                chess.Board(fen_before).san(wrong) if wrong else None
            ),
            "ply": ply,
            "is_white_move": not board.turn,  # after push, turn has flipped
            "plan_summary": opening_meta["plan_summary"],
            "strategic_goals": opening_meta["strategic_goals"],
            "pawn_structure": opening_meta["pawn_structure"],
            "piece_targets": opening_meta["piece_targets"],
            "board_summary": board_summary(board),
        }
        results.append(entry)
    else:
        # Root node has no move — nothing to record, just recurse
        pass

    # Recurse into children
    for child in node.get("children", []):
        walk_tree(child, board.copy(), opening_meta, ply + (1 if move_data else 0), results)

    # We do NOT pop the move because we passed board.copy() to children


# ---------------------------------------------------------------------------
# Sampling
# ---------------------------------------------------------------------------

def sample_positions(all_positions: list, target: int) -> list:
    """
    Sample approximately *target* positions from the full set, ensuring
    coverage across both openings and across early / mid / late plies.

    Strategy:
      - Split by opening
      - Within each opening, bucket by ply range (early 1-4, mid 5-8, late 9+)
      - Sample proportionally from each bucket, with a minimum of 2 per bucket
        (if available)
    """
    if len(all_positions) <= target:
        return all_positions

    by_opening: dict[str, list] = {}
    for pos in all_positions:
        by_opening.setdefault(pos["opening_id"], []).append(pos)

    def ply_bucket(ply: int) -> str:
        if ply <= 4:
            return "early"
        elif ply <= 8:
            return "mid"
        else:
            return "late"

    sampled: list = []
    per_opening = max(target // len(by_opening), 1)

    for opening_id, positions in by_opening.items():
        buckets: dict[str, list] = {}
        for p in positions:
            b = ply_bucket(p["ply"])
            buckets.setdefault(b, []).append(p)

        # Guarantee minimum from each bucket
        minimum_per_bucket = 2
        remaining_budget = per_opening

        for bucket_name, bucket_positions in buckets.items():
            take = min(minimum_per_bucket, len(bucket_positions))
            chosen = random.sample(bucket_positions, take)
            sampled.extend(chosen)
            remaining_budget -= take
            # Remove chosen from bucket so we don't double-pick
            for c in chosen:
                bucket_positions.remove(c)

        # Fill remaining budget proportionally from leftovers
        leftover = []
        for bucket_positions in buckets.values():
            leftover.extend(bucket_positions)

        if remaining_budget > 0 and leftover:
            extra = random.sample(leftover, min(remaining_budget, len(leftover)))
            sampled.extend(extra)

    # Final trim if we overshot
    if len(sampled) > target:
        sampled = random.sample(sampled, target)

    # Sort for deterministic output
    sampled.sort(key=lambda p: (p["opening_id"], p["ply"], p["position_id"]))
    return sampled


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    random.seed(42)  # reproducible sampling

    all_positions: list[dict] = []

    for filepath in OPENING_FILES:
        if not filepath.exists():
            print(f"WARNING: Opening file not found, skipping: {filepath}")
            continue

        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)

        opening_meta = {
            "opening_name": data["name"],
            "opening_id": data["id"],
            "plan_summary": data.get("plan", {}).get("summary", ""),
            "strategic_goals": [
                g["description"]
                for g in data.get("plan", {}).get("strategicGoals", [])
            ],
            "pawn_structure": data.get("plan", {}).get("pawnStructureTarget", ""),
            "piece_targets": [
                {
                    "piece": pt["piece"],
                    "ideal_squares": pt["idealSquares"],
                    "reasoning": pt["reasoning"],
                }
                for pt in data.get("plan", {}).get("pieceTargets", [])
            ],
        }

        board = chess.Board()
        tree = data["tree"]
        walk_tree(tree, board, opening_meta, ply=0, results=all_positions)

    print(f"Total positions collected: {len(all_positions)}")

    sampled = sample_positions(all_positions, TARGET_POSITIONS)
    print(f"Sampled positions: {len(sampled)}")

    # Per-opening breakdown
    opening_counts: dict[str, int] = {}
    for p in sampled:
        opening_counts[p["opening_id"]] = opening_counts.get(p["opening_id"], 0) + 1
    for oid, count in sorted(opening_counts.items()):
        print(f"  {oid}: {count}")

    # Ply distribution
    ply_dist: dict[int, int] = {}
    for p in sampled:
        ply_dist[p["ply"]] = ply_dist.get(p["ply"], 0) + 1
    print("Ply distribution:", dict(sorted(ply_dist.items())))

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(sampled, f, indent=2, ensure_ascii=False)

    print(f"Output written to: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
