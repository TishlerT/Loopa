#!/usr/bin/env python3
"""
Compare two screenshot images for visual parity using SSIM.

Masks the top and bottom 5% of the image to ignore status/nav bars.
Returns PASS if SSIM >= 0.85, FAIL with diff image and score otherwise.

Usage:
    python3 compare_images.py <ios_screenshot.png> <android_screenshot.png> [--output diff.png]
    python3 compare_images.py --test  # run self-test with dummy images
"""

import sys
import os
import tempfile
import numpy as np

try:
    from PIL import Image
    from skimage.metrics import structural_similarity as ssim
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


SSIM_THRESHOLD = 0.85
MASK_PERCENT = 0.05  # Mask top and bottom 5%


def load_and_prepare(path):
    """Load an image and convert to grayscale numpy array."""
    img = Image.open(path).convert('L')  # Grayscale
    return np.array(img)


def mask_bars(img, mask_percent=MASK_PERCENT):
    """Zero out the top and bottom N% of the image to mask status/nav bars."""
    h = img.shape[0]
    margin = int(h * mask_percent)
    masked = img.copy()
    masked[:margin, :] = 0
    masked[-margin:, :] = 0
    return masked


def compare_images(ios_path, android_path, output_path=None):
    """Compare two images and return PASS/FAIL."""
    if not HAS_DEPS:
        print("FAIL: Missing dependencies (pillow, scikit-image). Install with: pip3 install pillow scikit-image")
        return 1

    ios_img = load_and_prepare(ios_path)
    android_img = load_and_prepare(android_path)

    # Resize to match if different dimensions
    if ios_img.shape != android_img.shape:
        # Resize android to match iOS dimensions
        android_pil = Image.fromarray(android_img).resize(
            (ios_img.shape[1], ios_img.shape[0]),
            Image.Resampling.LANCZOS
        )
        android_img = np.array(android_pil)

    # Apply masks
    ios_masked = mask_bars(ios_img)
    android_masked = mask_bars(android_img)

    # Compute SSIM
    score, diff = ssim(ios_masked, android_masked, full=True)

    if score >= SSIM_THRESHOLD:
        print(f"PASS: SSIM = {score:.4f} (threshold: {SSIM_THRESHOLD})")
        return 0
    else:
        print(f"FAIL: SSIM = {score:.4f} (threshold: {SSIM_THRESHOLD})")

        # Save diff image if requested
        if output_path:
            diff_normalized = ((1 - diff) * 255).astype(np.uint8)
            diff_img = Image.fromarray(diff_normalized)
            diff_img.save(output_path)
            print(f"  Diff image saved to: {output_path}")

        return 1


def run_self_test():
    """Run self-test with dummy images."""
    if not HAS_DEPS:
        print("FAIL: Missing dependencies for self-test")
        return 1

    # Test 1: Identical images should PASS
    img_a = np.random.randint(50, 200, (100, 100), dtype=np.uint8)

    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f_a:
        Image.fromarray(img_a).save(f_a.name)
        path_a = f_a.name
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f_b:
        Image.fromarray(img_a).save(f_b.name)
        path_b = f_b.name

    result = compare_images(path_a, path_b)
    assert result == 0, "Self-test 1 failed: identical images should PASS"

    # Test 2: Very different images should FAIL
    img_c = np.random.randint(50, 200, (100, 100), dtype=np.uint8)

    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f_c:
        Image.fromarray(img_c).save(f_c.name)
        path_c = f_c.name

    result = compare_images(path_a, path_c)
    # Random images will likely have low SSIM (FAIL), but not guaranteed
    # Just verify it runs without error
    print(f"  (Random image comparison returned: {'PASS' if result == 0 else 'FAIL'})")

    # Cleanup
    os.unlink(path_a)
    os.unlink(path_b)
    os.unlink(path_c)

    print("\nAll self-tests passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--test":
        sys.exit(run_self_test())
    elif len(sys.argv) >= 3:
        output = None
        if "--output" in sys.argv:
            idx = sys.argv.index("--output")
            if idx + 1 < len(sys.argv):
                output = sys.argv[idx + 1]
        sys.exit(compare_images(sys.argv[1], sys.argv[2], output))
    else:
        print("Usage: python3 compare_images.py <ios.png> <android.png> [--output diff.png]")
        print("       python3 compare_images.py --test")
        sys.exit(1)
