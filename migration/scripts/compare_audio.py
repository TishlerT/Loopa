#!/usr/bin/env python3
"""
Compare two audio exports (M4A) for parity verification.

Currently a placeholder — will compare:
- File duration
- Onset timing (note attack alignment)
- RMS energy profile

Usage:
    python3 compare_audio.py <ios_export.m4a> <android_export.m4a>
    python3 compare_audio.py --test  # run self-test
"""

import sys
import os
import json


def compare_audio(ios_path, android_path):
    """Compare two audio files. Currently a duration/size placeholder."""
    if not os.path.exists(ios_path):
        print(f"FAIL: iOS audio file not found: {ios_path}")
        return 1
    if not os.path.exists(android_path):
        print(f"FAIL: Android audio file not found: {android_path}")
        return 1

    ios_size = os.path.getsize(ios_path)
    android_size = os.path.getsize(android_path)

    # Basic size comparison — within 50% as a sanity check
    if ios_size == 0 or android_size == 0:
        print("FAIL: One or both audio files are empty")
        return 1

    size_ratio = min(ios_size, android_size) / max(ios_size, android_size)
    if size_ratio < 0.5:
        print(f"FAIL: File sizes differ significantly (iOS={ios_size} bytes, Android={android_size} bytes, ratio={size_ratio:.2f})")
        return 1

    print(f"PASS: Audio files exist and have comparable sizes (iOS={ios_size} bytes, Android={android_size} bytes, ratio={size_ratio:.2f})")
    print("  NOTE: Full onset/timing/RMS comparison requires ffmpeg/librosa (not yet implemented)")
    return 0


def run_self_test():
    """Run self-test to verify script works."""
    import tempfile

    # Test 1: Two files of similar size should PASS
    with tempfile.NamedTemporaryFile(suffix='.m4a', delete=False) as f_a:
        f_a.write(b'\x00' * 1000)
        path_a = f_a.name
    with tempfile.NamedTemporaryFile(suffix='.m4a', delete=False) as f_b:
        f_b.write(b'\x00' * 1200)
        path_b = f_b.name

    result = compare_audio(path_a, path_b)
    assert result == 0, "Self-test 1 failed: similar-size files should PASS"

    # Test 2: Very different sizes should FAIL
    with tempfile.NamedTemporaryFile(suffix='.m4a', delete=False) as f_c:
        f_c.write(b'\x00' * 100)
        path_c = f_c.name

    result = compare_audio(path_a, path_c)
    assert result == 1, "Self-test 2 failed: very different sizes should FAIL"

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
        sys.exit(compare_audio(sys.argv[1], sys.argv[2]))
    else:
        print("Usage: python3 compare_audio.py <ios_export.m4a> <android_export.m4a>")
        print("       python3 compare_audio.py --test")
        sys.exit(1)
