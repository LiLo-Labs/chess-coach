"""
Shared evaluation module for chess coaching experiment scripts.
Contains helper functions for evaluating LLM responses in the context of chess coaching.
"""

import re
import json
import xml.etree.ElementTree as ET
import chess


# ---------------------------------------------------------------------------
# Piece-name utilities
# ---------------------------------------------------------------------------

PIECE_NAMES = {
    "king": chess.KING,
    "queen": chess.QUEEN,
    "rook": chess.ROOK,
    "bishop": chess.BISHOP,
    "knight": chess.KNIGHT,
    "pawn": chess.PAWN,
}

PIECE_TYPE_TO_NAME = {v: k for k, v in PIECE_NAMES.items()}

PIECE_SYMBOL_TO_NAME = {
    "K": "King",
    "Q": "Queen",
    "R": "Rook",
    "B": "Bishop",
    "N": "Knight",
    "P": "Pawn",
}

# Squares: a1-h8
SQUARE_RE = r"[a-h][1-8]"

# Pattern to find piece + square references in free text.
# Handles forms like:
#   "bishop e5", "Bishop on e5", "white's knight c3", "the pawn on d4",
#   "Nc3" (SAN-style single-letter prefix), "Rook f1"
_COLOR_PREFIX = r"(?:(?:white|black)['\u2019]?s?\s+)?"
_ARTICLE = r"(?:the\s+|a\s+)?"
_PIECE_WORD = r"(?P<piece>king|queen|rook|bishop|knight|pawn)"
_ON = r"(?:\s+on)?\s+"
_SQ = r"(?P<square>[a-h][1-8])"

PIECE_REF_PATTERN = re.compile(
    _COLOR_PREFIX + _ARTICLE + _PIECE_WORD + _ON + _SQ,
    re.IGNORECASE,
)

# SAN-style single letter + square (e.g. "Nf3", "Be5") — uppercase letter required
SAN_PIECE_PATTERN = re.compile(r"(?<![a-zA-Z])(?P<symbol>[KQRBNP])(?P<square>[a-h][1-8])(?![a-zA-Z])")


# ---------------------------------------------------------------------------
# extract_piece_refs
# ---------------------------------------------------------------------------

def extract_piece_refs(text: str) -> list:
    """Extract piece+square references from text.

    Returns a list of (piece_name_lower, square) tuples.
    e.g. 'bishop e5' -> [('bishop', 'e5')]
    """
    results = []
    seen = set()

    # Natural language references: "bishop e5", "knight on c3", etc.
    for m in PIECE_REF_PATTERN.finditer(text):
        piece = m.group("piece").lower()
        sq = m.group("square").lower()
        key = (piece, sq)
        if key not in seen:
            seen.add(key)
            results.append(key)

    # SAN-style single-letter references: "Nf3", "Be5"
    san_letter_to_name = {
        "K": "king",
        "Q": "queen",
        "R": "rook",
        "B": "bishop",
        "N": "knight",
        "P": "pawn",
    }
    for m in SAN_PIECE_PATTERN.finditer(text):
        sym = m.group("symbol")
        sq = m.group("square").lower()
        piece = san_letter_to_name[sym]
        key = (piece, sq)
        if key not in seen:
            seen.add(key)
            results.append(key)

    return results


# ---------------------------------------------------------------------------
# Format parsing helpers
# ---------------------------------------------------------------------------

def parse_refs_coaching(response: str) -> dict:
    """Parse REFS/COACHING format.

    Expected structure (case-insensitive labels):
        REFS: bishop e5, knight c3
        COACHING: <free text>

    Returns {'refs': str, 'coaching': str, 'ok': bool}
    """
    refs = ""
    coaching = ""

    # Try to find REFS line
    refs_match = re.search(r"(?i)^[ \t]*REFS\s*[:=]\s*(.*)$", response, re.MULTILINE)
    if refs_match:
        refs = refs_match.group(1).strip()

    # Try to find COACHING section — everything after the COACHING label
    coaching_match = re.search(r"(?i)^[ \t]*COACHING\s*[:=]\s*(.*)", response, re.DOTALL | re.MULTILINE)
    if coaching_match:
        coaching = coaching_match.group(1).strip()

    ok = bool(refs_match and coaching_match)
    return {"refs": refs, "coaching": coaching, "ok": ok}


