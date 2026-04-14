"""
parse_upload.py
---------------
BAY-min user upload parser — Sprint 5-6 pipeline.

Handles PDFs, scanned documents, and worksheet photos uploaded by teachers
or students. Uses pdf2image to render pages as PNG images, then sends them
to Gemini Vision (gemini-2.5-flash-lite) for YAML extraction.

Why image-based:
  - Eliminates pdfplumber's tripled-char artifacts from overlapping bold fonts
  - Handles scanned PDFs and photos natively (pdfplumber cannot)
  - Handles two-column layouts without coordinate heuristics
  - Single Gemini call does both OCR and YAML structuring

Usage (Windows PowerShell):
    # Single PDF
    $env:GEMINI_API_KEY = "your_key"
    python lib/parser/parse_upload.py uploads/worksheet.pdf --out data/uploads/

    # Image file (JPG/PNG of a worksheet)
    python lib/parser/parse_upload.py uploads/notes_photo.jpg --out data/uploads/

    # Dry run (no API calls, no file writes)
    python lib/parser/parse_upload.py uploads/worksheet.pdf --dry-run

    # Preview only concept YAML (skip questions)
    python lib/parser/parse_upload.py uploads/worksheet.pdf --concept-only

Poppler requirement (Windows):
    Download from: https://github.com/oschwartz10612/poppler-windows/releases
    Extract to C:\\poppler\\
    Add C:\\poppler\\Library\\bin to PATH (or use --poppler-path flag)

Output structure:
    data/uploads/{slug}/
        concept.yaml
        questions.yaml
        pages/          (rendered PNG images, kept for debugging)
            page_001.png
            page_002.png
"""

from __future__ import annotations

import argparse
import base64
import io
import logging
import os
import re
import shutil
import sys
import time
from pathlib import Path
from typing import Optional

import yaml

# pdf2image — converts PDF pages to PIL Images
try:
    from pdf2image import convert_from_path
    from pdf2image.exceptions import (
        PDFInfoNotInstalledError,
        PDFPageCountError,
        PDFSyntaxError,
    )
    PDF2IMAGE_OK = True
except ImportError:
    PDF2IMAGE_OK = False

# Pillow — image loading / format conversion
try:
    from PIL import Image
    PILLOW_OK = True
except ImportError:
    PILLOW_OK = False

# Our shared modules
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lib.parser._gemini_prompt import (
    call_gemini,
    strip_yaml_fences,
    build_upload_concept_prompt,
    build_upload_questions_prompt,
)
from lib.parser._yaml_validator import validate_pair, ValidationError

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SUPPORTED_IMAGE_TYPES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff", ".tif"}
SUPPORTED_DOC_TYPES = {".pdf"} | SUPPORTED_IMAGE_TYPES

# Gemini free tier: 15 requests/minute
# We make 2 calls per page batch (concept + questions), so max 7 page batches/min
# With --batch-pages=3, that means ~21 pages/minute comfortably within limit
INTER_CALL_DELAY = 4.5  # seconds between API calls to stay under 15 req/min

# DPI for rendering PDF pages — 150 is fast, 200 is balanced, 300 is high quality
# 200 DPI is recommended: Gemini Vision handles it well, ~200-400KB per page PNG
DEFAULT_DPI = 200

# Max pages to send in one Gemini call (to stay within token limits)
# At 200 DPI, ~1 page ≈ 750 tokens. Flash handles up to ~1M tokens but
# we keep batches small for reliability and to reduce rate-limit impact.
DEFAULT_BATCH_PAGES = 3
DEFAULT_GEMINI_MAX_RETRIES = 5
DEFAULT_GEMINI_RETRY_DELAY = 10.0
DEFAULT_GEMINI_MAX_RETRY_DELAY = 120.0


# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------
def image_to_b64(img: "Image.Image", format: str = "PNG") -> str:
    """Convert a PIL Image to base64-encoded bytes string."""
    buf = io.BytesIO()
    img.save(buf, format=format, optimize=True)
    return base64.b64encode(buf.getvalue()).decode("utf-8")


