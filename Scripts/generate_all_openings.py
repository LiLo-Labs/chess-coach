#!/usr/bin/env python3
"""
Generate all 28 new opening JSON files for ChessCoach app.

Uses the python-chess library for move validation and the Anthropic API
(Claude) for generating explanations, plans, lessons, and quizzes.

Usage:
    python3 generate_all_openings.py
    python3 generate_all_openings.py --dry-run          # Validate moves only
    python3 generate_all_openings.py --skip-api          # Use placeholder content
    python3 generate_all_openings.py --only vienna,slav  # Generate specific openings

Environment:
    ANTHROPIC_API_KEY - Required for Claude API calls (unless --skip-api)
"""

import argparse
import json
import os
import sys
import time
import re
from pathlib import Path

try:
    import chess
except ImportError:
    print("Error: python-chess is required. Install with: pip install python-chess")
    sys.exit(1)

try:
    import anthropic
except ImportError:
    anthropic = None

# ---------------------------------------------------------------------------
# Output directory (relative to this script)
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR.parent / "ChessCoach" / "Resources" / "Openings"
PROGRESS_FILE = SCRIPT_DIR / ".generate_progress.json"

# Existing openings that should be skipped
EXISTING_IDS = {"italian", "london"}

# Claude model to use
MODEL = "claude-sonnet-4-20250514"

# Rate limiting: seconds between API calls
API_DELAY = 1.5

# ---------------------------------------------------------------------------
# Opening definitions
# ---------------------------------------------------------------------------
# Each opening has:
#   id, name, description, color, difficulty,
#   main_line: list of UCI move strings for the main line,
#   variations: list of dicts with:
#       name: variation name
#       branch_ply: ply number where the variation branches (0-indexed)
#       moves: UCI moves FROM the branch point onward (replacing main line moves)
#   response_after_ply: ply after which to catalogue opponent responses