def parse_json_response(response: str) -> dict:
    """Parse JSON from response. Handles fenced JSON (```json ... ```) too.

    Returns parsed dict or None on failure.
    """
    # Try fenced JSON first
    fenced = re.search(r"```(?:json)?\s*\n?(.*?)```", response, re.DOTALL)
    if fenced:
        try:
            return json.loads(fenced.group(1).strip())
        except (json.JSONDecodeError, ValueError):
            pass

    # Try to find a raw JSON object in the response
    # Look for the outermost { ... }
    depth = 0
    start = None
    for i, ch in enumerate(response):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    return json.loads(response[start : i + 1])
                except (json.JSONDecodeError, ValueError):
                    start = None

    # Last resort: try parsing the whole response as JSON
    try:
        return json.loads(response.strip())
    except (json.JSONDecodeError, ValueError):
        return None


def parse_xml_response(response: str) -> dict:
    """Parse XML tags from response. Returns dict with extracted fields or None."""
    # Try wrapping in a root element in case the response has multiple top-level tags
    text = response.strip()

    # If the text doesn't start with <, try to find the XML portion
    first_tag = text.find("<")
    if first_tag == -1:
        return None
    text = text[first_tag:]

    # Strip trailing non-XML content after last >
    last_tag = text.rfind(">")
    if last_tag == -1:
        return None
    text = text[: last_tag + 1]

    # Wrap in root if not already a single root
    wrapped = f"<root>{text}</root>"
    try:
        root = ET.fromstring(wrapped)
    except ET.ParseError:
        # Try parsing as-is (might already have a single root)
        try:
            root = ET.fromstring(text)
        except ET.ParseError:
            return None

    result = {}
    for child in root:
        tag = child.tag
        # Handle CDATA — ElementTree exposes it as text
        content = child.text or ""
        # Also gather tail text of sub-elements
        inner_parts = [content]
        for sub in child:
            inner_parts.append(ET.tostring(sub, encoding="unicode", method="text") if sub.text else "")
            if sub.tail:
                inner_parts.append(sub.tail)
        result[tag] = "".join(inner_parts).strip()

    return result if result else None


# ---------------------------------------------------------------------------
# format_ok
# ---------------------------------------------------------------------------

def format_ok(response: str, expected_format: str) -> bool:
    """Check if the model followed the requested format.

    expected_format is one of:
        refs_coaching, coaching_only, json_flat, json_nested,
        xml_tags, xml_cdata, markdown_headers, numbered_lines,
        yaml_format, pipe_delimited, single_line_json, fenced_json
    """
    response = response.strip()
    if not response:
        return False

    # Strip thinking tags so we evaluate the actual output
    import re as _re
    _think_match = _re.search(r"</think>\s*", response)
    if _think_match:
        response = response[_think_match.end():].strip()
    if not response:
        return False

    fmt = expected_format.lower().strip()

    if fmt == "refs_coaching":
        parsed = parse_refs_coaching(response)
        return parsed["ok"]

    elif fmt == "coaching_only":
        # Should NOT contain REFS/COACHING labels — just free text coaching
        has_label = bool(re.search(r"(?i)^[ \t]*(?:REFS|COACHING)\s*[:=]", response, re.MULTILINE))
        # Accept any non-empty text that isn't structured with those labels
        return not has_label and len(response) > 0

    elif fmt in ("json_flat", "json_nested"):
        parsed = parse_json_response(response)
        if parsed is None:
            return False
        if fmt == "json_nested":
            # At least one value should itself be a dict or list
            return any(isinstance(v, (dict, list)) for v in parsed.values())
        return True

    elif fmt == "single_line_json":
        # JSON on a single line (no embedded newlines inside the JSON)
        parsed = parse_json_response(response)
        if parsed is None:
            return False
        # Re-serialize and check it could be one line
        # But the original response might have wrapping text; find the JSON portion
        fenced = re.search(r"```(?:json)?\s*\n?(.*?)```", response, re.DOTALL)
        json_str = fenced.group(1).strip() if fenced else response.strip()
        # Find the JSON object substring
        start = json_str.find("{")
        end = json_str.rfind("}")
        if start != -1 and end != -1:
            json_str = json_str[start : end + 1]
        return "\n" not in json_str

    elif fmt == "fenced_json":
        return bool(re.search(r"```(?:json)?\s*\n?\s*\{.*?\}\s*```", response, re.DOTALL))

    elif fmt in ("xml_tags", "xml_cdata"):
        parsed = parse_xml_response(response)
        if parsed is None:
            return False
        if fmt == "xml_cdata":
            # Expect CDATA sections in the raw response
            return "<![CDATA[" in response
        return True

    elif fmt == "markdown_headers":
        # Expect at least one markdown header (# or ##)
        return bool(re.search(r"^#{1,6}\s+\S", response, re.MULTILINE))

    elif fmt == "numbered_lines":
        # Expect lines starting with a number followed by . or )
        lines = [l.strip() for l in response.splitlines() if l.strip()]
        numbered = [l for l in lines if re.match(r"^\d+[.)]\s", l)]
        return len(numbered) >= 2

    elif fmt == "yaml_format":
        # Simple check: key: value lines
        lines = [l for l in response.splitlines() if l.strip()]
        yaml_lines = [l for l in lines if re.match(r"^[a-zA-Z_][\w]*\s*:", l)]
        return len(yaml_lines) >= 2

    elif fmt == "pipe_delimited":
        # Expect pipe-separated values
        return "|" in response and len(response.split("|")) >= 3

    return False