def load_image_file(path: Path) -> "Image.Image":
    """Load an image file from disk as a PIL Image."""
    if not PILLOW_OK:
        raise RuntimeError("Pillow is not installed. Run: pip install pillow")
    img = Image.open(path)
    # Convert to RGB to ensure consistent PNG encoding
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGB")
    return img


def render_pdf_pages(
    pdf_path: Path,
    dpi: int = DEFAULT_DPI,
    poppler_path: Optional[str] = None,
    max_pages: Optional[int] = None,
) -> list["Image.Image"]:
    """
    Render all pages of a PDF as PIL Images.

    Args:
        pdf_path:     Path to the PDF file.
        dpi:          Resolution for rendering (default 200).
        poppler_path: Path to poppler bin directory (Windows only).
                      If None, uses PATH.
        max_pages:    If set, only render this many pages (for testing).

    Returns:
        List of PIL Images, one per page.
    """
    if not PDF2IMAGE_OK:
        raise RuntimeError(
            "pdf2image is not installed. Run: pip install pdf2image\n"
            "Also requires poppler. On Windows: download from "
            "https://github.com/oschwartz10612/poppler-windows/releases"
        )
    if not PILLOW_OK:
        raise RuntimeError("Pillow is not installed. Run: pip install pillow")

    kwargs = {"dpi": dpi, "fmt": "PNG"}
    if poppler_path:
        kwargs["poppler_path"] = poppler_path
    if max_pages:
        kwargs["last_page"] = max_pages

    log.info("Rendering PDF pages at %d DPI: %s", dpi, pdf_path.name)
    try:
        pages = convert_from_path(str(pdf_path), **kwargs)
        log.info("  Rendered %d page(s)", len(pages))
        return pages
    except PDFInfoNotInstalledError:
        raise RuntimeError(
            "Poppler not found. On Windows:\n"
            "  1. Download from https://github.com/oschwartz10612/poppler-windows/releases\n"
            "  2. Extract to C:\\poppler\\\n"
            "  3. Add C:\\poppler\\Library\\bin to your PATH\n"
            "  OR use --poppler-path C:\\poppler\\Library\\bin"
        )
    except (PDFPageCountError, PDFSyntaxError) as exc:
        raise RuntimeError(f"PDF parsing error: {exc}") from exc


def batch_images(images: list, batch_size: int) -> list[list]:
    """Split a list of images into batches of batch_size."""
    return [images[i:i + batch_size] for i in range(0, len(images), batch_size)]


# ---------------------------------------------------------------------------
# YAML merging helpers (for multi-batch documents)
# ---------------------------------------------------------------------------
def merge_concept_yamls(docs: list[dict]) -> dict:
    """
    Merge multiple concept YAML dicts (from multi-batch PDFs) into one.
    Uses first doc's metadata, concatenates text/concepts/examples.
    """
    if not docs:
        return {}
    if len(docs) == 1:
        return docs[0]

    merged = dict(docs[0])  # Start with first batch's metadata
    ic_parts = []
    all_concepts = []
    all_examples = []

    for doc in docs:
        ic = doc.get("instructional_content", {})
        if isinstance(ic, dict):
            text = ic.get("text", "").strip()
            if text:
                ic_parts.append(text)
            concepts = ic.get("concepts", [])
            if isinstance(concepts, list):
                all_concepts.extend(concepts)
            example = ic.get("example_walkthrough", "").strip()
            if example:
                all_examples.append(example)

    # Deduplicate concepts while preserving order
    seen = set()
    unique_concepts = []
    for c in all_concepts:
        if c not in seen:
            seen.add(c)
            unique_concepts.append(c)

    merged["instructional_content"] = {
        "text": "\n\n".join(ic_parts),
        "concepts": unique_concepts,
        "example_walkthrough": "\n\n".join(all_examples),
    }

    # cite_only: true only if ALL batches are cite_only
    merged["cite_only"] = all(d.get("cite_only", False) for d in docs)

    # Merge standard_tags
    all_tags = []
    for doc in docs:
        tags = doc.get("standard_tags", [])
        if isinstance(tags, list):
            all_tags.extend(tags)
    merged["standard_tags"] = list(dict.fromkeys(all_tags))  # dedup, preserve order

    return merged


