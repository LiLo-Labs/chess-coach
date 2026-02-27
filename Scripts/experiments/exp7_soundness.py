#!/usr/bin/env python3
"""Experiment 7: Soundness Tolerance Curve — tests ELO-scaled tolerance for centipawn loss.

Pure math, no LLM calls. Tests different tolerance curves against typical centipawn losses.
Current: Linear from 130 (ELO 400) to 50 (ELO 1400).
Formula: soundness = 100 * exp(-cpLoss / tolerance)
"""

import csv
import math
from datetime import datetime, timezone
from pathlib import Path

RESULTS_DIR = Path(__file__).parent / "results"

# ELO test points
TEST_ELOS = [500, 800, 1000, 1200]

# Centipawn losses to test
CP_LOSSES = [0, 10, 30, 50, 80, 120, 200, 300]

# Tolerance curve configurations to test
# Each is a dict mapping ELO -> tolerance value
TOLERANCE_CURVES = [
    {
        "name": "current_linear",
        "description": "Current: linear 130 (ELO 400) to 50 (ELO 1400)",
        "min_elo": 400, "max_elo": 1400,
        "tol_at_min": 130.0, "tol_at_max": 50.0,
    },
    {
        "name": "wider_range",
        "description": "Wider: 150 (ELO 400) to 40 (ELO 1400)",
        "min_elo": 400, "max_elo": 1400,
        "tol_at_min": 150.0, "tol_at_max": 40.0,
    },
    {
        "name": "narrower_range",
        "description": "Narrower: 110 (ELO 400) to 60 (ELO 1400)",
        "min_elo": 400, "max_elo": 1400,
        "tol_at_min": 110.0, "tol_at_max": 60.0,
    },
    {
        "name": "generous_beginner",
        "description": "More generous to beginners: 180 (ELO 400) to 50 (ELO 1400)",
        "min_elo": 400, "max_elo": 1400,
        "tol_at_min": 180.0, "tol_at_max": 50.0,
    },
    {
        "name": "strict_all",
        "description": "Strict across board: 100 (ELO 400) to 35 (ELO 1400)",
        "min_elo": 400, "max_elo": 1400,
        "tol_at_min": 100.0, "tol_at_max": 35.0,
    },
    {
        "name": "extended_elo",
        "description": "Extended ELO range: 130 (ELO 200) to 40 (ELO 1800)",
        "min_elo": 200, "max_elo": 1800,
        "tol_at_min": 130.0, "tol_at_max": 40.0,
    },
]


def tolerance_for_elo(curve, elo):
    """Compute tolerance at given ELO using linear interpolation."""
    clamped = max(curve["min_elo"], min(curve["max_elo"], elo))
    slope = (curve["tol_at_min"] - curve["tol_at_max"]) / (curve["max_elo"] - curve["min_elo"])
    return curve["tol_at_min"] - (clamped - curve["min_elo"]) * slope


def soundness_score(cp_loss, tolerance):
    """Compute soundness score using exponential decay."""
    if cp_loss <= 0:
        return 100
    return int(100 * math.exp(-cp_loss / tolerance))


def run_experiment():
    """Run soundness tolerance curve analysis."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = RESULTS_DIR / "exp7_soundness.csv"

    fieldnames = [
        "experiment_id", "trial_id", "timestamp", "curve_name", "curve_description",
        "elo", "tolerance", "cp_loss", "soundness_score",
        "tol_at_min_elo", "tol_at_max_elo",
    ]

    trial_id = 0
    results = []

    for curve in TOLERANCE_CURVES:
        for elo in TEST_ELOS:
            tol = tolerance_for_elo(curve, elo)
            for cp in CP_LOSSES:
                trial_id += 1
                score = soundness_score(cp, tol)
                results.append({
                    "experiment_id": "exp7",
                    "trial_id": str(trial_id),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "curve_name": curve["name"],
                    "curve_description": curve["description"],
                    "elo": elo,
                    "tolerance": f"{tol:.1f}",
                    "cp_loss": cp,
                    "soundness_score": score,
                    "tol_at_min_elo": curve["tol_at_min"],
                    "tol_at_max_elo": curve["tol_at_max"],
                })

    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"\n[exp7] Wrote {len(results)} data points to {csv_path}")

    # Print comparison table
    print("\nSoundness scores by curve, ELO, and centipawn loss:")
    print(f"{'Curve':<22} {'ELO':>4} {'Tol':>5} | " + " ".join(f"cp={cp:>3}" for cp in CP_LOSSES))
    print("-" * 100)

    for curve in TOLERANCE_CURVES:
        for elo in TEST_ELOS:
            tol = tolerance_for_elo(curve, elo)
            scores = [soundness_score(cp, tol) for cp in CP_LOSSES]
            score_str = " ".join(f"{s:>6}" for s in scores)
            print(f"{curve['name']:<22} {elo:>4} {tol:>5.0f} | {score_str}")
        print()

    # Analyze: which curve best separates small mistakes from big ones?
    print("Gradient analysis (how quickly does score drop?):")
    for curve in TOLERANCE_CURVES:
        gradients = []
        for elo in TEST_ELOS:
            tol = tolerance_for_elo(curve, elo)
            s30 = soundness_score(30, tol)   # small inaccuracy
            s120 = soundness_score(120, tol)  # real mistake
            gradients.append(s30 - s120)
        avg_gradient = sum(gradients) / len(gradients)
        print(f"  {curve['name']:<22}: avg gap (cp30 vs cp120) = {avg_gradient:.0f} points")

    return str(csv_path)


if __name__ == "__main__":
    run_experiment()
