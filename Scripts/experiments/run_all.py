#!/usr/bin/env python3
"""Master runner: executes experiments 1-8 in order and generates REPORT.md.

Experiments 1 must complete before 2 (uses best format), 2 before 3 (uses best prompt), etc.
Experiments 6 and 7 are pure math (no LLM) and run quickly.
Experiment 8 uses winning configs from all prior experiments.
"""

import os
import sys
import time
import csv
from datetime import datetime, timezone
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent
RESULTS_DIR = SCRIPTS_DIR / "results"
MODEL_PATH = os.environ.get("GGUF_MODEL_PATH", "Qwen3-4B-Q4_K_M.gguf")


def check_prerequisites():
    """Check that test positions exist, generate if not."""
    positions_path = SCRIPTS_DIR / "test_positions.json"
    if not positions_path.exists():
        print("=" * 60)
        print("Generating test positions...")
        print("=" * 60)
        try:
            from generate_test_positions import generate_positions
            generate_positions()
        except Exception as e:
            print(f"Warning: Could not generate test positions: {e}")
            print("Experiments will use fallback data or fail gracefully.")
    return positions_path.exists()


def run_with_timing(name, run_func, **kwargs):
    """Run an experiment function and return (elapsed_seconds, result_path)."""
    print(f"\n{'=' * 60}")
    print(f"Running {name}...")
    print(f"{'=' * 60}")
    start = time.time()
    try:
        result_path = run_func(**kwargs)
        elapsed = time.time() - start
        print(f"\n{name} completed in {elapsed:.1f}s")
        return elapsed, result_path, None
    except Exception as e:
        elapsed = time.time() - start
        print(f"\n{name} FAILED after {elapsed:.1f}s: {e}")
        import traceback
        traceback.print_exc()
        return elapsed, None, str(e)


def count_csv_rows(path):
    """Count data rows in a CSV file."""
    if not path or not Path(path).exists():
        return 0
    with open(path) as f:
        return sum(1 for _ in csv.reader(f)) - 1  # minus header


def read_best_from_csv(csv_path, group_col, score_col, higher_is_better=True):
    """Read a CSV and find the group with the best average score."""
    if not csv_path or not Path(csv_path).exists():
        return None, 0.0
    scores = {}
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            group = row.get(group_col, "")
            try:
                val = float(row.get(score_col, "0"))
                scores.setdefault(group, []).append(val)
            except (ValueError, TypeError):
                continue
    if not scores:
        return None, 0.0
    if higher_is_better:
        best = max(scores, key=lambda k: sum(scores[k]) / len(scores[k]))
    else:
        best = min(scores, key=lambda k: sum(scores[k]) / len(scores[k]))
    avg = sum(scores[best]) / len(scores[best])
    return best, avg