def merge_questions_yamls(docs: list[dict]) -> dict:
    """
    Merge multiple questions YAML dicts from multi-batch processing.
    Concatenates all question lists, renumbers IDs to avoid duplicates.
    """
    if not docs:
        return {}
    if len(docs) == 1:
        return docs[0]

    merged = {"lesson_id": docs[0].get("lesson_id", ""), "title": docs[0].get("title", "")}
    sections = ["guided", "independent", "word_problems"]
    counters = {s: 1 for s in sections}
    section_suffix = {"guided": "g", "independent": "i", "word_problems": "w"}

    for section in sections:
        questions = []
        for doc in docs:
            for q in doc.get(section, []):
                if not isinstance(q, dict):
                    continue
                q = dict(q)  # copy to avoid mutating original
                # Re-ID to avoid duplicates across batches
                lesson_id = merged["lesson_id"].replace(".", "_")
                suffix = section_suffix[section]
                q["id"] = f"q_{lesson_id}_{suffix}{counters[section]}"
                counters[section] += 1
                questions.append(q)
        merged[section] = questions

    return merged


# ---------------------------------------------------------------------------
# Slug helper
# ---------------------------------------------------------------------------
def filename_to_slug(filename: str) -> str:
    """Convert a filename to a safe slug for use as a directory name and lesson_id."""
    stem = Path(filename).stem
    slug = re.sub(r"[^a-z0-9]+", "_", stem.lower()).strip("_")
    return slug or "upload"


def _get_retry_delay_seconds(resp, attempt: int, delay: float) -> float:
    """Honor Retry-After when present, otherwise use exponential backoff."""
    retry_after = resp.headers.get("Retry-After")
    if retry_after:
        try:
            return max(float(retry_after), delay)
        except ValueError:
            pass

    capped_delay = min(delay, DEFAULT_GEMINI_MAX_RETRY_DELAY)
    if attempt >= 4:
        capped_delay = min(capped_delay + 10.0, DEFAULT_GEMINI_MAX_RETRY_DELAY)
    return capped_delay


def _is_quota_exhausted_response(resp) -> bool:
    """Return True only for obvious Gemini quota exhaustion responses."""
    if getattr(resp, "status_code", None) != 429:
        return False

    body_text = ""
    try:
        body_text = (resp.text or "")[:2000]
    except Exception:
        body_text = ""

    body_lower = body_text.lower()
    if "generate_content_free_tier_requests" in body_lower:
        return True
    if "check your plan and billing details" in body_lower:
        return True
    if "resource_exhausted" in body_lower and "quota exceeded" in body_lower:
        return True

    try:
        error = (resp.json() or {}).get("error", {})
    except ValueError:
        return False

    status = str(error.get("status", "")).upper()
    message = str(error.get("message", "")).lower()
    if status == "RESOURCE_EXHAUSTED":
        return (
            "quota exceeded" in message
            or "generate_content_free_tier_requests" in message
            or "check your plan and billing details" in message
        )
    return False


