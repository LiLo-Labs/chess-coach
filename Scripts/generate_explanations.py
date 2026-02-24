#!/usr/bin/env python3
"""
Build-time script: generates per-move coaching explanations for opening trees.
Reads a polyglot .bin book, builds trees, sends batched prompts to Claude API,
and outputs JSON files per opening bundled with the app.

Usage:
    python3 generate_explanations.py --book path/to/book.bin --output ChessCoach/Resources/Openings/

Environment:
    ANTHROPIC_API_KEY - Claude API key for generating explanations
"""

import argparse
import json
import os
import struct
import sys
import time
from pathlib import Path

try:
    import chess
    import chess.polyglot
except ImportError:
    print("Error: python-chess is required. Install with: pip install python-chess")
    sys.exit(1)

try:
    import anthropic
except ImportError:
    anthropic = None
    print("Warning: anthropic SDK not installed. Will generate placeholder explanations.")
    print("Install with: pip install anthropic")


# Opening definitions: name, color, starting moves (UCI), difficulty
OPENINGS = [
    {
        "id": "italian",
        "name": "Italian Game",
        "description": "A classic opening that develops pieces quickly toward the center and kingside.",
        "color": "white",
        "difficulty": 1,
        "start_moves": ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"],
    },
    {
        "id": "london",
        "name": "London System",
        "description": "A solid, easy-to-learn system that works against almost any Black response.",
        "color": "white",
        "difficulty": 1,
        "start_moves": ["d2d4", "d7d5", "c1f4"],
    },
    {
        "id": "sicilian",
        "name": "Sicilian Defense",
        "description": "The most popular and aggressive response to 1.e4. Leads to sharp, exciting games.",
        "color": "black",
        "difficulty": 3,
        "start_moves": ["e2e4", "c7c5"],
    },
    {
        "id": "french",
        "name": "French Defense",
        "description": "A solid defense where Black builds a strong pawn structure and counterattacks the center.",
        "color": "black",
        "difficulty": 2,
        "start_moves": ["e2e4", "e7e6"],
    },
    {
        "id": "caro-kann",
        "name": "Caro-Kann Defense",
        "description": "A very solid defense that avoids the cramped positions of the French while keeping good piece activity.",
        "color": "black",
        "difficulty": 2,
        "start_moves": ["e2e4", "c7c6"],
    },
    {
        "id": "queens-gambit",
        "name": "Queen's Gambit",
        "description": "A classical opening where White offers a pawn to gain central control.",
        "color": "white",
        "difficulty": 2,
        "start_moves": ["d2d4", "d7d5", "c2c4"],
    },
    {
        "id": "kings-indian",
        "name": "King's Indian Defense",
        "description": "An aggressive defense where Black lets White build a big center, then counterattacks it.",
        "color": "black",
        "difficulty": 3,
        "start_moves": ["d2d4", "g8f6", "c2c4", "g7g6"],
    },
    {
        "id": "ruy-lopez",
        "name": "Ruy Lopez",
        "description": "One of the oldest and most respected openings. White puts immediate pressure on Black's center.",
        "color": "white",
        "difficulty": 3,
        "start_moves": ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"],
    },
    {
        "id": "scotch",
        "name": "Scotch Game",
        "description": "An aggressive opening where White immediately opens the center for active piece play.",
        "color": "white",
        "difficulty": 2,
        "start_moves": ["e2e4", "e7e5", "g1f3", "b8c6", "d2d4"],
    },
    {
        "id": "pirc",
        "name": "Pirc Defense",
        "description": "A hypermodern defense where Black invites White to build a center, planning to undermine it later.",
        "color": "black",
        "difficulty": 3,
        "start_moves": ["e2e4", "d7d6"],
    },
]


def build_tree_from_book(book_path, start_moves, max_depth=15, max_branch=3, min_weight_frac=0.05):
    """Build an opening tree from a polyglot book."""
    reader = chess.polyglot.open_reader(book_path)
    board = chess.Board()

    # Play starting moves
    for uci in start_moves:
        move = chess.Move.from_uci(uci)
        board.push(move)

    def walk(board, depth):
        if depth >= max_depth:
            return []

        try:
            entries = list(reader.find_all(board))
        except Exception:
            return []

        if not entries:
            return []

        total_weight = sum(e.weight for e in entries)
        if total_weight == 0:
            return []

        min_weight = max(1, int(total_weight * min_weight_frac))
        filtered = [e for e in entries if e.weight >= min_weight]
        filtered.sort(key=lambda e: e.weight, reverse=True)
        filtered = filtered[:max_branch]

        children = []
        for i, entry in enumerate(filtered):
            move = entry.move
            san = board.san(move)
            uci = move.uci()

            board.push(move)
            sub_children = walk(board, depth + 1)
            board.pop()

            node = {
                "move": {
                    "uci": uci,
                    "san": san,
                    "explanation": ""  # filled by Claude
                },
                "children": sub_children,
                "isMainLine": i == 0,
                "weight": entry.weight,
            }
            children.append(node)

        return children

    tree = walk(board, 0)
    reader.close()
    return tree


def count_nodes(tree):
    """Count total nodes in a tree."""
    count = len(tree)
    for node in tree:
        count += count_nodes(node.get("children", []))
    return count


