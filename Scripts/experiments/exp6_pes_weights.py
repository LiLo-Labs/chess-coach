#!/usr/bin/env python3
"""Experiment 6: PES Formula Tuning — grid search over composite formula weights and category thresholds.

Pure math, no LLM calls. Uses alignment scores collected from Experiment 4.
Current formula: total = (soundness * 40 + adjusted * 60) / 100
where adjusted = alignment + popularity_adj
"""

import csv
import itertools
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

RESULTS_DIR = Path(__file__).parent / "results"

# Parameter grid
SOUNDNESS_WEIGHTS = [30, 40, 50, 60]  # alignment_weight = 100 - soundness_weight
POPULARITY_NOT_IN_BOOK = [-10, -5, -3, 0]
POPULARITY_TOP_MOVE = [5, 8, 10, 15]
CATEGORY_THRESHOLDS = [
    {"name": "standard", "masterful": 90, "good": 75, "developing": 60, "needs_work": 40},
    {"name": "lenient", "masterful": 85, "good": 70, "developing": 55, "needs_work": 35},
    {"name": "strict", "masterful": 92, "good": 80, "developing": 65, "needs_work": 45},
]


def load_alignment_scores():
    """Load alignment scores from Experiment 4 results."""
    csv_path = RESULTS_DIR / "exp4_alignment.csv"
    scores = []
    if csv_path.exists():
        with open(csv_path) as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("json_parse_success") == "True" and row.get("alignment_score"):
                    scores.append({
                        "position_id": row["position_id"],
                        "variant_id": row["variant_id"],
                        "is_book_move": row.get("is_book_move", "True") == "True",
                        "alignment": int(float(row["alignment_score"])),
                        "thinking": row.get("thinking_mode", "off"),
                    })
    if not scores:
        # Generate synthetic scores for testing
        print("[exp6] No exp4 results found, using synthetic alignment scores")
        import random
        random.seed(42)
        for i in range(40):
            is_book = i < 20
            scores.append({
                "position_id": f"pos_{i}",
                "variant_id": "current",
                "is_book_move": is_book,
                "alignment": random.randint(65, 95) if is_book else random.randint(15, 55),
                "thinking": "on" if i % 2 == 0 else "off",
            })
    return scores


def categorize(score, thresholds):
    """Assign PES category based on thresholds."""
    if score >= thresholds["masterful"]:
        return "masterful"
    elif score >= thresholds["good"]:
        return "good"
    elif score >= thresholds["developing"]:
        return "developing"
    elif score >= thresholds["needs_work"]:
        return "needs_work"
    else:
        return "off_track"


def compute_pes(soundness, alignment, popularity_adj, soundness_weight):
    """Compute PES total score."""
    alignment_weight = 100 - soundness_weight
    adjusted = max(0, min(100, alignment + popularity_adj))
    total = (soundness * soundness_weight + adjusted * alignment_weight) / 100
    return max(0, min(100, int(total)))


def run_experiment():
    """Run PES weight grid search."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = RESULTS_DIR / "exp6_pes_weights.csv"

    alignment_scores = load_alignment_scores()

    # Simulate soundness scores: book moves ~85-95, deviations ~30-70
    import random
    random.seed(42)
    for s in alignment_scores:
        if s["is_book_move"]:
            s["soundness"] = random.randint(80, 98)
        else:
            s["soundness"] = random.randint(25, 75)

    fieldnames = [
        "experiment_id", "trial_id", "timestamp", "soundness_weight", "alignment_weight",
        "popularity_not_in_book", "popularity_top_move", "threshold_set",
        "avg_book_pes", "avg_deviation_pes", "separation",
        "book_masterful_pct", "book_good_pct", "deviation_off_track_pct",
        "correct_category_rate",
    ]

    trial_id = 0
    results = []

    for sw, pnib, ptm, thresh in itertools.product(
        SOUNDNESS_WEIGHTS, POPULARITY_NOT_IN_BOOK, POPULARITY_TOP_MOVE, CATEGORY_THRESHOLDS
    ):
        trial_id += 1
        book_scores = []
        dev_scores = []
        correct_categories = 0
        total = 0

        for s in alignment_scores:
            pop_adj = ptm if s["is_book_move"] else pnib
            pes = compute_pes(s["soundness"], s["alignment"], pop_adj, sw)
            cat = categorize(pes, thresh)

            if s["is_book_move"]:
                book_scores.append(pes)
                # "Correct" for book moves: should be good or masterful
                if cat in ("masterful", "good"):
                    correct_categories += 1
            else:
                dev_scores.append(pes)
                # "Correct" for deviations: should be needs_work or off_track
                if cat in ("needs_work", "off_track"):
                    correct_categories += 1
            total += 1

        avg_book = sum(book_scores) / len(book_scores) if book_scores else 0
        avg_dev = sum(dev_scores) / len(dev_scores) if dev_scores else 0
        separation = avg_book - avg_dev

        book_masterful = sum(1 for s in book_scores if s >= thresh["masterful"]) / max(len(book_scores), 1)
        book_good = sum(1 for s in book_scores if s >= thresh["good"]) / max(len(book_scores), 1)
        dev_off_track = sum(1 for s in dev_scores if s < thresh["needs_work"]) / max(len(dev_scores), 1)

        results.append({
            "experiment_id": "exp6",
            "trial_id": str(trial_id),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "soundness_weight": sw,
            "alignment_weight": 100 - sw,
            "popularity_not_in_book": pnib,
            "popularity_top_move": ptm,
            "threshold_set": thresh["name"],
            "avg_book_pes": f"{avg_book:.1f}",
            "avg_deviation_pes": f"{avg_dev:.1f}",
            "separation": f"{separation:.1f}",
            "book_masterful_pct": f"{book_masterful:.2f}",
            "book_good_pct": f"{book_good:.2f}",
            "deviation_off_track_pct": f"{dev_off_track:.2f}",
            "correct_category_rate": f"{correct_categories / max(total, 1):.2f}",
        })

    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    # Print top 5 by separation
    results.sort(key=lambda r: float(r["separation"]), reverse=True)
    print(f"\n[exp6] Wrote {len(results)} configurations to {csv_path}")
    print("\nTop 5 by score separation (book vs deviation):")
    for r in results[:5]:
        print(f"  sw={r['soundness_weight']} pnib={r['popularity_not_in_book']} "
              f"ptm={r['popularity_top_move']} thresh={r['threshold_set']} "
              f"=> sep={r['separation']} correct={r['correct_category_rate']}")

    return str(csv_path)


if __name__ == "__main__":
    run_experiment()