def _clean_gemini_yaml_response(text: str) -> str:
    """Normalize Gemini YAML output by removing stray markdown fence lines."""
    clean = strip_yaml_fences(text)
    clean = re.sub(r"(?m)^\s*```(?:yaml)?\s*$", "", clean, flags=re.IGNORECASE)
    lines = clean.splitlines()
    expected_top_level_keys = (
        "lesson_id",
        "title",
        "cite_only",
        "citation",
        "standard_tags",
        "instructional_content",
        "guided",
        "independent",
        "word_problems",
    )

    start_idx = 0
    for idx, line in enumerate(lines):
        if re.match(rf"^\s*(?:{'|'.join(expected_top_level_keys)})\s*:", line):
            start_idx = idx
            break

    lines = lines[start_idx:]

    end_idx = len(lines)
    for idx, line in enumerate(lines):
        if re.match(r"^\s*questions\.yaml\s*:\s*$", line, flags=re.IGNORECASE):
            end_idx = idx
            break
    lines = lines[:end_idx]

    normalized_lines = []
    for line in lines:
        normalized = re.sub(
            rf"^\s+((?:{'|'.join(expected_top_level_keys)})\s*:)",
            r"\1",
            line,
        )
        normalized_lines.append(normalized)

    clean = "\n".join(normalized_lines)
    return clean.strip()


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------
def process_upload(
    input_path: Path,
    out_dir: Path,
    *,
    dpi: int = DEFAULT_DPI,
    batch_pages: int = DEFAULT_BATCH_PAGES,
    poppler_path: Optional[str] = None,
    dry_run: bool = False,
    concept_only: bool = False,
    save_pages: bool = False,
    api_key: Optional[str] = None,
    model: str = "gemini-2.5-flash-lite",
    max_pages: Optional[int] = None,
) -> tuple[dict, dict]:
    """
    Full upload processing pipeline: file → YAML concept + questions.

    Args:
        input_path:   Path to input PDF, JPG, PNG, etc.
        out_dir:      Directory to write concept.yaml + questions.yaml.
        dpi:          PDF rendering resolution.
        batch_pages:  Number of pages per Gemini API call.
        poppler_path: Poppler bin path for Windows.
        dry_run:      If True, skip API calls and file writes.
        concept_only: If True, skip questions.yaml generation.
        save_pages:   If True, save rendered PNG pages to out_dir/pages/.
        api_key:      Gemini API key (falls back to GEMINI_API_KEY env var).
        model:        Gemini model name.
        max_pages:    Limit pages processed (for testing).

    Returns:
        Tuple of (concept_dict, questions_dict). Empty dicts in dry_run mode.
    """
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    suffix = input_path.suffix.lower()
    if suffix not in SUPPORTED_DOC_TYPES:
        raise ValueError(
            f"Unsupported file type '{suffix}'. "
            f"Supported: {', '.join(sorted(SUPPORTED_DOC_TYPES))}"
        )

    slug = filename_to_slug(input_path.name)
    lesson_out = out_dir / slug
    pages_dir = lesson_out / "pages"

    log.info("=" * 60)
    log.info("BAY-min Upload Parser")
    log.info("  Input:   %s", input_path.name)
    log.info("  Slug:    %s", slug)
    log.info("  Out dir: %s", lesson_out)
    if dry_run:
        log.info("  Mode:    DRY RUN (no API calls, no writes)")
    log.info("=" * 60)

    # ----- Step 1: Load images -----
    if suffix == ".pdf":
        pages = render_pdf_pages(input_path, dpi=dpi, poppler_path=poppler_path, max_pages=max_pages)
    else:
        log.info("Loading image file: %s", input_path.name)
        pages = [load_image_file(input_path)]
        if max_pages:
            pages = pages[:max_pages]

    if max_pages and len(pages) > max_pages:
        pages = pages[:max_pages]
        log.info("  (limited to %d page(s) for testing)", max_pages)

    log.info("Total pages to process: %d", len(pages))

    # ----- Step 2: Optionally save page images -----
    if save_pages and not dry_run:
        pages_dir.mkdir(parents=True, exist_ok=True)
        for i, page in enumerate(pages, 1):
            page_path = pages_dir / f"page_{i:03d}.png"
            page.save(str(page_path), "PNG")
        log.info("Saved %d page image(s) to %s", len(pages), pages_dir)

    if dry_run:
        log.info("DRY RUN: skipping Gemini API calls.")
        log.info("  Would process %d page(s) in batches of %d", len(pages), batch_pages)
        log.info("  Total API calls (concept): %d", len(list(batch_images(pages, batch_pages))))
        if not concept_only:
            log.info("  Total API calls (questions): %d", len(list(batch_images(pages, batch_pages))))
        log.info("  Estimated tokens (rough): %d", len(pages) * 750)
        return {}, {}

    # ----- Step 3: Build base64 for multi-image Gemini calls -----
    # Strategy: send all pages as inline_data in a single call if <= batch_pages,
    # otherwise split into batches and merge results.
    batches = batch_images(pages, batch_pages)
    filename = input_path.name

    # ----- Step 4: Concept extraction -----
    log.info("--- Concept extraction (%d batch(es)) ---", len(batches))
    concept_docs = []

    for batch_idx, batch in enumerate(batches, 1):
        log.info("  Batch %d/%d (%d page(s))...", batch_idx, len(batches), len(batch))

        # Build multi-image payload: first image triggers Vision mode
        # Additional images included as separate inline_data parts
        prompt = build_upload_concept_prompt(filename)

        # For multi-page batches, we send the first image to the standard
        # call_gemini() and include subsequent images in the prompt text
        # (Gemini Flash supports up to 16 images per request via REST)
        primary_image_b64 = image_to_b64(batch[0])

        # Additional pages: send as separate inline parts via extended call
        additional_b64s = [image_to_b64(p) for p in batch[1:]]

        text_result = _call_gemini_multiimage(
            prompt=prompt,
            primary_b64=primary_image_b64,
            additional_b64s=additional_b64s,
            api_key=api_key,
            model=model,
        )

        try:
            clean = _clean_gemini_yaml_response(text_result)
            doc = yaml.safe_load(clean)
            if not isinstance(doc, dict):
                raise ValueError(f"Expected dict, got {type(doc)}")
            # Set lesson_id from slug if Gemini didn't
            if not doc.get("lesson_id"):
                doc["lesson_id"] = f"upload_{slug}"
            concept_docs.append(doc)
            log.info("    OK — lesson_id: %s", doc.get("lesson_id"))
        except yaml.YAMLError as exc:
            log.error("    YAML parse error in batch %d: %s", batch_idx, exc)
            log.error("    Cleaned response snippet: %r", clean[:1200])
            raise RuntimeError(f"Gemini returned invalid YAML (concept batch {batch_idx})") from exc

        if batch_idx < len(batches):
            log.info("    Waiting %.1fs (rate limit)...", INTER_CALL_DELAY)
            time.sleep(INTER_CALL_DELAY)

    concept_doc = merge_concept_yamls(concept_docs)

    # ----- Step 5: Questions extraction -----
    questions_doc = {}
    if not concept_only:
        log.info("--- Question extraction (%d batch(es)) ---", len(batches))
        question_docs = []

        for batch_idx, batch in enumerate(batches, 1):
            log.info("  Batch %d/%d (%d page(s))...", batch_idx, len(batches), len(batch))

            prompt = build_upload_questions_prompt(filename)
            primary_image_b64 = image_to_b64(batch[0])
            additional_b64s = [image_to_b64(p) for p in batch[1:]]

            # Rate limit: always wait before question calls
            log.info("    Waiting %.1fs (rate limit)...", INTER_CALL_DELAY)
            time.sleep(INTER_CALL_DELAY)

            text_result = _call_gemini_multiimage(
                prompt=prompt,
                primary_b64=primary_image_b64,
                additional_b64s=additional_b64s,
                api_key=api_key,
                model=model,
            )

            try:
                clean = _clean_gemini_yaml_response(text_result)
                doc = yaml.safe_load(clean)
                if not isinstance(doc, dict):
                    raise ValueError(f"Expected dict, got {type(doc)}")
                if not doc.get("lesson_id"):
                    doc["lesson_id"] = f"upload_{slug}"
                if not doc.get("title"):
                    doc["title"] = concept_doc.get("title", filename)
                question_docs.append(doc)
                guided_count = len(doc.get("guided", []))
                indep_count = len(doc.get("independent", []))
                log.info("    OK — %dg + %di questions", guided_count, indep_count)
            except yaml.YAMLError as exc:
                log.error("    YAML parse error in batch %d: %s", batch_idx, exc)
                log.error("    Cleaned response snippet: %r", clean[:1200])
                raise RuntimeError(
                    f"Gemini returned invalid YAML (questions batch {batch_idx})"
                ) from exc

        questions_doc = merge_questions_yamls(question_docs)

    # ----- Step 6: Validate -----
    log.info("--- Validating output ---")
    try:
        if questions_doc:
            result = validate_pair(concept_doc, questions_doc)
        else:
            from lib.parser._yaml_validator import validate_concept
            result = validate_concept(concept_doc)

        if result.warnings:
            for w in result.warnings:
                log.warning("  WARN: %s", w)
        if result.valid:
            log.info("  Validation PASSED")
        else:
            log.error("  Validation FAILED:")
            for e in result.errors:
                log.error("    - %s", e)
            # Don't hard-fail on validation — write output and let user fix
            log.warning("  Writing output anyway; fix issues before Firestore ingestion.")
    except Exception as exc:
        log.warning("  Validation error (non-fatal): %s", exc)

    # ----- Step 7: Write YAML output -----
    lesson_out.mkdir(parents=True, exist_ok=True)

    concept_path = lesson_out / "concept.yaml"
    questions_path = lesson_out / "questions.yaml"

    with open(concept_path, "w", encoding="utf-8") as f:
        yaml.dump(concept_doc, f, allow_unicode=True, sort_keys=False, width=120)
    log.info("Wrote: %s", concept_path)

    if questions_doc:
        with open(questions_path, "w", encoding="utf-8") as f:
            yaml.dump(questions_doc, f, allow_unicode=True, sort_keys=False, width=120)
        log.info("Wrote: %s", questions_path)

    log.info("=" * 60)
    log.info("Done! Output: %s", lesson_out)
    log.info("=" * 60)

    return concept_doc, questions_doc