def generate_report(experiment_results, total_time):
    """Generate REPORT.md summarizing all experiment results."""
    report_path = RESULTS_DIR / "REPORT.md"
    lines = [
        "# On-Device LLM & PES Tuning — Experiment Report",
        f"",
        f"**Generated:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"**Model:** Qwen3-4B-Q4_K_M",
        f"**Total time:** {total_time:.0f}s ({total_time/60:.1f} min)",
        f"",
        "---",
        "",
    ]

    total_trials = 0
    total_llm_calls = 0

    # Experiment 1: Best format
    exp1_path = RESULTS_DIR / "exp1_formats.csv"
    if exp1_path.exists():
        best_fmt, compliance = read_best_from_csv(str(exp1_path), "variant_id", "format_compliance")
        trials = count_csv_rows(str(exp1_path))
        total_trials += trials
        total_llm_calls += trials
        lines.extend([
            "## Experiment 1: Output Format Wars",
            f"- **Best format:** `{best_fmt}` (compliance rate: {compliance:.0%})" if best_fmt else "- No results",
            f"- **Trials:** {trials}",
            "",
        ])
        # List all formats by compliance
        if best_fmt:
            fmt_scores = {}
            with open(exp1_path) as f:
                for row in csv.DictReader(f):
                    vid = row.get("variant_id", "")
                    ok = 1 if row.get("format_compliance", "False") == "True" else 0
                    fmt_scores.setdefault(vid, []).append(ok)
            lines.append("| Format | Compliance Rate |")
            lines.append("|--------|----------------|")
            for fmt, scores in sorted(fmt_scores.items(), key=lambda x: -sum(x[1])/len(x[1])):
                rate = sum(scores) / len(scores)
                lines.append(f"| `{fmt}` | {rate:.0%} |")
            lines.append("")

    # Experiment 2: Best prompt
    exp2_path = RESULTS_DIR / "exp2_prompts.csv"
    if exp2_path.exists():
        best_prompt, _ = read_best_from_csv(str(exp2_path), "variant_id", "format_compliance")
        trials = count_csv_rows(str(exp2_path))
        total_trials += trials
        total_llm_calls += trials
        lines.extend([
            "## Experiment 2: Prompt Architecture Sweep",
            f"- **Best prompt:** `{best_prompt}`" if best_prompt else "- No results",
            f"- **Trials:** {trials}",
            "",
        ])

    # Experiment 3: Token budgets
    exp3_path = RESULTS_DIR / "exp3_tokens.csv"
    if exp3_path.exists():
        best_tokens, avg_q = read_best_from_csv(str(exp3_path), "max_tokens", "quality_score")
        trials = count_csv_rows(str(exp3_path))
        total_trials += trials
        total_llm_calls += trials
        lines.extend([
            "## Experiment 3: Token Budget",
            f"- **Best max_tokens:** {best_tokens} (avg quality: {avg_q:.1f}/4)" if best_tokens else "- No results",
            f"- **Trials:** {trials}",
            "",
        ])

    # Experiment 4: Alignment
    exp4_path = RESULTS_DIR / "exp4_alignment.csv"
    if exp4_path.exists():
        best_align, parse_rate = read_best_from_csv(str(exp4_path), "variant_id", "json_parse_success")
        trials = count_csv_rows(str(exp4_path))
        total_trials += trials
        total_llm_calls += trials

        # Compute score separation
        separations = {}
        with open(exp4_path) as f:
            for row in csv.DictReader(f):
                vid = row.get("variant_id", "")
                is_book = row.get("is_book_move", "True") == "True"
                try:
                    score = float(row.get("alignment_score", "50"))
                except (ValueError, TypeError):
                    continue
                separations.setdefault(vid, {"book": [], "dev": []})
                if is_book:
                    separations[vid]["book"].append(score)
                else:
                    separations[vid]["dev"].append(score)

        lines.extend([
            "## Experiment 4: Alignment Prompt",
            f"- **Best variant:** `{best_align}` (parse rate: {parse_rate:.0%})" if best_align else "- No results",
            f"- **Trials:** {trials}",
        ])
        if separations:
            lines.append("")
            lines.append("| Variant | Parse Rate | Avg Book | Avg Dev | Separation |")
            lines.append("|---------|-----------|----------|---------|------------|")
            for vid, data in sorted(separations.items(),
                                    key=lambda x: (sum(x[1]["book"])/max(len(x[1]["book"]),1) -
                                                   sum(x[1]["dev"])/max(len(x[1]["dev"]),1)),
                                    reverse=True):
                avg_b = sum(data["book"])/max(len(data["book"]),1)
                avg_d = sum(data["dev"])/max(len(data["dev"]),1)
                sep = avg_b - avg_d
                lines.append(f"| `{vid}` | - | {avg_b:.0f} | {avg_d:.0f} | {sep:.0f} |")
        lines.append("")

    # Experiment 5: Opponent coaching
    exp5_path = RESULTS_DIR / "exp5_opponent.csv"
    if exp5_path.exists():
        best_opp, _ = read_best_from_csv(str(exp5_path), "variant_id", "format_compliance")
        trials = count_csv_rows(str(exp5_path))
        total_trials += trials
        total_llm_calls += trials
        lines.extend([
            "## Experiment 5: Opponent Move Coaching",
            f"- **Best variant:** `{best_opp}`" if best_opp else "- No results",
            f"- **Trials:** {trials}",
            "",
        ])

    # Experiment 6: PES weights
    exp6_path = RESULTS_DIR / "exp6_pes_weights.csv"
    if exp6_path.exists():
        trials = count_csv_rows(str(exp6_path))
        total_trials += trials
        best_row = None
        best_sep = -999
        with open(exp6_path) as f:
            for row in csv.DictReader(f):
                sep = float(row.get("separation", "0"))
                if sep > best_sep:
                    best_sep = sep
                    best_row = row
        lines.extend([
            "## Experiment 6: PES Formula Tuning",
            f"- **Best config:** soundness_weight={best_row['soundness_weight']}, "
            f"popularity_not_in_book={best_row['popularity_not_in_book']}, "
            f"popularity_top_move={best_row['popularity_top_move']}, "
            f"thresholds={best_row['threshold_set']}" if best_row else "- No results",
            f"- **Score separation:** {best_sep:.1f}" if best_row else "",
            f"- **Configurations tested:** {trials}",
            "",
        ])

    # Experiment 7: Soundness curve
    exp7_path = RESULTS_DIR / "exp7_soundness.csv"
    if exp7_path.exists():
        trials = count_csv_rows(str(exp7_path))
        total_trials += trials
        lines.extend([
            "## Experiment 7: Soundness Tolerance Curve",
            f"- **Data points:** {trials}",
            "- See `exp7_soundness.csv` for full comparison table",
            "",
        ])

    # Experiment 8: E2E
    exp8_summary = RESULTS_DIR / "exp8_summary.json"
    if exp8_summary.exists():
        import json
        with open(exp8_summary) as f:
            summary = json.load(f)
        trials = summary.get("total_trials", 0)
        total_trials += trials
        total_llm_calls += summary.get("total_llm_calls", 0)
        lines.extend([
            "## Experiment 8: End-to-End Validation",
            f"- **Trials:** {trials}",
        ])
        for elo, data in summary.get("results_by_elo", {}).items():
            lines.append(f"- **ELO {elo}:** avg PES = {data['avg_pes']}, range [{data['min_pes']}-{data['max_pes']}]")
        lines.append("")

    # Summary
    lines.extend([
        "---",
        "",
        "## Summary",
        f"- **Total experiments:** {sum(1 for _, _, err in experiment_results if err is None)}",
        f"- **Total trials:** {total_trials}",
        f"- **Total LLM calls:** {total_llm_calls}",
        f"- **Total time:** {total_time:.0f}s ({total_time/60:.1f} min)",
        "",
    ])

    # Recommended config
    lines.extend([
        "## Recommended Configuration",
        "",
        "```swift",
        "// AppConfig.swift updates based on experiment results",
        f"// Best output format: (from exp1)",
        f"// Best coaching prompt: (from exp2)",
        f"// Best max_tokens coaching: (from exp3)",
        f"// Best alignment prompt: (from exp4)",
        f"// Best opponent prompt: (from exp5)",
        f"// Best PES weights: (from exp6)",
        f"// Soundness curve: see exp7",
        "```",
        "",
    ])

    report_content = "\n".join(lines)
    with open(report_path, "w") as f:
        f.write(report_content)

    print(f"\nReport written to {report_path}")
    return str(report_path)