# ---------------------------------------------------------------------------
# Piece validation against FEN
# ---------------------------------------------------------------------------

def validate_pieces(refs: str, fen: str) -> bool:
    """Check if all referenced pieces actually exist on those squares in the given FEN.

    refs is like 'bishop e5, knight c3' or 'none' or empty string.
    Uses python-chess to validate.

    Returns True if every referenced piece is present, or if refs is empty/none.
    """
    refs = refs.strip().lower()
    if not refs or refs == "none":
        return True

    try:
        board = chess.Board(fen)
    except ValueError:
        return False

    piece_refs = extract_piece_refs(refs)
    if not piece_refs:
        # Could not parse any refs — treat as valid (no claims to verify)
        return True

    for piece_name, sq_str in piece_refs:
        piece_type = PIECE_NAMES.get(piece_name)
        if piece_type is None:
            return False
        try:
            sq = chess.parse_square(sq_str)
        except ValueError:
            return False
        board_piece = board.piece_at(sq)
        if board_piece is None or board_piece.piece_type != piece_type:
            return False

    return True


# ---------------------------------------------------------------------------
# Simple text checks
# ---------------------------------------------------------------------------

def mentions_opening(text: str, opening_name: str) -> bool:
    """Check if text mentions the opening name (case-insensitive)."""
    return opening_name.lower() in text.lower()


def mentions_move(text: str, move_san: str) -> bool:
    """Check if text mentions the SAN move or its spelled-out form.

    Handles common SAN moves like 'Nf3', 'e4', 'O-O', 'Bxe5', etc.
    Also recognises spelled-out forms like 'knight to f3'.
    """
    if not move_san:
        return False

    # Direct SAN mention (case-sensitive for piece letters, but be lenient)
    if move_san in text:
        return True

    # Case-insensitive check for pawn moves like 'e4'
    if re.search(re.escape(move_san), text, re.IGNORECASE):
        return True

    # Castling variants
    san_lower = move_san.lower().replace("\u2013", "-").replace("\u2014", "-")
    text_lower = text.lower().replace("\u2013", "-").replace("\u2014", "-")
    if san_lower in ("o-o", "0-0"):
        if any(term in text_lower for term in ("o-o", "0-0", "castles kingside", "kingside castle", "short castle")):
            return True
    if san_lower in ("o-o-o", "0-0-0"):
        if any(term in text_lower for term in ("o-o-o", "0-0-0", "castles queenside", "queenside castle", "long castle")):
            return True

    # Spelled-out form: "knight to f3", "bishop takes e5"
    san_piece_letter = {"K": "king", "Q": "queen", "R": "rook", "B": "bishop", "N": "knight"}
    # Parse SAN: optional piece letter, optional 'x' for capture, destination square
    m = re.match(r"^([KQRBN])?x?([a-h][1-8])", move_san)
    if m:
        piece_letter = m.group(1)
        dest = m.group(2)
        if piece_letter:
            piece_word = san_piece_letter[piece_letter]
            # "knight to f3", "knight f3", "knight takes f3"
            pattern = rf"{piece_word}\s+(?:to\s+|takes\s+|captures\s+)?{re.escape(dest)}"
            if re.search(pattern, text, re.IGNORECASE):
                return True
        else:
            # Pawn move like 'e4' — also check "pawn to e4"
            pattern = rf"pawn\s+(?:to\s+|takes\s+|captures\s+)?{re.escape(dest)}"
            if re.search(pattern, text, re.IGNORECASE):
                return True

    return False