def _call_gemini_multiimage(
    prompt: str,
    primary_b64: str,
    additional_b64s: list[str],
    api_key: Optional[str],
    model: str,
) -> str:
    """
    Call Gemini REST API with multiple images in a single request.
    The REST API supports multiple inline_data parts in one content block.
    """
    import random
    import requests as req
    import os

    key = api_key or os.environ.get("GEMINI_API_KEY")
    if not key:
        raise RuntimeError(
            "No Gemini API key. Set GEMINI_API_KEY or pass --api-key."
        )

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models"
        f"/{model}:generateContent?key={key}"
    )

    parts = []
    # Primary image
    parts.append({"inline_data": {"mime_type": "image/png", "data": primary_b64}})
    # Additional images
    for b64 in additional_b64s:
        parts.append({"inline_data": {"mime_type": "image/png", "data": b64}})
    # Text prompt last
    parts.append({"text": prompt})

    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {"temperature": 0.2, "maxOutputTokens": 4096},
    }

    max_retries = int(os.environ.get("GEMINI_MAX_RETRIES", DEFAULT_GEMINI_MAX_RETRIES))
    delay = float(os.environ.get("GEMINI_RETRY_DELAY", DEFAULT_GEMINI_RETRY_DELAY))
    for attempt in range(1, max_retries + 1):
        resp = req.post(url, json=payload, timeout=120)
        if resp.status_code == 429 and _is_quota_exhausted_response(resp):
            raise RuntimeError(f"Gemini quota exhausted {resp.status_code}: {resp.text[:500]}")
        if resp.status_code in (429, 503):
            if attempt == max_retries:
                raise RuntimeError(f"Gemini API error {resp.status_code}: {resp.text[:500]}")
            wait_seconds = _get_retry_delay_seconds(resp, attempt, delay)
            wait_seconds = min(
                wait_seconds + random.uniform(0.0, 1.0),
                DEFAULT_GEMINI_MAX_RETRY_DELAY,
            )
            log.warning(
                "Gemini overloaded (attempt %d/%d). Waiting %.1fs...",
                attempt,
                max_retries,
                wait_seconds,
            )
            time.sleep(wait_seconds)
            delay = min(wait_seconds * 2, DEFAULT_GEMINI_MAX_RETRY_DELAY)
            continue
        if resp.status_code != 200:
            raise RuntimeError(f"Gemini API error {resp.status_code}: {resp.text[:500]}")

        data = resp.json()
        candidates = data.get("candidates", [])
        if not candidates:
            raise RuntimeError(f"No candidates in Gemini response: {data}")
        content = candidates[0].get("content", {})
        text = " ".join(p.get("text", "") for p in content.get("parts", [])).strip()
        if not text:
            raise RuntimeError(f"Empty response from Gemini: {data}")
        return text

    raise RuntimeError(f"Gemini call failed after {max_retries} attempts.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="BAY-min upload parser: PDF/image → concept.yaml + questions.yaml",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples (Windows PowerShell):
  # Parse a worksheet PDF
  $env:GEMINI_API_KEY = "your_key_here"
  python lib/parser/parse_upload.py uploads/worksheet.pdf --out data/uploads/

  # Parse a photo of handwritten notes
  python lib/parser/parse_upload.py uploads/notes_photo.jpg --out data/uploads/

  # Dry run to check page count and token estimate
  python lib/parser/parse_upload.py uploads/worksheet.pdf --dry-run

  # Limit to first 5 pages (fast test)
  python lib/parser/parse_upload.py uploads/worksheet.pdf --max-pages 5

  # Save rendered page images for debugging
  python lib/parser/parse_upload.py uploads/worksheet.pdf --save-pages

  # Windows with explicit poppler path
  python lib/parser/parse_upload.py uploads/worksheet.pdf --poppler-path "C:\\poppler\\Library\\bin"
        """,
    )
    parser.add_argument("input", type=Path, help="Input PDF, JPG, PNG, or WEBP file")
    parser.add_argument("--out", type=Path, default=Path("data/uploads"),
                        help="Output base directory (default: data/uploads/)")
    parser.add_argument("--dpi", type=int, default=DEFAULT_DPI,
                        help=f"PDF rendering DPI (default: {DEFAULT_DPI})")
    parser.add_argument("--batch-pages", type=int, default=DEFAULT_BATCH_PAGES,
                        help=f"Pages per Gemini API call (default: {DEFAULT_BATCH_PAGES})")
    parser.add_argument("--poppler-path", type=str, default=None,
                        help='Windows poppler bin path (e.g. "C:\\poppler\\Library\\bin")')
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview processing plan without making API calls")
    parser.add_argument("--concept-only", action="store_true",
                        help="Only generate concept.yaml (skip questions.yaml)")
    parser.add_argument("--save-pages", action="store_true",
                        help="Save rendered PNG pages to <out>/<slug>/pages/ for debugging")
    parser.add_argument("--max-pages", type=int, default=None,
                        help="Limit pages processed (useful for testing)")
    parser.add_argument("--api-key", type=str, default=None,
                        help="Gemini API key (default: $env:GEMINI_API_KEY)")
    parser.add_argument("--model", type=str, default="gemini-2.5-flash-lite",
                        help="Gemini model name (default: gemini-2.5-flash-lite)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Enable debug logging")

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        process_upload(
            input_path=args.input,
            out_dir=args.out,
            dpi=args.dpi,
            batch_pages=args.batch_pages,
            poppler_path=args.poppler_path,
            dry_run=args.dry_run,
            concept_only=args.concept_only,
            save_pages=args.save_pages,
            api_key=args.api_key,
            model=args.model,
            max_pages=args.max_pages,
        )
    except FileNotFoundError as exc:
        log.error("File not found: %s", exc)
        sys.exit(1)
    except RuntimeError as exc:
        log.error("Pipeline error: %s", exc)
        sys.exit(1)
    except KeyboardInterrupt:
        log.info("Interrupted.")
        sys.exit(0)


if __name__ == "__main__":
    main()
