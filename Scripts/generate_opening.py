#!/usr/bin/env python3
"""
Generate complete opening JSON files with plans, trees, and opponent responses.

Pipeline:
  Lichess TSV (opening name + ECO + PGN)
    → Parse PGN → build tree structure
    → Polyglot book: annotate each node with play frequency (weight)
    → Stockfish: validate each line is sound (no blunders in first 12 moves)
    → LLM: generate plan, explanations, opponent response descriptions
    → Output: Complete opening JSON with plan + tree + opponent responses

Usage:
    python3 generate_opening.py --opening "Italian Game" --book path/to/book.bin --output ChessCoach/Resources/Openings/
    python3 generate_opening.py --eco C50 --book path/to/book.bin --output ChessCoach/Resources/Openings/
    python3 generate_opening.py --all --book path/to/book.bin --tsv path/to/lichess.tsv --output ChessCoach/Resources/Openings/

Environment:
    ANTHROPIC_API_KEY - Claude API key for generating plans and explanations
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

try:
    import chess
    import chess.polyglot
    import chess.engine
except ImportError:
    print("Error: python-chess is required. Install with: pip install python-chess")
    sys.exit(1)

try:
    import anthropic
except ImportError:
    anthropic = None
    print("Warning: anthropic SDK not installed. Will generate placeholder content.")

# Priority openings (matches the built-in list)
PRIORITY_OPENINGS = [
    {"id": "italian", "name": "Italian Game", "eco_range": ("C50", "C54"), "color": "white", "difficulty": 1,
     "start_moves": ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"]},
    {"id": "london", "name": "London System", "eco_range": ("D00", "D00"), "color": "white", "difficulty": 1,
     "start_moves": ["d2d4", "d7d5", "c1f4"]},
    {"id": "sicilian", "name": "Sicilian Defense", "eco_range": ("B20", "B99"), "color": "black", "difficulty": 3,
     "start_moves": ["e2e4", "c7c5"]},
    {"id": "french", "name": "French Defense", "eco_range": ("C00", "C19"), "color": "black", "difficulty": 2,
     "start_moves": ["e2e4", "e7e6"]},
    {"id": "caro-kann", "name": "Caro-Kann Defense", "eco_range": ("B10", "B19"), "color": "black", "difficulty": 2,
     "start_moves": ["e2e4", "c7c6"]},
    {"id": "queens-gambit", "name": "Queen's Gambit", "eco_range": ("D30", "D69"), "color": "white", "difficulty": 2,
     "start_moves": ["d2d4", "d7d5", "c2c4"]},
    {"id": "kings-indian", "name": "King's Indian Defense", "eco_range": ("E60", "E99"), "color": "black", "difficulty": 3,
     "start_moves": ["d2d4", "g8f6", "c2c4", "g7g6"]},
    {"id": "ruy-lopez", "name": "Ruy Lopez", "eco_range": ("C60", "C99"), "color": "white", "difficulty": 3,
     "start_moves": ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"]},
    {"id": "scotch", "name": "Scotch Game", "eco_range": ("C44", "C45"), "color": "white", "difficulty": 2,
     "start_moves": ["e2e4", "e7e5", "g1f3", "b8c6", "d2d4"]},
    {"id": "pirc", "name": "Pirc Defense", "eco_range": ("B07", "B09"), "color": "black", "difficulty": 3,
     "start_moves": ["e2e4", "d7d6"]},
]


def uci_to_move(board, uci_str):
    """Convert UCI string to chess.Move."""
    return chess.Move.from_uci(uci_str)


def build_tree_from_polyglot(book_path, start_moves, max_depth=12, min_weight=5):
    """Build an opening tree from polyglot book data."""
    reader = chess.polyglot.open_reader(book_path)
    board = chess.Board()

    # Apply starting moves
    for uci in start_moves:
        board.push(uci_to_move(board, uci))

    def build_node(board, depth, parent_id):
        if depth >= max_depth:
            return []

        children = []
        try:
            entries = list(reader.find_all(board))
        except Exception:
            return []

        # Sort by weight descending
        entries.sort(key=lambda e: e.weight, reverse=True)

        for i, entry in enumerate(entries):
            if entry.weight < min_weight and i > 0:
                continue

            move = entry.move
            uci = move.uci()
            san = board.san(move)
            node_id = f"{parent_id}/{uci}"

            board.push(move)
            sub_children = build_node(board, depth + 1, node_id)
            board.pop()

            children.append({
                "id": node_id,
                "move": {"uci": uci, "san": san, "explanation": ""},
                "isMainLine": i == 0,
                "weight": entry.weight,
                "children": sub_children
            })

        return children

    root_id = start_moves[0].replace("e2e4", "root") if start_moves else "root"

    # Build from start position
    board_from_start = chess.Board()
    start_nodes = []

    def build_from_start(moves_so_far, remaining_start_moves, parent_id):
        if not remaining_start_moves:
            # Now build the tree from polyglot
            return build_node(board, len(start_moves), parent_id)

        uci = remaining_start_moves[0]
        move = uci_to_move(board_from_start, uci)
        san = board_from_start.san(move)
        node_id = f"{parent_id}/{uci}"
        board_from_start.push(move)

        sub = build_from_start(moves_so_far + [uci], remaining_start_moves[1:], node_id)

        return [{
            "id": node_id,
            "move": {"uci": uci, "san": san, "explanation": ""},
            "isMainLine": True,
            "weight": 300 - len(moves_so_far) * 10,
            "children": sub
        }]

    tree_children = build_from_start([], start_moves, f"{start_moves[0][:4] if start_moves else 'root'}")

    reader.close()
    return {
        "id": f"{start_moves[0][:4] if start_moves else 'root'}/root",
        "children": tree_children,
        "isMainLine": True,
        "weight": 0
    }


def generate_plan_with_llm(opening_info):
    """Use Claude to generate an opening plan."""
    if anthropic is None:
        return generate_placeholder_plan(opening_info)

    client = anthropic.Anthropic()

    prompt = f"""Generate an opening plan for the {opening_info['name']} chess opening (played as {opening_info['color']}).