def word_count(text: str) -> int:
    """Count words in text."""
    return len(text.split())


# ---------------------------------------------------------------------------
# Hallucination scoring
# ---------------------------------------------------------------------------

def hallucination_score(response: str, fen: str) -> int:
    """Score 0-3 for hallucination severity.

    0 = clean (all references valid or no specific references)
    1 = minor (wrong piece type on correct square — a piece exists there, just not the one claimed)
    2 = wrong square (piece of that type exists but on a different square)
    3 = phantom piece (piece of that type doesn't exist on the board at all for that colour,
        or the square is empty and no such piece exists)

    Uses python-chess to validate piece positions against FEN.
    Returns the worst (highest) score found across all references.
    """
    try:
        board = chess.Board(fen)
    except ValueError:
        return 0

    refs = extract_piece_refs(response)
    if not refs:
        return 0

    worst = 0

    for piece_name, sq_str in refs:
        piece_type = PIECE_NAMES.get(piece_name)
        if piece_type is None:
            continue

        try:
            sq = chess.parse_square(sq_str)
        except ValueError:
            continue

        board_piece = board.piece_at(sq)

        if board_piece is not None and board_piece.piece_type == piece_type:
            # Correct — no hallucination for this reference
            continue

        if board_piece is not None and board_piece.piece_type != piece_type:
            # Square is occupied, but by a different piece type
            score = 1
        else:
            # Square is empty — check if the piece type exists anywhere on the board
            # (for either colour)
            squares_of_type = board.pieces(piece_type, chess.WHITE) | board.pieces(piece_type, chess.BLACK)
            if squares_of_type:
                # The piece type exists but not on the claimed square
                score = 2
            else:
                # No piece of this type exists on the board at all
                score = 3

        worst = max(worst, score)

    return worst


# ---------------------------------------------------------------------------
# Board summary
# ---------------------------------------------------------------------------

def board_summary(fen: str) -> str:
    """Generate human-readable board summary from FEN.

    Example output:
    White: King g1, Queen d1, Rook a1, Rook f1, Bishop c4, Knight f3, Pawns a2 b2 c2 d3 e4 f2 g2 h2
    Black: King e8, Queen d8, Rook a8, Rook h8, Bishop c8, Bishop f8, Knight b8, Knight g8, Pawns a7 b7 c7 d7 e7 f7 g7 h7
    """
    try:
        board = chess.Board(fen)
    except ValueError:
        return f"Invalid FEN: {fen}"

    # Canonical piece ordering: K, Q, R, B, N, P
    piece_order = [chess.KING, chess.QUEEN, chess.ROOK, chess.BISHOP, chess.KNIGHT, chess.PAWN]

    parts = []
    for color, color_name in [(chess.WHITE, "White"), (chess.BLACK, "Black")]:
        segments = []
        for pt in piece_order:
            squares = sorted(board.pieces(pt, color), key=lambda s: (chess.square_file(s), chess.square_rank(s)))
            if not squares:
                continue
            name = PIECE_TYPE_TO_NAME[pt].capitalize()
            sq_names = [chess.square_name(s) for s in squares]
            if pt == chess.PAWN:
                segments.append(f"Pawns {' '.join(sq_names)}")
            else:
                for sn in sq_names:
                    segments.append(f"{name} {sn}")
        parts.append(f"{color_name}: {', '.join(segments)}")

    return "\n".join(parts)
