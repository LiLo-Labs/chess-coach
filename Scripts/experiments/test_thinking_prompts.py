"""Quick experiment: find the right prompt structure for thinking mode format compliance.

Tests multiple system/user prompt strategies for getting Qwen3-4B to follow
structured output formats when thinking mode is enabled.

Uses 3 positions x 3 formats x N prompt strategies x 2 runs = fast iteration.
"""
import json
import os
import time
import csv
import re
from llama_cpp import Llama

THINKING_PARAMS = {"temperature": 0.6, "top_p": 0.95, "top_k": 20, "min_p": 0.0}

# 3 representative formats to test against
TEST_FORMATS = [
    {
        "id": "refs_coaching",
        "instruction": (
            "Respond with exactly two sections. First a REFS line listing the key squares "
            "or pieces, then a COACHING section with a brief explanation.\n"
            "Format:\n"
            "REFS: <comma-separated squares or pieces>\n"
            "COACHING: <one or two sentences>"
        ),
        "example": "REFS: bishop e5, pawn d4\nCOACHING: The bishop on e5 is very active, targeting the weak f7 pawn.",
    },
    {
        "id": "json_flat",
        "instruction": (
            "Respond with a single JSON object on one line containing two keys:\n"
            '- "coaching": a short coaching explanation\n'
            '- "refs": an array of referenced squares or pieces\n'
            "Output only the JSON, nothing else."
        ),
        "example": '{"coaching": "The bishop targets the weak f7 pawn.", "refs": ["bishop e5", "pawn d4"]}',
    },
    {
        "id": "numbered_lines",
        "instruction": (
            "Respond with exactly two numbered lines:\n"
            "1. REFS: <comma-separated squares or pieces>\n"
            "2. COACHING: <one or two sentences>"
        ),
        "example": "1. REFS: bishop e5, pawn d4\n2. COACHING: The bishop targets the weak f7 pawn.",
    },
]

# Prompt strategies to test
PROMPT_STRATEGIES = [
    {
        "id": "baseline",
        "name": "Baseline (just /think)",
        "system": "You are a helpful chess coaching assistant. /think",
        "user_prefix": "",
        "user_suffix": "",
    },
    {
        "id": "system_format_after_think",
        "name": "System: format instruction after </think>",
        "system": (
            "You are a helpful chess coaching assistant. /think\n"
            "You may reason inside <think>...</think> tags. "
            "After closing </think>, output ONLY the final answer in the exact format requested. "
            "No extra text outside the format."
        ),
        "user_prefix": "",
        "user_suffix": "\n\nIMPORTANT: After </think>, output ONLY the formatted response.",
    },
    {
        "id": "explicit_two_phase",
        "name": "Explicit two-phase instruction",
        "system": (
            "You are a helpful chess coaching assistant. /think\n"
            "Phase 1: Think about the chess position inside <think>...</think> tags.\n"
            "Phase 2: After </think>, write ONLY the formatted output. Nothing else."
        ),
        "user_prefix": "",
        "user_suffix": "\n\nRemember: your visible output after </think> must be ONLY the formatted response.",
    },
    {
        "id": "output_template",
        "name": "Show exact output template",
        "system": "You are a helpful chess coaching assistant. /think",
        "user_prefix": "",
        "user_suffix": (
            "\n\nYour response will be parsed by a program. After your thinking, "
            "output EXACTLY the format shown — no explanation, no preamble, no markdown fences "
            "(unless the format itself uses them)."
        ),
    },
    {
        "id": "repeat_format_end",
        "name": "Repeat format at end of user msg",
        "system": "You are a helpful chess coaching assistant. /think",
        "user_prefix": "",
        "user_suffix": (
            "\n\n[CRITICAL OUTPUT RULE]\n"
            "After </think>, your entire output must match the format above exactly.\n"
            "Do not write any text before or after the formatted output."
        ),
    },
    {
        "id": "no_think_just_format",
        "name": "/no_think but strong format instruction",
        "system": "You are a helpful chess coaching assistant. /no_think",
        "user_prefix": "",
        "user_suffix": "\n\nRespond with ONLY the formatted output. No explanation.",
    },
    {
        "id": "think_with_answer_tag",
        "name": "Think + wrap answer in <answer> tags",
        "system": (
            "You are a helpful chess coaching assistant. /think\n"
            "Think inside <think>...</think>. Then wrap your final formatted output "
            "in <answer>...</answer> tags."
        ),
        "user_prefix": "",
        "user_suffix": (
            "\n\nAfter thinking, wrap your response in <answer>...</answer> tags. "
            "Inside <answer>, use ONLY the format specified above."
        ),
    },
    {
        "id": "system_role_formatter",
        "name": "System: you are a formatter",
        "system": (
            "You are a chess coaching response formatter. /think\n"
            "You analyze chess positions and output structured responses in a specific format.\n"
            "Think inside <think>...</think>, then output ONLY the requested format."
        ),
        "user_prefix": "",
        "user_suffix": "",
    },
    {
        "id": "few_shot_thinking",
        "name": "Few-shot with thinking example",
        "system": "You are a helpful chess coaching assistant. /think",
        "user_prefix": "",
        "user_suffix": "",  # Will be built dynamically per format
        "dynamic_suffix": True,
    },
]