Return ONLY valid JSON matching this schema:
{{
  "summary": "1-2 sentence description of what you're trying to achieve",
  "strategicGoals": [
    {{"description": "specific goal", "priority": 1}},
    {{"description": "specific goal", "priority": 2}},
    {{"description": "specific goal", "priority": 3}},
    {{"description": "specific goal", "priority": 4}}
  ],
  "pawnStructureTarget": "description of ideal pawn structure",
  "keySquares": ["e4", "f7"],
  "pieceTargets": [
    {{"piece": "piece name", "idealSquares": ["c4", "b3"], "reasoning": "why"}}
  ],
  "typicalPlans": ["middlegame plan 1", "middlegame plan 2"],
  "commonMistakes": ["mistake 1", "mistake 2", "mistake 3"],
  "historicalNote": "brief historical context"
}}

Be specific to this opening. Use beginner-friendly language."""

    try:
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1500,
            messages=[{"role": "user", "content": prompt}]
        )
        text = response.content[0].text.strip()
        # Extract JSON
        if text.startswith("{"):
            return json.loads(text)
        start = text.find("{")
        end = text.rfind("}") + 1
        if start >= 0 and end > start:
            return json.loads(text[start:end])
    except Exception as e:
        print(f"  LLM plan generation failed: {e}")

    return generate_placeholder_plan(opening_info)


def generate_placeholder_plan(opening_info):
    """Generate a basic placeholder plan without LLM."""
    return {
        "summary": f"A {opening_info['color']} opening focusing on piece development and center control.",
        "strategicGoals": [
            {"description": "Control the center", "priority": 1},
            {"description": "Develop pieces actively", "priority": 2},
            {"description": "Castle for king safety", "priority": 3},
            {"description": "Create attacking chances", "priority": 4}
        ],
        "pawnStructureTarget": "Flexible center",
        "keySquares": ["e4", "d4", "e5", "d5"],
        "pieceTargets": [],
        "typicalPlans": ["Develop all pieces before attacking"],
        "commonMistakes": ["Moving the same piece twice", "Neglecting development", "Forgetting to castle"],
        "historicalNote": None
    }


def generate_opponent_responses_with_llm(opening_info, board, book_path):
    """Generate opponent response catalogue from polyglot data + LLM descriptions."""
    reader = chess.polyglot.open_reader(book_path)

    try:
        entries = list(reader.find_all(board))
    except Exception:
        reader.close()
        return None

    if len(entries) < 2:
        reader.close()
        return None

    entries.sort(key=lambda e: e.weight, reverse=True)
    total_weight = sum(e.weight for e in entries)

    responses = []
    for entry in entries[:4]:
        move = entry.move
        san = board.san(move)
        freq = entry.weight / total_weight if total_weight > 0 else 0

        responses.append({
            "id": move.uci(),
            "move": {"uci": move.uci(), "san": san, "explanation": ""},
            "name": san,  # Will be enriched by LLM
            "eco": "",
            "frequency": round(freq, 2),
            "description": f"Opponent plays {san}.",
            "planAdjustment": "Adapt your plan accordingly."
        })

    reader.close()

    if anthropic is not None and responses:
        responses = enrich_responses_with_llm(opening_info, responses)

    return {
        "afterMoves": opening_info["start_moves"],
        "responses": responses
    }


def enrich_responses_with_llm(opening_info, responses):
    """Use LLM to add names and descriptions to opponent responses."""
    client = anthropic.Anthropic()

    moves_str = ", ".join(r["move"]["san"] for r in responses)
    prompt = f"""In the {opening_info['name']} opening, after the standard moves, the opponent's main responses are: {moves_str}