def collect_positions(tree, board, start_moves):
    """Collect all (position_desc, move_san, node_path) tuples for explanation generation."""
    board_copy = chess.Board()
    for uci in start_moves:
        board_copy.push(chess.Move.from_uci(uci))

    positions = []

    def walk(nodes, move_history):
        for node in nodes:
            move = node["move"]
            san = move["san"]
            uci_str = move["uci"]

            pos_desc = " ".join(
                f"{i//2+1}." + (" " if i % 2 == 0 else "") + m
                for i, m in enumerate(move_history + [san])
            )

            positions.append({
                "position": pos_desc,
                "san": san,
                "uci": uci_str,
                "node": node,
            })

            board_copy.push(chess.Move.from_uci(uci_str))
            walk(node.get("children", []), move_history + [san])
            board_copy.pop()

    walk(tree, [board_copy.move_stack[i].uci() if i < len(board_copy.move_stack) else "" for i in range(len(start_moves))])
    return positions


def generate_explanations_claude(positions, opening_name, client):
    """Generate explanations using Claude API in batches."""
    batch_size = 10

    for i in range(0, len(positions), batch_size):
        batch = positions[i:i+batch_size]

        moves_text = "\n".join(
            f"- After {p['position']}: {p['san']}"
            for p in batch
        )

        prompt = f"""For the {opening_name} chess opening, write a 1-2 sentence explanation
for each of these moves, suitable for a beginner chess player (ELO ~800-1200).
Explain WHY the move is played, not just what it does.

Moves to explain:
{moves_text}

Return a JSON array of strings, one explanation per move, in the same order.
Only return the JSON array, no other text."""

        try:
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=2000,
                messages=[{"role": "user", "content": prompt}]
            )

            text = response.content[0].text.strip()
            # Parse JSON from response
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]

            explanations = json.loads(text)

            for j, explanation in enumerate(explanations):
                if j < len(batch):
                    batch[j]["node"]["move"]["explanation"] = explanation

            # Rate limiting
            time.sleep(1)

        except Exception as e:
            print(f"  Warning: Claude API error for batch {i}: {e}")
            for p in batch:
                p["node"]["move"]["explanation"] = f"A key move in the {opening_name}."


def generate_placeholder_explanations(positions, opening_name):
    """Generate simple placeholder explanations when Claude is not available."""
    for p in positions:
        san = p["san"]
        p["node"]["move"]["explanation"] = f"An important move in the {opening_name}."


def assign_node_ids(tree, prefix=""):
    """Assign stable IDs to all nodes in the tree."""
    for i, node in enumerate(tree):
        node_id = f"{prefix}/{node['move']['uci']}" if prefix else node["move"]["uci"]
        node["id"] = node_id
        assign_node_ids(node.get("children", []), node_id)


def main():
    parser = argparse.ArgumentParser(description="Generate opening explanations")
    parser.add_argument("--book", required=True, help="Path to polyglot .bin book")
    parser.add_argument("--output", required=True, help="Output directory for JSON files")
    parser.add_argument("--dry-run", action="store_true", help="Don't call Claude, use placeholders")
    parser.add_argument("--max-depth", type=int, default=15, help="Max tree depth in plies")
    parser.add_argument("--max-branch", type=int, default=3, help="Max branches per node")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)

    # Set up Claude client
    client = None
    if not args.dry_run and anthropic is not None:
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if api_key:
            client = anthropic.Anthropic(api_key=api_key)
        else:
            print("Warning: ANTHROPIC_API_KEY not set, using placeholder explanations")

    for opening in OPENINGS:
        print(f"\nProcessing: {opening['name']}")

        # Build tree
        tree = build_tree_from_book(
            args.book,
            opening["start_moves"],
            max_depth=args.max_depth,
            max_branch=args.max_branch,
        )

        node_count = count_nodes(tree)
        print(f"  Tree nodes: {node_count}")

        if node_count == 0:
            print(f"  Warning: No book entries found for {opening['name']}")
            continue

        # Assign IDs
        assign_node_ids(tree, opening["id"])

        # Generate explanations
        positions = collect_positions(tree, None, opening["start_moves"])
        print(f"  Positions to explain: {len(positions)}")

        if client:
            generate_explanations_claude(positions, opening["name"], client)
        else:
            generate_placeholder_explanations(positions, opening["name"])

        # Build the start moves with explanations (from hardcoded data)
        start_tree = []
        for uci in opening["start_moves"]:
            start_tree.append({
                "move": {"uci": uci, "san": "", "explanation": ""},
                "children": [],
                "isMainLine": True,
                "weight": 65535,
                "id": f"{opening['id']}/{uci}",
            })

        # Nest start moves and attach the explored tree
        root = {
            "id": opening["id"],
            "name": opening["name"],
            "description": opening["description"],
            "color": opening["color"],
            "difficulty": opening["difficulty"],
            "tree": {
                "id": f"{opening['id']}/root",
                "children": tree,
                "isMainLine": True,
                "weight": 0,
            }
        }

        # Write JSON
        output_path = os.path.join(args.output, f"{opening['id']}.json")
        with open(output_path, "w") as f:
            json.dump(root, f, indent=2)

        print(f"  Written to: {output_path}")

    print("\nDone!")


if __name__ == "__main__":
    main()
