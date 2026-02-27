#!/usr/bin/env python3
"""Validate opening JSON trees against the Lichess chess-openings dataset."""

import json
import csv
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPENINGS_DIR = ROOT / "ChessCoach" / "Resources" / "Openings"
REFERENCE_DIR = ROOT / "ChessCoach" / "Resources" / "OpeningData"


def load_lichess_openings():
    """Load all Lichess openings into a dict keyed by PGN move sequence."""
    openings = {}  # pgn_moves -> (eco, name)
    for tsv_file in sorted(REFERENCE_DIR.glob("*.tsv")):
        with open(tsv_file, "r") as f:
            reader = csv.reader(f, delimiter="\t")
            header = next(reader)  # skip header
            for row in reader:
                if len(row) >= 3:
                    eco, name, pgn = row[0], row[1], row[2]
                    openings[pgn.strip()] = (eco, name)
    return openings


def san_to_pgn(san_moves):
    """Convert a list of SAN moves to PGN string."""
    parts = []
    for i, san in enumerate(san_moves):
        if i % 2 == 0:
            parts.append(f"{i // 2 + 1}. {san}")
        else:
            parts.append(san)
    return " ".join(parts)


def walk_tree(node, moves_so_far=None):
    """Walk a JSON opening tree, yielding (path_of_san_moves, node_info) for each node."""
    if moves_so_far is None:
        moves_so_far = []

    current_moves = list(moves_so_far)
    if node.get("move"):
        current_moves.append(node["move"]["san"])

    yield current_moves, node

    for child in node.get("children", []):
        yield from walk_tree(child, current_moves)


def find_best_match(pgn, lichess_openings):
    """Find the longest matching prefix in the Lichess dataset."""
    # Try exact match first
    if pgn in lichess_openings:
        return pgn, lichess_openings[pgn]

    # Try progressively shorter prefixes
    parts = pgn.split()
    for end in range(len(parts), 0, -1):
        candidate = " ".join(parts[:end])
        if candidate in lichess_openings:
            return candidate, lichess_openings[candidate]

    return None, None


def validate_opening(json_path, lichess_openings):
    """Validate a single opening JSON file."""
    with open(json_path) as f:
        data = json.load(f)

    print(f"\n{'='*70}")
    print(f"Opening: {data['name']} ({json_path.name})")
    print(f"{'='*70}")

    tree = data["tree"]
    lines_found = 0
    lines_matched = 0
    issues = []
    name_suggestions = {}

    # Collect all leaf paths (complete lines)
    leaves = []
    for moves, node in walk_tree(tree):
        if not node.get("children"):
            leaves.append((moves, node))

    print(f"\nTotal lines (leaf nodes): {len(leaves)}")
    print()

    # Check each leaf line
    for moves, node in leaves:
        lines_found += 1
        pgn = san_to_pgn(moves)
        variation_name = node.get("variationName", "")

        # Find exact or longest prefix match
        match_pgn, match_info = find_best_match(pgn, lichess_openings)

        if match_pgn == pgn:
            lines_matched += 1
            eco, canonical_name = match_info
            status = "EXACT"
        elif match_pgn:
            eco, canonical_name = match_info
            matched_moves = len(match_pgn.split())
            total_parts = len(pgn.split())
            # Count actual moves (not move numbers)
            status = f"PARTIAL (matched {match_pgn})"
            lines_matched += 1
        else:
            status = "NO MATCH"
            canonical_name = None
            eco = None

        # Print line info
        node_id = node.get("id", "?")
        inherited_name = variation_name or node_id.split("/")[-1]
        print(f"  Line: {pgn}")
        if canonical_name:
            print(f"    Lichess: [{eco}] {canonical_name}")
            if variation_name:
                print(f"    Our name: {variation_name}")
            # Store name suggestion for the best matching position
            name_suggestions[node.get("id")] = (eco, canonical_name)
        else:
            print(f"    WARNING: No match in Lichess dataset")
        print(f"    Status: {status}")
        print()

    # Also check intermediate positions (branch points)
    print(f"\n--- Branch point names ---")
    for moves, node in walk_tree(tree):
        if not moves:
            continue
        if node.get("children") and node.get("variationName"):
            pgn = san_to_pgn(moves)
            match_pgn, match_info = find_best_match(pgn, lichess_openings)
            if match_info:
                eco, canonical = match_info
                ours = node["variationName"]
                if ours != canonical.split(": ", 1)[-1] if ": " in canonical else canonical:
                    print(f"  Position: {pgn}")
                    print(f"    Our name: {ours}")
                    print(f"    Lichess:  [{eco}] {canonical}")
                    print()

    print(f"\nSummary: {lines_matched}/{lines_found} lines found in Lichess dataset")
    return lines_found, lines_matched


def main():
    lichess = load_lichess_openings()
    print(f"Loaded {len(lichess)} openings from Lichess dataset")

    total_lines = 0
    total_matched = 0

    for json_file in sorted(OPENINGS_DIR.glob("*.json")):
        found, matched = validate_opening(json_file, lichess)
        total_lines += found
        total_matched += matched

    print(f"\n{'='*70}")
    print(f"OVERALL: {total_matched}/{total_lines} lines matched against Lichess data")
    print(f"{'='*70}")


if __name__ == "__main__":
    main()