def main():
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    total_start = time.time()
    experiment_results = []

    # Check/generate test positions
    has_positions = check_prerequisites()

    # Experiment 1: Format Wars
    try:
        from exp1_formats import run_experiment as run_exp1
        elapsed, path, err = run_with_timing("Experiment 1: Output Format Wars", run_exp1, model_path=MODEL_PATH)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp1: {e}")
        experiment_results.append((0, None, str(e)))

    # Experiment 2: Prompt Architecture
    try:
        from exp2_prompts import run_experiment as run_exp2
        elapsed, path, err = run_with_timing("Experiment 2: Prompt Architecture Sweep", run_exp2, model_path=MODEL_PATH)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp2: {e}")
        experiment_results.append((0, None, str(e)))

    # Experiment 3: Token Budget
    try:
        from exp3_tokens import run_experiment as run_exp3
        elapsed, path, err = run_with_timing("Experiment 3: Token Budget", run_exp3, model_path=MODEL_PATH)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp3: {e}")
        experiment_results.append((0, None, str(e)))

    # Experiment 4: Alignment Prompt
    try:
        from exp4_alignment import run_experiment as run_exp4
        elapsed, path, err = run_with_timing("Experiment 4: Alignment Prompt", run_exp4, model_path=MODEL_PATH)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp4: {e}")
        experiment_results.append((0, None, str(e)))

    # Experiment 5: Opponent Coaching
    try:
        from exp5_opponent import run_experiment as run_exp5
        elapsed, path, err = run_with_timing("Experiment 5: Opponent Coaching", run_exp5, model_path=MODEL_PATH)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp5: {e}")
        experiment_results.append((0, None, str(e)))

    # Experiment 6: PES Weights (pure math — fast)
    try:
        from exp6_pes_weights import run_experiment as run_exp6
        elapsed, path, err = run_with_timing("Experiment 6: PES Weight Tuning", run_exp6)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp6: {e}")
        experiment_results.append((0, None, str(e)))

    # Experiment 7: Soundness Curve (pure math — fast)
    try:
        from exp7_soundness import run_experiment as run_exp7
        elapsed, path, err = run_with_timing("Experiment 7: Soundness Tolerance Curve", run_exp7)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp7: {e}")
        experiment_results.append((0, None, str(e)))

    # Experiment 8: End-to-End
    try:
        from exp8_e2e import run_experiment as run_exp8
        elapsed, path, err = run_with_timing("Experiment 8: End-to-End Validation", run_exp8, model_path=MODEL_PATH)
        experiment_results.append((elapsed, path, err))
    except ImportError as e:
        print(f"Skipping exp8: {e}")
        experiment_results.append((0, None, str(e)))

    total_time = time.time() - total_start

    # Generate report
    print(f"\n{'=' * 60}")
    print("Generating report...")
    print(f"{'=' * 60}")
    generate_report(experiment_results, total_time)

    # Print summary
    print(f"\n{'=' * 60}")
    print(f"ALL EXPERIMENTS COMPLETE")
    print(f"{'=' * 60}")
    exp_names = [
        "Exp 1: Formats", "Exp 2: Prompts", "Exp 3: Tokens", "Exp 4: Alignment",
        "Exp 5: Opponent", "Exp 6: PES Weights", "Exp 7: Soundness", "Exp 8: E2E",
    ]
    for i, (elapsed, path, err) in enumerate(experiment_results):
        status = "OK" if err is None else f"FAIL: {err}"
        print(f"  {exp_names[i]:<25} {elapsed:>6.1f}s  {status}")
    print(f"\n  Total time: {total_time:.0f}s ({total_time/60:.1f} min)")
    print(f"  Report: {RESULTS_DIR / 'REPORT.md'}")


if __name__ == "__main__":
    main()