def build_few_shot_suffix(fmt):
    """Build a few-shot example showing thinking then formatted output."""
    if fmt["id"] == "refs_coaching":
        return (
            "\n\nHere is an example of the expected full response:\n"
            "<think>\nThe position has a strong bishop on e5 and a central pawn on d4. "
            "I should highlight these pieces.\n</think>\n"
            "REFS: bishop e5, pawn d4\n"
            "COACHING: The bishop on e5 is very active, targeting the weak f7 pawn."
        )
    elif fmt["id"] == "json_flat":
        return (
            "\n\nHere is an example of the expected full response:\n"
            "<think>\nThe position has a strong bishop on e5 and a central pawn on d4.\n</think>\n"
            '{"coaching": "The bishop targets the weak f7 pawn.", "refs": ["bishop e5", "pawn d4"]}'
        )
    elif fmt["id"] == "numbered_lines":
        return (
            "\n\nHere is an example of the expected full response:\n"
            "<think>\nThe position has a strong bishop on e5 and a central pawn on d4.\n</think>\n"
            "1. REFS: bishop e5, pawn d4\n"
            "2. COACHING: The bishop targets the weak f7 pawn."
        )
    return ""


def strip_thinking(text):
    """Strip <think>...</think> from response."""
    m = re.search(r"</think>\s*", text)
    if m:
        return text[m.end():].strip()
    return text.strip()


def strip_answer_tags(text):
    """Strip <answer>...</answer> wrapper if present."""
    m = re.search(r"<answer>\s*(.*?)\s*</answer>", text, re.DOTALL)
    if m:
        return m.group(1).strip()
    return text


def check_compliance(text, fmt_id):
    """Simple format compliance check."""
    text = strip_thinking(text)
    text = strip_answer_tags(text)
    if not text:
        return False

    if fmt_id == "refs_coaching":
        has_refs = bool(re.search(r"(?i)^REFS\s*:", text, re.MULTILINE))
        has_coaching = bool(re.search(r"(?i)^COACHING\s*:", text, re.MULTILINE))
        return has_refs and has_coaching

    elif fmt_id == "json_flat":
        try:
            obj = json.loads(text)
            return "coaching" in obj and "refs" in obj
        except (json.JSONDecodeError, TypeError):
            # Try extracting JSON from the text
            m = re.search(r'\{[^{}]*\}', text)
            if m:
                try:
                    obj = json.loads(m.group(0))
                    return "coaching" in obj and "refs" in obj
                except (json.JSONDecodeError, TypeError):
                    pass
            return False

    elif fmt_id == "numbered_lines":
        has_1 = bool(re.search(r"^1\.\s*REFS:", text, re.MULTILINE | re.IGNORECASE))
        has_2 = bool(re.search(r"^2\.\s*COACHING:", text, re.MULTILINE | re.IGNORECASE))
        return has_1 and has_2

    return False