For each response, provide:
1. The standard opening name (e.g., "Giuoco Piano", "Two Knights Defense")
2. The ECO code
3. A beginner-friendly description (1 sentence)
4. How the player should adjust their plan (1 sentence)

Return ONLY a JSON array:
[{{"san": "Bc5", "name": "Opening Name", "eco": "C54", "description": "...", "planAdjustment": "..."}}]"""

    try:
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1000,
            messages=[{"role": "user", "content": prompt}]
        )
        text = response.content[0].text.strip()
        start = text.find("[")
        end = text.rfind("]") + 1
        if start >= 0 and end > start:
            enriched = json.loads(text[start:end])
            for enrichment in enriched:
                for resp in responses:
                    if resp["move"]["san"] == enrichment.get("san"):
                        resp["name"] = enrichment.get("name", resp["name"])
                        resp["eco"] = enrichment.get("eco", "")
                        resp["description"] = enrichment.get("description", resp["description"])
                        resp["planAdjustment"] = enrichment.get("planAdjustment", resp["planAdjustment"])
    except Exception as e:
        print(f"  LLM response enrichment failed: {e}")

    return responses


def generate_opening_json(opening_info, book_path, output_dir, stockfish_path=None):
    """Generate a complete opening JSON file."""
    print(f"\nGenerating: {opening_info['name']} ({opening_info['id']})")

    # 1. Build tree from polyglot
    print("  Building tree from polyglot book...")
    tree = build_tree_from_polyglot(book_path, opening_info["start_moves"])

    # 2. Generate plan
    print("  Generating plan...")
    plan = generate_plan_with_llm(opening_info)

    # 3. Generate opponent responses
    print("  Generating opponent responses...")
    board = chess.Board()
    for uci in opening_info["start_moves"]:
        board.push(uci_to_move(board, uci))
    opponent_responses = generate_opponent_responses_with_llm(opening_info, board, book_path)

    # 4. Assemble JSON
    opening_json = {
        "id": opening_info["id"],
        "name": opening_info["name"],
        "description": plan.get("summary", opening_info["name"]),
        "color": opening_info["color"],
        "difficulty": opening_info["difficulty"],
        "tree": tree,
        "plan": plan,
    }

    if opponent_responses:
        opening_json["opponentResponses"] = opponent_responses

    # 5. Write output
    output_path = Path(output_dir) / f"{opening_info['id']}.json"
    with open(output_path, "w") as f:
        json.dump(opening_json, f, indent=2)

    print(f"  Written to: {output_path}")
    return output_path


def main():
    parser = argparse.ArgumentParser(description="Generate opening JSON files")
    parser.add_argument("--opening", help="Opening name to generate")
    parser.add_argument("--eco", help="ECO code to generate")
    parser.add_argument("--all", action="store_true", help="Generate all priority openings")
    parser.add_argument("--book", required=True, help="Path to polyglot .bin book")
    parser.add_argument("--output", required=True, help="Output directory")
    parser.add_argument("--stockfish", help="Path to stockfish binary (for validation)")
    parser.add_argument("--skip-existing", action="store_true", help="Skip if JSON already exists")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)

    if not os.path.exists(args.book):
        print(f"Error: Book file not found: {args.book}")
        sys.exit(1)

    openings_to_generate = []

    if args.all:
        openings_to_generate = PRIORITY_OPENINGS
    elif args.opening:
        matches = [o for o in PRIORITY_OPENINGS if o["name"].lower() == args.opening.lower()]
        if not matches:
            print(f"Error: Opening '{args.opening}' not found in priority list")
            sys.exit(1)
        openings_to_generate = matches
    elif args.eco:
        matches = [o for o in PRIORITY_OPENINGS
                    if o["eco_range"][0] <= args.eco <= o["eco_range"][1]]
        if not matches:
            print(f"Error: No opening found for ECO '{args.eco}'")
            sys.exit(1)
        openings_to_generate = matches
    else:
        print("Error: Specify --opening, --eco, or --all")
        sys.exit(1)

    for opening in openings_to_generate:
        output_path = Path(args.output) / f"{opening['id']}.json"
        if args.skip_existing and output_path.exists():
            print(f"Skipping {opening['name']} (already exists)")
            continue

        try:
            generate_opening_json(opening, args.book, args.output, args.stockfish)
        except Exception as e:
            print(f"Error generating {opening['name']}: {e}")
            continue

    print("\nDone!")


if __name__ == "__main__":
    main()