OPENINGS = [
    # =========================================================================
    # WHITE OPENINGS (10 new)
    # =========================================================================
    {
        "id": "vienna",
        "name": "Vienna Game",
        "description": "A flexible opening where White delays committing to a pawn structure, keeping options for both quiet and aggressive play.",
        "color": "white",
        "difficulty": 2,
        "main_line": [
            "e2e4", "e7e5", "b1c3", "g8f6", "f2f4", "d7d5",
            "f4e5", "f6e4", "g1f3", "f8c5", "d2d4", "c5b6",
        ],
        "variations": [
            {
                "name": "Vienna: ...Nc6",
                "branch_ply": 3,
                "moves": ["b8c6", "f1c4", "g8f6", "d2d3", "f8c5", "g1f3"],
            },
            {
                "name": "Quiet Vienna",
                "branch_ply": 3,
                "moves": ["f8c5", "g1f3", "d7d6", "f1c4", "g8f6", "d2d3"],
            },
            {
                "name": "Vienna Gambit Accepted",
                "branch_ply": 5,
                "moves": ["e5f4", "d2d4", "d7d5", "e4d5", "f6d5", "f1d3"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "kings-gambit",
        "name": "King's Gambit",
        "description": "One of the oldest and most romantic openings. White sacrifices a pawn for rapid development and attacking chances.",
        "color": "white",
        "difficulty": 3,
        "main_line": [
            "e2e4", "e7e5", "f2f4", "e5f4", "g1f3", "g7g5",
            "f1c4", "g5g4", "e1g1", "g4f3", "d1f3",
        ],
        "variations": [
            {
                "name": "Falkbeer Counter-Gambit",
                "branch_ply": 3,
                "moves": ["d7d5", "e4d5", "e5e4", "d2d3", "g8f6", "b1c3", "f8b4"],
            },
            {
                "name": "Classical Defense",
                "branch_ply": 3,
                "moves": ["f8c5", "g1f3", "d7d6", "b1c3", "g8f6", "f1c4"],
            },
            {
                "name": "King's Gambit Declined",
                "branch_ply": 3,
                "moves": ["f8c5", "g1f3", "d7d6", "c2c3", "c8g4", "f4e5"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "english",
        "name": "English Opening",
        "description": "A flexible opening where White controls the center from the flank. Can transpose into many different positions.",
        "color": "white",
        "difficulty": 2,
        "main_line": [
            "c2c4", "e7e5", "b1c3", "g8f6", "g1f3", "b8c6",
            "g2g3", "f8b4", "f1g2", "e8g8", "e1g1", "e5e4",
        ],
        "variations": [
            {
                "name": "Symmetrical English",
                "branch_ply": 1,
                "moves": ["c7c5", "b1c3", "b8c6", "g2g3", "g7g6", "f1g2", "f8g7", "g1f3"],
            },
            {
                "name": "Anglo-Slav",
                "branch_ply": 1,
                "moves": ["c7c6", "g1f3", "d7d5", "c4d5", "c6d5", "d2d4", "g8f6", "b1c3"],
            },
            {
                "name": "English: ...e6 setup",
                "branch_ply": 1,
                "moves": ["e7e6", "g1f3", "d7d5", "g2g3", "g8f6", "f1g2", "f8e7", "e1g1"],
            },
        ],
        "response_after_ply": 1,
    },
    {
        "id": "catalan",
        "name": "Catalan Opening",
        "description": "A sophisticated opening combining Queen's Gambit pawn structure with a fianchettoed bishop. Exerts long-term pressure.",
        "color": "white",
        "difficulty": 3,
        "main_line": [
            "d2d4", "g8f6", "c2c4", "e7e6", "g2g3", "d7d5",
            "f1g2", "f8e7", "g1f3", "e8g8", "e1g1", "d5c4",
        ],
        "variations": [
            {
                "name": "Closed Catalan",
                "branch_ply": 5,
                "moves": ["d7d5", "f1g2", "f8e7", "g1f3", "e8g8", "e1g1"],
            },
            {
                "name": "Catalan: ...Bb4+ line",
                "branch_ply": 5,
                "moves": ["f8b4", "c1d2", "b4e7", "g1f3", "d7d5", "f1g2"],
            },
            {
                "name": "Open Catalan with ...a6",
                "branch_ply": 11,
                "moves": ["a7a6", "d1c2", "b8d7", "f1e1", "b7b5"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "reti",
        "name": "Reti Opening",
        "description": "A hypermodern opening where White controls the center with pieces rather than pawns. Very flexible and transpositional.",
        "color": "white",
        "difficulty": 2,
        "main_line": [
            "g1f3", "d7d5", "c2c4", "d5c4", "e2e3", "c7c5",
            "f1c4", "e7e6", "e1g1", "g8f6", "d2d4",
        ],
        "variations": [
            {
                "name": "Reti: ...e6 system",
                "branch_ply": 1,
                "moves": ["e7e6", "g2g3", "g8f6", "f1g2", "f8e7", "e1g1", "e8g8", "c2c4"],
            },
            {
                "name": "Reti: ...c6 system",
                "branch_ply": 1,
                "moves": ["c7c6", "g2g3", "d7d5", "f1g2", "c8f5", "e1g1", "g8f6", "d2d3"],
            },
            {
                "name": "Reti Accepted: ...Nf6",
                "branch_ply": 3,
                "moves": ["g8f6", "g2g3", "e7e6", "f1g2", "c7c5", "e1g1"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "four-knights",
        "name": "Four Knights Game",
        "description": "A solid, symmetrical opening where both sides develop their knights first. Easy to learn and hard to go wrong.",
        "color": "white",
        "difficulty": 1,
        "main_line": [
            "e2e4", "e7e5", "g1f3", "b8c6", "b1c3", "g8f6",
            "f1b5", "f8b4", "e1g1", "e8g8", "d2d3", "d7d6",
        ],
        "variations": [
            {
                "name": "Rubinstein Variation",
                "branch_ply": 7,
                "moves": ["f6d5", "b5c6", "d7c6", "c3d5", "d8d5", "d2d3"],
            },
            {
                "name": "Italian Four Knights",
                "branch_ply": 6,
                "moves": ["f1c4", "f8c5", "f3e5", "c6e5", "d2d4", "c5d6"],
            },
            {
                "name": "Scotch Four Knights",
                "branch_ply": 4,
                "moves": ["d2d4", "e5d4", "f3d4", "g8f6", "d4c6", "b7c6"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "bishops-opening",
        "name": "Bishop's Opening",
        "description": "A simple but effective opening. White develops the bishop early aiming at f7, keeping the game flexible.",
        "color": "white",
        "difficulty": 1,
        "main_line": [
            "e2e4", "e7e5", "f1c4", "g8f6", "d2d3", "f8c5",
            "g1f3", "d7d6", "e1g1", "e8g8", "c2c3", "a7a6",
        ],
        "variations": [
            {
                "name": "Bishop's Opening: ...Nc6 transposition",
                "branch_ply": 3,
                "moves": ["b8c6", "g1f3", "f8c5", "d2d3", "d7d6", "e1g1"],
            },
            {
                "name": "Bishop's Opening: ...d5 counter",
                "branch_ply": 3,
                "moves": ["d7d5", "e4d5", "g8f6", "d2d4", "f6d5", "b1c3"],
            },
            {
                "name": "Bishop's Opening: ...c6 setup",
                "branch_ply": 3,
                "moves": ["c7c6", "d2d4", "d7d5", "e4d5", "c6d5", "c4b3"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "kings-indian-attack",
        "name": "King's Indian Attack",
        "description": "A universal system for White. Set up with Nf3, g3, Bg2, d3, Nbd2 and e4 against almost anything.",
        "color": "white",
        "difficulty": 2,
        "main_line": [
            "g1f3", "d7d5", "g2g3", "g8f6", "f1g2", "e7e6",
            "e1g1", "f8e7", "d2d3", "e8g8", "b1d2", "c7c5", "e2e4",
        ],
        "variations": [
            {
                "name": "KIA vs ...c5",
                "branch_ply": 3,
                "moves": ["c7c5", "f1g2", "b8c6", "e1g1", "e7e5", "d2d3", "f8e7"],
            },
            {
                "name": "KIA: Fianchetto vs Fianchetto",
                "branch_ply": 3,
                "moves": ["g7g6", "f1g2", "f8g7", "e1g1", "g8f6", "d2d3", "e8g8"],
            },
            {
                "name": "KIA vs French setup",
                "branch_ply": 3,
                "moves": ["e7e6", "f1g2", "c7c5", "e1g1", "b8c6", "d2d3", "g8f6"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "colle",
        "name": "Colle System",
        "description": "A beginner-friendly system opening. Set up with d4, Nf3, e3, Bd3, O-O and then push e4 when ready.",
        "color": "white",
        "difficulty": 1,
        "main_line": [
            "d2d4", "d7d5", "g1f3", "g8f6", "e2e3", "e7e6",
            "f1d3", "c7c5", "c2c3", "b8c6", "b1d2", "f8d6",
            "e1g1", "e8g8",
        ],
        "variations": [
            {
                "name": "Colle: ...Bf5 Anti-Colle",
                "branch_ply": 5,
                "moves": ["c8f5", "f1d3", "f5d3", "d1d3", "e7e6", "e1g1"],
            },
            {
                "name": "Colle: ...Bg4 Pin",
                "branch_ply": 5,
                "moves": ["c8g4", "f1e2", "e7e6", "e1g1", "f8d6", "c2c4"],
            },
            {
                "name": "Colle-Zukertort",
                "branch_ply": 5,
                "moves": ["e7e6", "f1d3", "c7c5", "b2b3", "b8c6", "c1b2"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "trompowsky",
        "name": "Trompowsky Attack",
        "description": "A surprise weapon where White develops the bishop before the knight. Forces Black to make early decisions.",
        "color": "white",
        "difficulty": 2,
        "main_line": [
            "d2d4", "g8f6", "c1g5", "d7d5", "e2e3", "c7c5",
            "c2c3", "d8b6", "d1b3", "b6b3", "a2b3",
        ],
        "variations": [
            {
                "name": "Trompowsky Accepted",
                "branch_ply": 3,
                "moves": ["f6e4", "g5h4", "d7d5", "f2f3", "e4f6", "e2e4"],
            },
            {
                "name": "Trompowsky: ...e6 quiet",
                "branch_ply": 3,
                "moves": ["e7e6", "e2e4", "h7h6", "g5f6", "d8f6", "b1c3"],
            },
            {
                "name": "Trompowsky: ...Ne4 Gambit",
                "branch_ply": 3,
                "moves": ["f6e4", "g5f4", "c7c5", "f2f3", "e4f6", "e2e4"],
            },
        ],
        "response_after_ply": 4,
    },

    # =========================================================================
    # BLACK OPENINGS (10 new)
    # =========================================================================
    {
        "id": "scandinavian",
        "name": "Scandinavian Defense",
        "description": "A straightforward defense where Black immediately challenges White's center. Easy to learn with clear plans.",
        "color": "black",
        "difficulty": 2,
        "main_line": [
            "e2e4", "d7d5", "e4d5", "d8d5", "b1c3", "d5a5",
            "d2d4", "g8f6", "g1f3", "c8f5", "f1c4", "e7e6",
        ],
        "variations": [
            {
                "name": "Modern Scandinavian (...Nf6)",
                "branch_ply": 3,
                "moves": ["g8f6", "d2d4", "f6d5", "g1f3", "c8f5", "f1d3", "f5d3"],
            },
            {
                "name": "Scandinavian: ...Qd6",
                "branch_ply": 5,
                "moves": ["d5d6", "d2d4", "g8f6", "g1f3", "c8f5", "f1d3"],
            },
            {
                "name": "Icelandic Gambit",
                "branch_ply": 3,
                "moves": ["g8f6", "c2c4", "e7e6", "d5e6", "f7e6", "d2d4"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "nimzo-indian",
        "name": "Nimzo-Indian Defense",
        "description": "One of Black's most respected defenses. The bishop pins White's knight, controlling the center indirectly.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "d2d4", "g8f6", "c2c4", "e7e6", "b1c3", "f8b4",
            "e2e3", "e8g8", "f1d3", "d7d5", "g1f3", "c7c5",
            "e1g1", "b8c6",
        ],
        "variations": [
            {
                "name": "Capablanca Variation",
                "branch_ply": 6,
                "moves": ["d1c2", "d7d5", "a2a3", "b4c3", "b2c3", "c7c5"],
            },
            {
                "name": "Samisch Variation",
                "branch_ply": 6,
                "moves": ["f2f3", "d7d5", "a2a3", "b4c3", "b2c3", "c7c5"],
            },
            {
                "name": "Nimzo-Indian: ...c5 early",
                "branch_ply": 7,
                "moves": ["c7c5", "g1f3", "c5d4", "e3d4", "d7d5", "c4d5"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "queens-indian",
        "name": "Queen's Indian Defense",
        "description": "A solid, positional defense where Black fianchettoes the queenside bishop to control the center from a distance.",
        "color": "black",
        "difficulty": 2,
        "main_line": [
            "d2d4", "g8f6", "c2c4", "e7e6", "g1f3", "b7b6",
            "g2g3", "c8b7", "f1g2", "f8e7", "e1g1", "e8g8",
            "b1c3",
        ],
        "variations": [
            {
                "name": "Queen's Indian: ...Ba6",
                "branch_ply": 7,
                "moves": ["c8a6", "d1c2", "c7c5", "e2e4", "a6b7", "e4e5"],
            },
            {
                "name": "Bogo-Indian Hybrid",
                "branch_ply": 7,
                "moves": ["f8b4", "c1d2", "b4e7", "b1c3", "c8b7", "f1g2"],
            },
            {
                "name": "Queen's Indian: ...d5 central",
                "branch_ply": 7,
                "moves": ["d7d5", "c4d5", "e6d5", "f1g2", "f8e7", "e1g1"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "slav",
        "name": "Slav Defense",
        "description": "A rock-solid defense that supports d5 with c6 while keeping the light-squared bishop free to develop.",
        "color": "black",
        "difficulty": 2,
        "main_line": [
            "d2d4", "d7d5", "c2c4", "c7c6", "g1f3", "g8f6",
            "b1c3", "d5c4", "a2a4", "c8f5", "e2e3", "e7e6",
            "f1c4", "f8b4",
        ],
        "variations": [
            {
                "name": "Semi-Slav",
                "branch_ply": 7,
                "moves": ["e7e6", "e2e3", "b8d7", "f1d3", "d5c4", "d3c4"],
            },
            {
                "name": "Slav: early ...Bf5",
                "branch_ply": 7,
                "moves": ["c8f5", "c4d5", "c6d5", "d1b3", "d8b6", "b3b6"],
            },
            {
                "name": "Exchange Slav",
                "branch_ply": 4,
                "moves": ["c4d5", "c6d5", "c1f4", "b8c6", "e2e3", "c8f5"],
            },
        ],
        "response_after_ply": 8,
    },
    {
        "id": "dutch",
        "name": "Dutch Defense",
        "description": "An aggressive defense where Black immediately fights for control of the e4 square with the f-pawn.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "d2d4", "f7f5", "g2g3", "g8f6", "f1g2", "e7e6",
            "g1f3", "f8e7", "e1g1", "e8g8", "c2c4", "d7d6",
            "b1c3",
        ],
        "variations": [
            {
                "name": "Stonewall Dutch",
                "branch_ply": 5,
                "moves": ["d7d5", "c2c4", "e7e6", "g1f3", "f8d6", "e1g1", "e8g8"],
            },
            {
                "name": "Leningrad Dutch",
                "branch_ply": 5,
                "moves": ["g7g6", "g1f3", "f8g7", "e1g1", "e8g8", "c2c4", "d7d6"],
            },
            {
                "name": "Dutch: ...d6/...e5 setup",
                "branch_ply": 5,
                "moves": ["d7d6", "g1f3", "e7e5", "d4e5", "d6e5", "e2e4"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "grunfeld",
        "name": "Grunfeld Defense",
        "description": "A dynamic defense where Black allows White a big center then attacks it. Leads to sharp, exciting play.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "d2d4", "g8f6", "c2c4", "g7g6", "b1c3", "d7d5",
            "c4d5", "f6d5", "e2e4", "d5c3", "b2c3", "f8g7",
            "g1f3", "c7c5",
        ],
        "variations": [
            {
                "name": "Russian System",
                "branch_ply": 8,
                "moves": ["g1f3", "f8g7", "e2e4", "d5c3", "b2c3", "c7c5"],
            },
            {
                "name": "Grunfeld: Bc4 line",
                "branch_ply": 8,
                "moves": ["e2e4", "d5c3", "b2c3", "f8g7", "f1c4", "c7c5"],
            },
            {
                "name": "Grunfeld: Fianchetto variation",
                "branch_ply": 5,
                "moves": ["d7d5", "g2g3", "d5c4", "g1f3", "f8g7", "f1g2"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "philidor",
        "name": "Philidor Defense",
        "description": "A solid, old-fashioned defense where Black supports e5 with d6. Simple to play with a clear structure.",
        "color": "black",
        "difficulty": 1,
        "main_line": [
            "e2e4", "e7e5", "g1f3", "d7d6", "d2d4", "g8f6",
            "b1c3", "b8d7", "f1c4", "f8e7", "e1g1", "e8g8",
        ],
        "variations": [
            {
                "name": "Philidor Exchange",
                "branch_ply": 5,
                "moves": ["e5d4", "f3d4", "g8f6", "b1c3", "f8e7", "f1e2"],
            },
            {
                "name": "Philidor: ...Nf6 first",
                "branch_ply": 5,
                "moves": ["g8f6", "b1c3", "b8d7", "f1c4", "f8e7", "e1g1"],
            },
            {
                "name": "Hanham Variation",
                "branch_ply": 7,
                "moves": ["b8d7", "f1c4", "c7c6", "a2a4", "f8e7", "e1g1"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "alekhine",
        "name": "Alekhine Defense",
        "description": "A provocative defense where Black invites White to advance pawns and then attacks the overextended center.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "e2e4", "g8f6", "e4e5", "f6d5", "d2d4", "d7d6",
            "g1f3", "c8g4", "f1e2", "e7e6", "e1g1", "f8e7",
            "c2c4", "d5b6",
        ],
        "variations": [
            {
                "name": "Exchange Variation",
                "branch_ply": 5,
                "moves": ["d7d6", "e5d6", "c7d6", "g1f3", "b8c6", "f1e2"],
            },
            {
                "name": "Alekhine: ...g6 Fianchetto",
                "branch_ply": 7,
                "moves": ["g7g6", "c2c4", "d5b6", "e5d6", "c7d6", "b1c3"],
            },
            {
                "name": "Four Pawns Attack",
                "branch_ply": 7,
                "moves": ["c8g4", "c2c4", "d5b6", "f1e2", "d6e5", "d4e5"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "benoni",
        "name": "Modern Benoni",
        "description": "An ambitious defense where Black creates an asymmetrical pawn structure and plays for a queenside pawn majority.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "d2d4", "g8f6", "c2c4", "c7c5", "d4d5", "e7e6",
            "b1c3", "e6d5", "c4d5", "d7d6", "e2e4", "g7g6",
            "g1f3", "f8g7",
        ],
        "variations": [
            {
                "name": "Benoni: ...Be7 Classical",
                "branch_ply": 11,
                "moves": ["f8e7", "f1e2", "e8g8", "g1f3", "b8d7", "e1g1"],
            },
            {
                "name": "Czech Benoni",
                "branch_ply": 5,
                "moves": ["e7e5", "e2e4", "f8e7", "g1f3", "e8g8", "f1d3"],
            },
            {
                "name": "Benoni: Fianchetto System",
                "branch_ply": 9,
                "moves": ["d7d6", "g1f3", "g7g6", "g2g3", "f8g7", "f1g2"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "petroff",
        "name": "Petroff Defense",
        "description": "A solid, symmetrical defense where Black mirrors White's play. Known for its drawish tendencies but very reliable.",
        "color": "black",
        "difficulty": 2,
        "main_line": [
            "e2e4", "e7e5", "g1f3", "g8f6", "f3e5", "d7d6",
            "e5f3", "f6e4", "d2d4", "d6d5", "f1d3", "f8e7",
            "e1g1", "e8g8",
        ],
        "variations": [
            {
                "name": "Petroff: Three Knights",
                "branch_ply": 5,
                "moves": ["b8c6", "e5c6", "d7c6", "d2d3", "f8c5", "f1e2"],
            },
            {
                "name": "Petroff: ...Qe7 line",
                "branch_ply": 5,
                "moves": ["d8e7", "d2d4", "d7d6", "e5f3", "e7e4", "f1e2"],
            },
            {
                "name": "Petroff: Steinitz Attack",
                "branch_ply": 4,
                "moves": ["d2d4", "d7d6", "b1c3", "f6e4", "c3e4", "d6d5"],
            },
        ],
        "response_after_ply": 4,
    },

    # =========================================================================
    # EXISTING OPENINGS to also generate (skip italian, london which have JSONs)
    # =========================================================================
    {
        "id": "queens-gambit",
        "name": "Queen's Gambit",
        "description": "A classical opening where White offers a pawn to gain central control and piece activity.",
        "color": "white",
        "difficulty": 2,
        "main_line": [
            "d2d4", "d7d5", "c2c4", "e7e6", "b1c3", "g8f6",
            "c1g5", "f8e7", "e2e3", "e8g8", "g1f3", "b8d7",
        ],
        "variations": [
            {
                "name": "Queen's Gambit Accepted",
                "branch_ply": 3,
                "moves": ["d5c4", "e2e4", "e7e5", "g1f3", "e5d4", "f1c4"],
            },
            {
                "name": "Tarrasch Defense",
                "branch_ply": 3,
                "moves": ["c7c5", "c4d5", "e7e6", "g1f3", "b8c6", "g2g3"],
            },
            {
                "name": "Slav-like ...c6",
                "branch_ply": 3,
                "moves": ["c7c6", "g1f3", "g8f6", "e2e3", "c8f5", "c4d5"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "scotch",
        "name": "Scotch Game",
        "description": "An aggressive opening where White immediately opens the center for active piece play.",
        "color": "white",
        "difficulty": 2,
        "main_line": [
            "e2e4", "e7e5", "g1f3", "b8c6", "d2d4", "e5d4",
            "f3d4", "g8f6", "d4c6", "b7c6", "f1d3", "d7d5",
        ],
        "variations": [
            {
                "name": "Scotch: ...Bc5",
                "branch_ply": 7,
                "moves": ["f8c5", "c1e3", "d8f6", "c2c3", "g8e7", "f1c4"],
            },
            {
                "name": "Scotch: ...Qh4",
                "branch_ply": 7,
                "moves": ["d8h4", "d4b3", "h4e4", "c1e3", "f8d6", "b1c3"],
            },
            {
                "name": "Scotch Four Knights",
                "branch_ply": 5,
                "moves": ["g8f6", "b1c3", "f8b4", "d4e5", "f6e4", "f1d3"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "ruy-lopez",
        "name": "Ruy Lopez",
        "description": "One of the oldest and most respected openings. White puts lasting pressure on Black's center.",
        "color": "white",
        "difficulty": 3,
        "main_line": [
            "e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6",
            "b5a4", "g8f6", "e1g1", "f8e7", "f1e1", "b7b5",
            "a4b3", "d7d6",
        ],
        "variations": [
            {
                "name": "Berlin Defense",
                "branch_ply": 5,
                "moves": ["g8f6", "e1g1", "f6e4", "d2d4", "f8e7", "d1e2"],
            },
            {
                "name": "Classical Defense",
                "branch_ply": 5,
                "moves": ["f8c5", "c2c3", "g8f6", "d2d4", "c5b6", "e1g1"],
            },
            {
                "name": "Exchange Variation",
                "branch_ply": 5,
                "moves": ["a7a6", "b5c6", "d7c6", "e1g1", "f7f6", "d2d4"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "sicilian",
        "name": "Sicilian Defense",
        "description": "The most popular and aggressive response to 1.e4. Leads to sharp, exciting games.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4",
            "f3d4", "g8f6", "b1c3", "a7a6", "f1e2", "e7e5",
            "d4b3",
        ],
        "variations": [
            {
                "name": "Dragon Variation",
                "branch_ply": 7,
                "moves": ["g7g6", "b1c3", "f8g7", "c1e3", "b8c6", "f1c4"],
            },
            {
                "name": "Classical Sicilian",
                "branch_ply": 7,
                "moves": ["b8c6", "b1c3", "g7g6", "c1e3", "f8g7", "f1c4"],
            },
            {
                "name": "Sveshnikov Variation",
                "branch_ply": 3,
                "moves": ["b8c6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "e7e5"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "french",
        "name": "French Defense",
        "description": "A solid defense where Black builds a strong pawn structure and counterattacks the center.",
        "color": "black",
        "difficulty": 2,
        "main_line": [
            "e2e4", "e7e6", "d2d4", "d7d5", "b1c3", "g8f6",
            "e4e5", "f6d7", "f2f4", "c7c5", "g1f3", "b8c6",
        ],
        "variations": [
            {
                "name": "Winawer Variation",
                "branch_ply": 5,
                "moves": ["f8b4", "e4e5", "c7c5", "a2a3", "b4c3", "b2c3"],
            },
            {
                "name": "Tarrasch Variation",
                "branch_ply": 4,
                "moves": ["b1d2", "g8f6", "e4e5", "f6d7", "f1d3", "c7c5"],
            },
            {
                "name": "Exchange Variation",
                "branch_ply": 4,
                "moves": ["e4d5", "e6d5", "g1f3", "g8f6", "f1d3", "f8d6"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "caro-kann",
        "name": "Caro-Kann Defense",
        "description": "A very solid defense that avoids cramped positions while keeping good piece activity.",
        "color": "black",
        "difficulty": 2,
        "main_line": [
            "e2e4", "c7c6", "d2d4", "d7d5", "b1c3", "d5e4",
            "c3e4", "c8f5", "e4g3", "f5g6", "g1f3", "b8d7",
        ],
        "variations": [
            {
                "name": "Advance Variation",
                "branch_ply": 4,
                "moves": ["e4e5", "c8f5", "g1f3", "e7e6", "f1e2", "b8d7"],
            },
            {
                "name": "Two Knights Variation",
                "branch_ply": 4,
                "moves": ["g1f3", "d5e4", "f3e5", "c8f5", "b1c3", "e7e6"],
            },
            {
                "name": "Exchange Variation",
                "branch_ply": 4,
                "moves": ["e4d5", "c6d5", "f1d3", "b8c6", "c2c3", "g8f6"],
            },
        ],
        "response_after_ply": 4,
    },
    {
        "id": "kings-indian",
        "name": "King's Indian Defense",
        "description": "An aggressive defense where Black lets White build a big center, then counterattacks it.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "d2d4", "g8f6", "c2c4", "g7g6", "b1c3", "f8g7",
            "e2e4", "d7d6", "g1f3", "e8g8", "f1e2", "e7e5",
        ],
        "variations": [
            {
                "name": "Samisch Variation",
                "branch_ply": 6,
                "moves": ["f2f3", "d7d6", "e2e4", "e8g8", "g1e2", "e7e5"],
            },
            {
                "name": "Four Pawns Attack",
                "branch_ply": 6,
                "moves": ["f2f4", "d7d6", "g1f3", "e8g8", "e2e4", "c7c5"],
            },
            {
                "name": "Fianchetto Variation",
                "branch_ply": 4,
                "moves": ["g2g3", "f8g7", "f1g2", "e8g8", "g1f3", "d7d6", "e1g1"],
            },
        ],
        "response_after_ply": 6,
    },
    {
        "id": "pirc",
        "name": "Pirc Defense",
        "description": "A hypermodern defense where Black invites White to build a center, planning to undermine it later.",
        "color": "black",
        "difficulty": 3,
        "main_line": [
            "e2e4", "d7d6", "d2d4", "g8f6", "b1c3", "g7g6",
            "f2f4", "f8g7", "g1f3", "e8g8", "f1d3", "b8c6",
        ],
        "variations": [
            {
                "name": "Classical Pirc",
                "branch_ply": 6,
                "moves": ["g1f3", "f8g7", "f1e2", "e8g8", "e1g1", "c7c6"],
            },
            {
                "name": "Pirc: ...c6 system",
                "branch_ply": 7,
                "moves": ["c7c6", "g1f3", "f8g7", "f1d3", "e8g8", "e1g1"],
            },
            {
                "name": "Pirc: ...Bg4 line",
                "branch_ply": 5,
                "moves": ["c8g4", "g1f3", "b8d7", "f1e2", "e7e6", "e1g1"],
            },
        ],
        "response_after_ply": 4,
    },
]


# ---------------------------------------------------------------------------
# Move validation helpers
# ---------------------------------------------------------------------------

def validate_moves(moves: list[str]) -> list[tuple[str, str, str]]:
    """Validate a sequence of UCI moves. Returns [(uci, san, fen_after), ...]."""
    board = chess.Board()
    result = []
    for uci_str in moves:
        move = chess.Move.from_uci(uci_str)
        if move not in board.legal_moves:
            raise ValueError(f"Illegal move {uci_str} in position:\n{board.fen()}\n{board}")
        san = board.san(move)
        board.push(move)
        result.append((uci_str, san, board.fen()))
    return result


def get_fen_after(moves: list[str]) -> str:
    """Return FEN after playing a sequence of UCI moves."""
    board = chess.Board()
    for uci_str in moves:
        board.push(chess.Move.from_uci(uci_str))
    return board.fen()


def get_san(moves: list[str], move_index: int) -> str:
    """Get SAN for the move at move_index in the given sequence."""
    board = chess.Board()
    for i, uci_str in enumerate(moves):
        m = chess.Move.from_uci(uci_str)
        if i == move_index:
            return board.san(m)
        board.push(m)
    return ""


# ---------------------------------------------------------------------------
# Tree building
# ---------------------------------------------------------------------------

def build_tree(opening: dict) -> dict:
    """Build the opening tree JSON structure from hardcoded main line + variations."""
    opening_id = opening["id"]
    main_line = opening["main_line"]

    # Validate main line
    validated_main = validate_moves(main_line)

    # Build main line nodes (nested)
    root = {
        "id": f"{opening_id}/root",
        "children": [],
        "isMainLine": True,
        "weight": 0,
    }

    # Create nested main line
    current_node = root
    path_so_far = []
    for i, (uci, san, fen) in enumerate(validated_main):
        path_so_far.append(uci)
        node_id = f"{opening_id}/{'/'.join(path_so_far)}"
        weight = max(300 - i * 20, 50)
        child = {
            "id": node_id,
            "move": {"uci": uci, "san": san, "explanation": ""},
            "isMainLine": True,
            "weight": weight,
            "children": [],
        }
        current_node["children"].append(child)
        current_node = child

    # Graft variations
    for var in opening.get("variations", []):
        branch_ply = var["branch_ply"]
        var_moves = var["moves"]
        var_name = var["name"]

        # Navigate to the branch point in the main line tree
        parent = root
        for i in range(branch_ply):
            # Find the main line child
            main_children = [c for c in parent["children"] if c.get("isMainLine")]
            if not main_children:
                break
            parent = main_children[0]

        # Validate variation moves from the board state at branch_ply
        board = chess.Board()
        for uci_str in main_line[:branch_ply]:
            board.push(chess.Move.from_uci(uci_str))

        # Build variation path prefix from main line
        main_path = main_line[:branch_ply]

        try:
            var_validated = []
            var_board = board.copy()
            for uci_str in var_moves:
                m = chess.Move.from_uci(uci_str)
                if m not in var_board.legal_moves:
                    raise ValueError(
                        f"Illegal variation move {uci_str} in {var_name} "
                        f"at position:\n{var_board.fen()}"
                    )
                san = var_board.san(m)
                var_board.push(m)
                var_validated.append((uci_str, san, var_board.fen()))
        except ValueError as e:
            print(f"  WARNING: Skipping variation '{var_name}': {e}")
            continue

        # Build the variation branch
        var_current = parent
        var_path = list(main_path)
        for j, (uci, san, fen) in enumerate(var_validated):
            var_path.append(uci)
            node_id = f"{opening_id}/{'/'.join(var_path)}"
            weight = max(200 - (branch_ply + j) * 15, 30)
            child = {
                "id": node_id,
                "move": {"uci": uci, "san": san, "explanation": ""},
                "isMainLine": False,
                "weight": weight,
                "children": [],
            }
            if j == 0:
                child["variationName"] = var_name
            var_current["children"].append(child)
            var_current = child

    return root


# ---------------------------------------------------------------------------
# Claude API helpers
# ---------------------------------------------------------------------------

def extract_json_from_response(text: str):
    """Extract JSON from a Claude response, handling markdown code blocks."""
    text = text.strip()
    # Remove markdown code fences
    if text.startswith("```"):
        lines = text.split("\n")
        # Remove first and last fence lines
        start = 1
        end = len(lines)
        for i in range(len(lines) - 1, 0, -1):
            if lines[i].strip().startswith("```"):
                end = i
                break
        text = "\n".join(lines[start:end]).strip()

    if text.startswith("{") or text.startswith("["):
        return json.loads(text)

    # Try to find JSON object or array
    for start_char, end_char in [("{", "}"), ("[", "]")]:
        start = text.find(start_char)
        end = text.rfind(end_char)
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end + 1])
            except json.JSONDecodeError:
                continue

    raise ValueError(f"Could not extract JSON from response: {text[:200]}")


def call_claude(client, prompt: str, max_tokens: int = 4000) -> str:
    """Call Claude API with rate limiting."""
    response = client.messages.create(
        model=MODEL,
        max_tokens=max_tokens,
        messages=[{"role": "user", "content": prompt}],
    )
    time.sleep(API_DELAY)
    return response.content[0].text


# ---------------------------------------------------------------------------
# Content generation
# ---------------------------------------------------------------------------

def generate_move_explanations(client, opening: dict, tree: dict) -> dict:
    """Use Claude to generate beginner-friendly explanations for each move in the tree."""
    # Collect all moves that need explanations
    moves_info = []

    def collect_moves(node, board_state_moves=None):
        if board_state_moves is None:
            board_state_moves = []
        for child in node.get("children", []):
            move_data = child.get("move", {})
            uci = move_data.get("uci", "")
            san = move_data.get("san", "")
            var_name = child.get("variationName", "")
            is_main = child.get("isMainLine", False)
            moves_info.append({
                "uci": uci,
                "san": san,
                "path": board_state_moves + [uci],
                "var_name": var_name,
                "is_main": is_main,
            })
            collect_moves(child, board_state_moves + [uci])

    collect_moves(tree)

    if not moves_info or client is None:
        return tree

    # Build prompt with all moves
    opening_color = opening["color"]
    move_list_str = ""
    for i, m in enumerate(moves_info):
        side = "White" if len(m["path"]) % 2 == 1 else "Black"
        var_str = f" (start of {m['var_name']})" if m["var_name"] else ""
        main_str = " [main line]" if m["is_main"] else " [variation]"
        move_list_str += f"{i+1}. {m['san']} ({m['uci']}) by {side}{var_str}{main_str}\n"

    prompt = f"""You are generating beginner-friendly move explanations for the {opening['name']} chess opening (played as {opening_color}).

For each move below, write a 1-2 sentence explanation suitable for a chess beginner learning this opening.
- Explain WHY the move is played (strategy, not just what it does)
- Use simple language, avoid jargon
- For the player's moves ({opening_color}): explain the idea/plan behind the move
- For the opponent's moves: explain what the opponent is trying to achieve

Moves:
{move_list_str}

Return ONLY a JSON array of strings, one explanation per move, in the same order:
["explanation for move 1", "explanation for move 2", ...]"""

    try:
        text = call_claude(client, prompt, max_tokens=3000)
        explanations = extract_json_from_response(text)

        # Apply explanations to tree
        idx = [0]

        def apply_explanations(node):
            for child in node.get("children", []):
                if idx[0] < len(explanations):
                    child["move"]["explanation"] = explanations[idx[0]]
                    idx[0] += 1
                apply_explanations(child)

        apply_explanations(tree)
    except Exception as e:
        print(f"  WARNING: Move explanation generation failed: {e}")
        # Apply fallback explanations
        _apply_fallback_explanations(tree, opening)

    return tree


def _apply_fallback_explanations(tree: dict, opening: dict):
    """Apply generic fallback explanations when API fails."""
    def apply(node, depth=0):
        for child in node.get("children", []):
            move = child.get("move", {})
            san = move.get("san", "")
            if not move.get("explanation"):
                side = "White" if depth % 2 == 0 else "Black"
                move["explanation"] = f"{side} plays {san}, continuing development."
            apply(child, depth + 1)
    apply(tree)


def generate_plan(client, opening: dict) -> dict:
    """Use Claude to generate the opening plan."""
    if client is None:
        return _placeholder_plan(opening)

    # Get the main line in a readable format
    board = chess.Board()
    move_str = ""
    for i, uci in enumerate(opening["main_line"]):
        m = chess.Move.from_uci(uci)
        san = board.san(m)
        if i % 2 == 0:
            move_str += f"{i//2 + 1}. {san} "
        else:
            move_str += f"{san} "
        board.push(m)

    prompt = f"""Generate a comprehensive opening plan for the {opening['name']} chess opening.
The player plays as {opening['color']}.
Main line: {move_str.strip()}

Return ONLY valid JSON matching this EXACT schema (no extra keys):
{{
  "summary": "2-3 sentence summary of what you're trying to achieve in this opening",
  "strategicGoals": [
    {{"description": "specific goal 1", "priority": 1}},
    {{"description": "specific goal 2", "priority": 2}},
    {{"description": "specific goal 3", "priority": 3}},
    {{"description": "specific goal 4", "priority": 4}}
  ],
  "pawnStructureTarget": "description of ideal pawn structure",
  "keySquares": ["e4", "d5", "f5"],
  "pieceTargets": [
    {{"piece": "light-squared bishop", "idealSquares": ["c4", "b3"], "reasoning": "why this piece goes here"}},
    {{"piece": "knight", "idealSquares": ["f3"], "reasoning": "why"}}
  ],
  "typicalPlans": ["plan 1 in 1 sentence", "plan 2", "plan 3"],
  "commonMistakes": ["mistake 1", "mistake 2", "mistake 3"],
  "historicalNote": "1-2 sentences of historical context about this opening"
}}

Be specific to the {opening['name']}. Use beginner-friendly language.
Key squares should be algebraic notation (e.g., "e4", "d5").
Include 3-5 piece targets with specific ideal squares."""

    try:
        text = call_claude(client, prompt, max_tokens=2000)
        plan = extract_json_from_response(text)
        return plan
    except Exception as e:
        print(f"  WARNING: Plan generation failed: {e}")
        return _placeholder_plan(opening)


def _placeholder_plan(opening: dict) -> dict:
    """Generate a placeholder plan when API is unavailable."""
    return {
        "summary": f"The {opening['name']} is a {opening['color']} opening focusing on piece development and center control.",
        "strategicGoals": [
            {"description": "Control the center", "priority": 1},
            {"description": "Develop pieces actively", "priority": 2},
            {"description": "Castle for king safety", "priority": 3},
            {"description": "Create attacking chances", "priority": 4},
        ],
        "pawnStructureTarget": "Flexible center",
        "keySquares": ["e4", "d4", "e5", "d5"],
        "pieceTargets": [],
        "typicalPlans": ["Develop all pieces before attacking"],
        "commonMistakes": [
            "Moving the same piece twice",
            "Neglecting development",
            "Forgetting to castle",
        ],
        "historicalNote": f"The {opening['name']} has been played by many strong players throughout chess history.",
    }


def generate_lessons_and_quizzes(client, opening: dict) -> dict:
    """Generate planLessons, planQuizzes, theoryLessons, theoryQuizzes."""
    if client is None:
        return _placeholder_lessons(opening)

    main_line = opening["main_line"]
    variations = opening.get("variations", [])

    # Build FEN positions at various points
    fens = {}
    board = chess.Board()
    move_strs = []
    for i, uci in enumerate(main_line):
        m = chess.Move.from_uci(uci)
        san = board.san(m)
        board.push(m)
        fen = board.fen()
        ply = i + 1
        fens[ply] = fen
        if i % 2 == 0:
            move_strs.append(f"{i//2 + 1}. {san}")
        else:
            move_strs[-1] += f" {san}"

    game_notation = " ".join(move_strs)

    # Collect variation info
    var_info = []
    for var in variations:
        branch = var["branch_ply"]
        vboard = chess.Board()
        for uci in main_line[:branch]:
            vboard.push(chess.Move.from_uci(uci))
        var_moves_san = []
        for uci in var["moves"]:
            m = chess.Move.from_uci(uci)
            san = vboard.san(m)
            vboard.push(m)
            var_moves_san.append(san)
        var_fen = vboard.fen()
        var_info.append({
            "name": var["name"],
            "branch_ply": branch,
            "moves_san": var_moves_san,
            "final_fen": var_fen,
        })

    # Select key FEN positions for lessons (early, middle, late in the line)
    key_plies = []
    line_len = len(main_line)
    if line_len >= 2:
        key_plies.append(1)
    if line_len >= 4:
        key_plies.append(min(3, line_len))
    if line_len >= 6:
        key_plies.append(min(5, line_len))
    if line_len >= 8:
        key_plies.append(min(7, line_len))
    if line_len >= 10:
        key_plies.append(min(10, line_len))

    fen_positions = json.dumps({str(k): v for k, v in fens.items()})

    prompt = f"""Generate lessons and quizzes for the {opening['name']} chess opening (played as {opening['color']}).

Main line: {game_notation}

Key FEN positions (by ply number):
{fen_positions}

Variations:
{json.dumps(var_info, indent=2)}

Return ONLY valid JSON with this EXACT structure:
{{
  "planLessons": [
    {{
      "title": "Short title (3-6 words)",
      "description": "2-3 sentence explanation of this concept for beginners",
      "fen": "USE AN EXACT FEN FROM THE POSITIONS ABOVE",
      "highlights": ["e4", "d5"],
      "arrows": [{{"from": "e2", "to": "e4"}}],
      "style": "good"
    }}
  ],
  "planQuizzes": [
    {{
      "fen": "USE AN EXACT FEN FROM THE POSITIONS ABOVE",
      "prompt": "Question about the position (1 sentence)",
      "choices": [
        {{"text": "Correct answer with brief reason", "isCorrect": true}},
        {{"text": "Wrong answer 1", "isCorrect": false}},
        {{"text": "Wrong answer 2", "isCorrect": false}}
      ],
      "correctIndex": 0,
      "explanation": "1-2 sentence explanation of why the correct answer is right",
      "boardHighlightsOnReveal": ["e4"],
      "arrowsOnReveal": [{{"from": "e2", "to": "e4"}}]
    }}
  ],
  "theoryLessons": [
    {{
      "title": "Variation Name (ECO code if known)",
      "description": "2-3 sentence explanation of this variation",
      "fen": "USE AN EXACT FEN",
      "highlights": ["c5", "d4"],
      "arrows": [{{"from": "c7", "to": "c5"}}],
      "style": "theory"
    }}
  ],
  "theoryQuizzes": [
    {{
      "fen": "USE AN EXACT FEN",
      "prompt": "Question about variations/theory",
      "choices": [
        {{"text": "Correct answer", "isCorrect": true}},
        {{"text": "Wrong answer 1", "isCorrect": false}},
        {{"text": "Wrong answer 2", "isCorrect": false}}
      ],
      "correctIndex": 0,
      "explanation": "Why this is correct",
      "boardHighlightsOnReveal": ["d4"],
      "arrowsOnReveal": []
    }}
  ]
}}

Requirements:
- 3-5 planLessons (concepts: center control, piece development, king safety, pawn structure, common mistakes)
- 2-3 planQuizzes
- 2-4 theoryLessons (one per major variation)
- 2 theoryQuizzes
- ALL FEN strings MUST be exact copies from the positions listed above
- highlights and arrows use algebraic squares (e.g., "e4", "d5")
- style is one of: "good", "bad", "theory"
- Use beginner-friendly language throughout"""

    try:
        text = call_claude(client, prompt, max_tokens=4000)
        result = extract_json_from_response(text)
        return result
    except Exception as e:
        print(f"  WARNING: Lessons generation failed: {e}")
        return _placeholder_lessons(opening)


def _placeholder_lessons(opening: dict) -> dict:
    """Placeholder lessons when API is unavailable."""
    # Get a FEN from the main line
    board = chess.Board()
    for uci in opening["main_line"][:2]:
        board.push(chess.Move.from_uci(uci))
    fen_early = board.fen()

    for uci in opening["main_line"][2:min(6, len(opening["main_line"]))]:
        board.push(chess.Move.from_uci(uci))
    fen_mid = board.fen()

    return {
        "planLessons": [
            {
                "title": f"Introduction to the {opening['name']}",
                "description": f"The {opening['name']} is characterized by specific move orders that lead to unique pawn structures and plans.",
                "fen": fen_early,
                "highlights": [],
                "arrows": [],
                "style": "theory",
            },
        ],
        "planQuizzes": [
            {
                "fen": fen_mid,
                "prompt": f"What is the main idea behind the {opening['name']}?",
                "choices": [
                    {"text": "Control the center and develop pieces", "isCorrect": True},
                    {"text": "Attack immediately", "isCorrect": False},
                    {"text": "Move pawns as far as possible", "isCorrect": False},
                ],
                "correctIndex": 0,
                "explanation": f"The {opening['name']} focuses on sound development and central control.",
                "boardHighlightsOnReveal": [],
                "arrowsOnReveal": [],
            },
        ],
        "theoryLessons": [],
        "theoryQuizzes": [],
    }


def generate_opponent_responses(client, opening: dict) -> dict | None:
    """Generate the opponent response catalogue."""
    response_ply = opening.get("response_after_ply")
    if response_ply is None:
        return None

    main_line = opening["main_line"]
    after_moves = main_line[:response_ply]

    # Get the board position at the response point
    board = chess.Board()
    for uci in after_moves:
        board.push(chess.Move.from_uci(uci))

    # Get legal moves for the side to move
    legal_moves = list(board.legal_moves)
    if not legal_moves:
        return None

    # Get the SAN for each legal move
    move_sans = [(m.uci(), board.san(m)) for m in legal_moves[:10]]

    # The main line continuation
    main_next = main_line[response_ply] if response_ply < len(main_line) else None

    if client is None:
        # Generate placeholder responses
        responses = []
        for i, (uci, san) in enumerate(move_sans[:4]):
            is_main = (uci == main_next) if main_next else (i == 0)
            responses.append({
                "id": f"{opening['id']}-resp-{i}",
                "move": {"uci": uci, "san": san, "explanation": f"Opponent plays {san}."},
                "name": san,
                "eco": "",
                "frequency": round(0.4 - i * 0.1, 2) if i < 4 else 0.05,
                "description": f"The opponent continues with {san}.",
                "planAdjustment": "Adapt your plan accordingly.",
            })
        return {"afterMoves": after_moves, "responses": responses}

    # Use Claude to identify and describe the main opponent responses
    move_list = ", ".join(f"{san} ({uci})" for uci, san in move_sans[:8])
    game_so_far = ""
    b = chess.Board()
    for i, uci in enumerate(after_moves):
        m = chess.Move.from_uci(uci)
        san = b.san(m)
        if i % 2 == 0:
            game_so_far += f"{i//2 + 1}. {san} "
        else:
            game_so_far += f"{san} "
        b.push(m)

    prompt = f"""In the {opening['name']} opening, after the moves: {game_so_far.strip()}

The position FEN is: {board.fen()}

Legal moves include: {move_list}

Identify the 3-4 most important/common opponent responses and return ONLY valid JSON:
[
  {{
    "uci": "exact uci from the list",
    "san": "exact san from the list",
    "name": "Standard opening variation name",
    "eco": "ECO code (e.g., C54)",
    "frequency": 0.40,
    "description": "1 sentence beginner-friendly description",
    "explanation": "1 sentence explaining why the opponent plays this",
    "planAdjustment": "1 sentence on how to adjust your plan"
  }}
]

Requirements:
- Frequencies should sum to roughly 1.0
- Use EXACT uci and san strings from the legal moves list above
- Use standard opening names where applicable
- Be specific about plan adjustments"""

    try:
        text = call_claude(client, prompt, max_tokens=2000)
        resp_list = extract_json_from_response(text)

        responses = []
        for i, r in enumerate(resp_list):
            uci = r.get("uci", "")
            san = r.get("san", "")
            # Validate the move
            try:
                move = chess.Move.from_uci(uci)
                if move not in board.legal_moves:
                    # Try to find the move by SAN
                    try:
                        move = board.parse_san(san)
                        uci = move.uci()
                    except Exception:
                        continue
            except Exception:
                continue

            responses.append({
                "id": f"{opening['id']}-{uci.replace(' ', '')}",
                "move": {
                    "uci": uci,
                    "san": board.san(move),
                    "explanation": r.get("explanation", f"Opponent plays {san}."),
                },
                "name": r.get("name", san),
                "eco": r.get("eco", ""),
                "frequency": r.get("frequency", 0.25),
                "description": r.get("description", f"Opponent plays {san}."),
                "planAdjustment": r.get("planAdjustment", "Adapt your plan."),
            })

        if not responses:
            return None

        return {"afterMoves": after_moves, "responses": responses}
    except Exception as e:
        print(f"  WARNING: Opponent response generation failed: {e}")
        return None


# ---------------------------------------------------------------------------
# Progress tracking
# ---------------------------------------------------------------------------

def load_progress() -> set:
    """Load set of completed opening IDs from progress file."""
    if PROGRESS_FILE.exists():
        try:
            with open(PROGRESS_FILE) as f:
                data = json.load(f)
                return set(data.get("completed", []))
        except Exception:
            pass
    return set()


def save_progress(completed: set):
    """Save completed opening IDs to progress file."""
    with open(PROGRESS_FILE, "w") as f:
        json.dump({"completed": sorted(completed)}, f, indent=2)


# ---------------------------------------------------------------------------
# Main generation
# ---------------------------------------------------------------------------

def generate_opening_json(opening: dict, client, skip_api: bool = False) -> dict:
    """Generate a complete opening JSON structure."""
    print(f"\n{'='*60}")
    print(f"Generating: {opening['name']} ({opening['id']})")
    print(f"{'='*60}")

    # 1. Build and validate the tree
    print("  [1/5] Building move tree...")
    tree = build_tree(opening)

    # 2. Generate move explanations
    api_client = None if skip_api else client
    print("  [2/5] Generating move explanations...")
    tree = generate_move_explanations(api_client, opening, tree)

    # 3. Generate plan
    print("  [3/5] Generating opening plan...")
    plan = generate_plan(api_client, opening)

    # 4. Generate lessons and quizzes
    print("  [4/5] Generating lessons and quizzes...")
    lessons = generate_lessons_and_quizzes(api_client, opening)

    # Merge lessons into plan
    plan["planLessons"] = lessons.get("planLessons", [])
    plan["planQuizzes"] = lessons.get("planQuizzes", [])
    plan["theoryLessons"] = lessons.get("theoryLessons", [])
    plan["theoryQuizzes"] = lessons.get("theoryQuizzes", [])

    # 5. Generate opponent responses
    print("  [5/5] Generating opponent responses...")
    opponent_responses = generate_opponent_responses(api_client, opening)

    # Assemble final JSON
    result = {
        "id": opening["id"],
        "name": opening["name"],
        "description": opening["description"],
        "color": opening["color"],
        "difficulty": opening["difficulty"],
        "tree": tree,
        "plan": plan,
    }

    if opponent_responses:
        result["opponentResponses"] = opponent_responses

    return result


def main():
    parser = argparse.ArgumentParser(description="Generate all opening JSON files for ChessCoach")
    parser.add_argument("--dry-run", action="store_true", help="Only validate moves, don't generate content")
    parser.add_argument("--skip-api", action="store_true", help="Skip Claude API calls, use placeholders")
    parser.add_argument("--only", type=str, help="Comma-separated list of opening IDs to generate")
    parser.add_argument("--force", action="store_true", help="Regenerate even if JSON already exists")
    parser.add_argument("--no-resume", action="store_true", help="Don't resume from previous progress")
    args = parser.parse_args()

    # Check for API key
    if not args.skip_api and not args.dry_run:
        if anthropic is None:
            print("WARNING: anthropic SDK not installed. Using placeholder content.")
            print("Install with: pip install anthropic")
            args.skip_api = True
        elif not os.environ.get("ANTHROPIC_API_KEY"):
            print("WARNING: ANTHROPIC_API_KEY not set. Using placeholder content.")
            args.skip_api = True

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Filter openings
    openings_to_generate = OPENINGS
    if args.only:
        only_ids = set(args.only.split(","))
        openings_to_generate = [o for o in OPENINGS if o["id"] in only_ids]
        if not openings_to_generate:
            print(f"Error: No openings found matching: {args.only}")
            sys.exit(1)

    # Load progress
    completed = set() if args.no_resume else load_progress()

    # Dry run: just validate all moves
    if args.dry_run:
        print("DRY RUN: Validating all move sequences...\n")
        errors = 0
        for opening in openings_to_generate:
            print(f"  {opening['name']} ({opening['id']})...")
            try:
                validate_moves(opening["main_line"])
                print(f"    Main line: OK ({len(opening['main_line'])} moves)")
            except ValueError as e:
                print(f"    Main line: FAILED - {e}")
                errors += 1

            for var in opening.get("variations", []):
                try:
                    # Validate main line up to branch point
                    partial = opening["main_line"][:var["branch_ply"]]
                    validate_moves(partial)
                    # Then validate variation from that point
                    board = chess.Board()
                    for uci in partial:
                        board.push(chess.Move.from_uci(uci))
                    for uci in var["moves"]:
                        m = chess.Move.from_uci(uci)
                        if m not in board.legal_moves:
                            raise ValueError(f"Illegal: {uci} in {board.fen()}")
                        board.push(m)
                    print(f"    {var['name']}: OK ({len(var['moves'])} moves from ply {var['branch_ply']})")
                except ValueError as e:
                    print(f"    {var['name']}: FAILED - {e}")
                    errors += 1

        if errors:
            print(f"\n{errors} error(s) found.")
            sys.exit(1)
        else:
            print(f"\nAll {len(openings_to_generate)} openings validated successfully!")
        return

    # Create Claude client
    client = None
    if not args.skip_api:
        client = anthropic.Anthropic()

    # Generate openings
    generated = 0
    skipped = 0
    failed = 0

    for opening in openings_to_generate:
        oid = opening["id"]

        # Skip existing JSON files (italian, london)
        output_path = OUTPUT_DIR / f"{oid}.json"
        if oid in EXISTING_IDS and output_path.exists() and not args.force:
            print(f"\nSkipping {opening['name']} (existing JSON)")
            skipped += 1
            continue

        # Skip if already completed in this run
        if oid in completed and not args.force:
            print(f"\nSkipping {opening['name']} (already completed)")
            skipped += 1
            continue

        try:
            result = generate_opening_json(opening, client, args.skip_api)

            # Write output
            with open(output_path, "w") as f:
                json.dump(result, f, indent=2)

            print(f"  Written: {output_path}")
            generated += 1

            # Save progress
            completed.add(oid)
            save_progress(completed)

        except Exception as e:
            print(f"  ERROR generating {opening['name']}: {e}")
            import traceback
            traceback.print_exc()
            failed += 1
            continue

    print(f"\n{'='*60}")
    print(f"Done! Generated: {generated}, Skipped: {skipped}, Failed: {failed}")
    print(f"Output directory: {OUTPUT_DIR}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