def run_test(model_path):
    print(f"Loading model from {model_path} ...")
    model = Llama(model_path=model_path, n_ctx=2048, n_gpu_layers=-1, verbose=False)
    print("Model loaded.\n")

    # Load 3 test positions
    with open("test_positions.json") as f:
        all_positions = json.load(f)
    positions = all_positions[:3]

    RUNS = 2
    results = []

    total = len(PROMPT_STRATEGIES) * len(TEST_FORMATS) * len(positions) * RUNS
    trial_num = 0

    for strategy in PROMPT_STRATEGIES:
        for fmt in TEST_FORMATS:
            for pos in positions:
                for run in range(RUNS):
                    trial_num += 1

                    fen = pos.get("fen", "")
                    side = pos.get("side_to_move", "White")
                    context = f"Position (FEN): {fen}\nSide to move: {side}"
                    if pos.get("last_move"):
                        context += f"\nLast move: {pos['last_move']}"

                    user_msg = (
                        f"{strategy['user_prefix']}"
                        f"{context}\n\n"
                        f"Give a brief coaching insight for this position.\n\n"
                        f"{fmt['instruction']}\n\n"
                        f"Example:\n{fmt['example']}"
                    )

                    if strategy.get("dynamic_suffix"):
                        user_msg += build_few_shot_suffix(fmt)
                    elif strategy["user_suffix"]:
                        user_msg += strategy["user_suffix"]

                    t0 = time.time()
                    try:
                        output = model.create_chat_completion(
                            messages=[
                                {"role": "system", "content": strategy["system"]},
                                {"role": "user", "content": user_msg},
                            ],
                            max_tokens=300,
                            **THINKING_PARAMS,
                        )
                        raw = output["choices"][0]["message"]["content"]
                    except Exception as e:
                        raw = f"ERROR: {e}"
                    latency = (time.time() - t0) * 1000

                    compliant = check_compliance(raw, fmt["id"])
                    cleaned = strip_thinking(raw)
                    cleaned = strip_answer_tags(cleaned)

                    results.append({
                        "strategy": strategy["id"],
                        "format": fmt["id"],
                        "run": run + 1,
                        "compliant": compliant,
                        "latency_ms": round(latency),
                        "cleaned_response": cleaned[:200],
                    })

                    status = "OK" if compliant else "FAIL"
                    print(f"  [{trial_num}/{total}] {strategy['id']} | {fmt['id']} | {status} | {latency:.0f}ms")

    # Save raw results
    out_path = "results/thinking_prompt_test.csv"
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=results[0].keys())
        writer.writeheader()
        writer.writerows(results)

    # Print summary
    print("\n" + "=" * 80)
    print("RESULTS SUMMARY")
    print("=" * 80)

    # Aggregate by strategy
    from collections import defaultdict
    strat_stats = defaultdict(lambda: {"total": 0, "compliant": 0, "latencies": []})
    fmt_strat_stats = defaultdict(lambda: {"total": 0, "compliant": 0})

    for r in results:
        key = r["strategy"]
        strat_stats[key]["total"] += 1
        if r["compliant"]:
            strat_stats[key]["compliant"] += 1
        strat_stats[key]["latencies"].append(r["latency_ms"])

        fkey = (r["strategy"], r["format"])
        fmt_strat_stats[fkey]["total"] += 1
        if r["compliant"]:
            fmt_strat_stats[fkey]["compliant"] += 1

    print("\nOverall compliance by strategy:")
    print("%-30s %6s %8s %10s" % ("Strategy", "Trials", "Comply%", "Avg ms"))
    print("-" * 56)
    ranked = sorted(strat_stats.items(), key=lambda x: x[1]["compliant"]/x[1]["total"], reverse=True)
    for strat_id, stats in ranked:
        rate = stats["compliant"] / stats["total"] * 100
        avg_lat = sum(stats["latencies"]) / len(stats["latencies"])
        name = next(s["name"] for s in PROMPT_STRATEGIES if s["id"] == strat_id)
        print("%-30s %6d %7.1f%% %9.0fms" % (name[:30], stats["total"], rate, avg_lat))

    print("\nBreakdown by strategy x format:")
    print("%-30s %-18s %6s %8s" % ("Strategy", "Format", "Trials", "Comply%"))
    print("-" * 64)
    for strat_id, _ in ranked:
        name = next(s["name"] for s in PROMPT_STRATEGIES if s["id"] == strat_id)
        for fmt in TEST_FORMATS:
            fkey = (strat_id, fmt["id"])
            stats = fmt_strat_stats[fkey]
            rate = stats["compliant"] / stats["total"] * 100
            print("%-30s %-18s %6d %7.1f%%" % (name[:30], fmt["id"], stats["total"], rate))

    print(f"\nResults saved to {out_path}")
    return out_path


if __name__ == "__main__":
    path = os.environ.get("GGUF_MODEL_PATH", "")
    if not path:
        print("Set GGUF_MODEL_PATH")
        exit(1)
    run_test(path)
