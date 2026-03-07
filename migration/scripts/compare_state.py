#!/usr/bin/env python3
"""
Compare two JSON state dumps (iOS vs Android) for parity verification.

Usage:
    python3 compare_state.py <ios_state.json> <android_state.json>
    python3 compare_state.py --test  # run self-test with dummy data
"""

import json
import sys
import os
import tempfile


def load_json(path):
    """Load and parse a JSON file."""
    with open(path, 'r') as f:
        return json.load(f)


def compare_values(ios_val, android_val, path=""):
    """Recursively compare two values, returning list of differences."""
    diffs = []

    if type(ios_val) != type(android_val):
        # Allow int/float comparison
        if isinstance(ios_val, (int, float)) and isinstance(android_val, (int, float)):
            if abs(float(ios_val) - float(android_val)) > 1e-6:
                diffs.append(f"  {path}: iOS={ios_val} Android={android_val}")
        else:
            diffs.append(f"  {path}: type mismatch iOS={type(ios_val).__name__}({ios_val}) Android={type(android_val).__name__}({android_val})")
        return diffs

    if isinstance(ios_val, dict):
        all_keys = set(list(ios_val.keys()) + list(android_val.keys()))
        for key in sorted(all_keys):
            child_path = f"{path}.{key}" if path else key
            if key not in ios_val:
                diffs.append(f"  {child_path}: missing in iOS")
            elif key not in android_val:
                diffs.append(f"  {child_path}: missing in Android")
            else:
                diffs.extend(compare_values(ios_val[key], android_val[key], child_path))
    elif isinstance(ios_val, list):
        if len(ios_val) != len(android_val):
            diffs.append(f"  {path}: array length iOS={len(ios_val)} Android={len(android_val)}")
        for i in range(min(len(ios_val), len(android_val))):
            diffs.extend(compare_values(ios_val[i], android_val[i], f"{path}[{i}]"))
    elif isinstance(ios_val, float):
        if abs(ios_val - android_val) > 1e-6:
            diffs.append(f"  {path}: iOS={ios_val} Android={android_val}")
    elif isinstance(ios_val, str):
        if ios_val != android_val:
            diffs.append(f"  {path}: iOS=\"{ios_val}\" Android=\"{android_val}\"")
    elif isinstance(ios_val, bool):
        if ios_val != android_val:
            diffs.append(f"  {path}: iOS={ios_val} Android={android_val}")
    elif isinstance(ios_val, int):
        if ios_val != android_val:
            diffs.append(f"  {path}: iOS={ios_val} Android={android_val}")
    elif ios_val is None:
        if android_val is not None:
            diffs.append(f"  {path}: iOS=null Android={android_val}")

    return diffs


def compare_states(ios_path, android_path):
    """Compare two state dump files and print results."""
    ios_state = load_json(ios_path)
    android_state = load_json(android_path)

    diffs = compare_values(ios_state, android_state)

    if not diffs:
        print("PASS: All state values match")
        return 0
    else:
        print(f"FAIL: {len(diffs)} difference(s) found:")
        for diff in diffs:
            print(diff)
        return 1


def run_self_test():
    """Run self-test with dummy data to verify script works."""
    # Test 1: Matching states
    state_a = {
        "bpm": 100.0,
        "barCount": 4,
        "isPlaying": False,
        "tracks": [
            {"id": "abc", "instrumentName": "Piano", "volume": 0.8}
        ]
    }
    state_b = {
        "bpm": 100.0,
        "barCount": 4,
        "isPlaying": False,
        "tracks": [
            {"id": "abc", "instrumentName": "Piano", "volume": 0.8}
        ]
    }

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f_a:
        json.dump(state_a, f_a)
        path_a = f_a.name
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f_b:
        json.dump(state_b, f_b)
        path_b = f_b.name

    result = compare_states(path_a, path_b)
    assert result == 0, "Self-test 1 failed: matching states should PASS"

    # Test 2: Different states
    state_c = {"bpm": 120.0, "barCount": 4}

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f_c:
        json.dump(state_c, f_c)
        path_c = f_c.name

    result = compare_states(path_a, path_c)
    assert result == 1, "Self-test 2 failed: different states should FAIL"

    # Cleanup
    os.unlink(path_a)
    os.unlink(path_b)
    os.unlink(path_c)

    print("\nAll self-tests passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--test":
        sys.exit(run_self_test())
    elif len(sys.argv) == 3:
        sys.exit(compare_states(sys.argv[1], sys.argv[2]))
    else:
        print("Usage: python3 compare_state.py <ios_state.json> <android_state.json>")
        print("       python3 compare_state.py --test")
        sys.exit(1)
