#!/usr/bin/env python3
"""
parse_chapter.py — GO Math PDF → Reachy Mini YAML Pipeline
============================================================
EGR302 Junior Design | Reachy Mini (BAY-min) Tutoring Robot
Role owner: Haneul (data pipelines & module/question design)

Strategy: Hybrid
  1. pdfplumber  → extracts raw text per page (deterministic, free)
  2. Claude API  → structures raw text into concept.yaml + questions.yaml
                   using the v1.1 schema as the system prompt

Usage:
  python parse_chapter.py \\
      --pdf  path/to/gomath_g4.pdf \\
      --pages 5-38 \\
      --chapter 1 \\
      --grade 4 \\
      --output ./chapter_01

  # Dry-run (extraction only, no API calls, prints raw text per lesson):
  python parse_chapter.py --pdf gomath_g4.pdf --pages 5-38 --chapter 1 --grade 4 --dry-run

Requirements:
  pip install pdfplumber anthropic pyyaml

Environment:
  ANTHROPIC_API_KEY  — must be set before running
"""

import os
import re
import sys
import json
import argparse
import logging
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

# ---------------------------------------------------------------------------
# Graceful import handling so the file can be read / syntax-checked without
# the packages installed.
# ---------------------------------------------------------------------------
try:
    import pdfplumber
except ImportError:
    pdfplumber = None  # type: ignore

try:
    import anthropic
except ImportError:
    anthropic = None  # type: ignore

try:
    import yaml
except ImportError:
    yaml = None  # type: ignore


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)
log = logging.getLogger("parse_chapter")

DEFAULT_OUTPUT_ROOT = Path(
    r"D:\Users\haneu\Desktop\CBU\CBU_Courses_S6\EGR302\Robot-Tutor\data\mnt\user-data\outputs"
)


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------
@dataclass
class LessonChunk:
    """Raw text extracted for a single lesson."""
    lesson_num: str          # e.g. "1.1"
    title: str               # e.g. "Model Place Value Relationships"
    pages: list[int]         # 1-indexed page numbers from the PDF
    raw_text: str            # concatenated pdfplumber output
    has_tables: bool = False # True if pdfplumber found tables on any page


@dataclass
class ParseResult:
    """Holds the two YAML strings produced for one lesson."""
    lesson_num: str
    lesson_folder: str       # e.g. "lesson_1_1_model_place_value"
    concept_yaml: str
    questions_yaml: str
    warnings: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Stage 1 — PDF extraction (pdfplumber)
# ---------------------------------------------------------------------------

# GO Math heading patterns (tested against Chapters 1–3 of Grade 4 CA edition)
_LESSON_HEADING = re.compile(
    r"(?:^|\n)\s*Lesson\s+(\d+\.\d+)\s*\n\s*(.+?)(?=\n)",
    re.IGNORECASE,
)

_VISUAL_KEYWORDS = re.compile(
    r"\b(number line|diagram|bar model|tape diagram|place.value chart"
    r"|base.ten block|pictograph|table|graph|figure|model|draw)\b",
    re.IGNORECASE,
)

_DIFFICULTY_KEYWORDS = re.compile(
    r"\b(Go Deeper|Think Smarter\+?|Mathematical Practice|Unlock the Problem"
    r"|Try This|Share and Show|On Your Own|Problem Solving)\b",
    re.IGNORECASE,
)


def extract_pages(pdf_path: str, start_page: int, end_page: int) -> dict[int, str]:
    """
    Extract text from a page range using pdfplumber.
    Pages are 1-indexed (matching the printed page numbers you pass via CLI).
    Returns {page_number: text}.
    """
    if pdfplumber is None:
        raise ImportError("pdfplumber is not installed. Run: pip install pdfplumber")

    result: dict[int, str] = {}
    with pdfplumber.open(pdf_path) as pdf:
        total = len(pdf.pages)
        for page_num in range(start_page, end_page + 1):
            # pdfplumber uses 0-based indexing internally
            pdf_idx = page_num - 1
            if pdf_idx >= total:
                log.warning("Page %d exceeds PDF length (%d pages). Stopping.", page_num, total)
                break
            page = pdf.pages[pdf_idx]

            # extract_text(layout=True) preserves column ordering better than default
            text = page.extract_text(layout=True) or ""

            # Also extract any tables and append as tab-separated rows so
            # Claude can see the data even if pdfplumber linearises it oddly
            tables = page.extract_tables()
            if tables:
                for tbl in tables:
                    if tbl:
                        text += "\n[TABLE]\n"
                        for row in tbl:
                            text += "\t".join(str(c) if c else "" for c in row) + "\n"
                        text += "[/TABLE]\n"

            result[page_num] = text

    return result


def detect_lesson_boundaries(pages: dict[int, str]) -> list[tuple[str, str, int]]:
    """
    Scan page texts for lesson headings.
    Returns list of (lesson_num, title, start_page) sorted by start_page.
    e.g. [("1.1", "Model Place Value Relationships", 5), ...]
    """
    found: list[tuple[str, str, int]] = []
    for page_num, text in sorted(pages.items()):
        for m in _LESSON_HEADING.finditer(text):
            lesson_num = m.group(1)
            title = m.group(2).strip()
            # Deduplicate: same lesson can appear in header on multiple pages
            if not found or found[-1][0] != lesson_num:
                found.append((lesson_num, title, page_num))
                log.info("  Detected Lesson %s — '%s' at page %d", lesson_num, title, page_num)
    return found


def build_lesson_chunks(
    pages: dict[int, str],
    boundaries: list[tuple[str, str, int]],
) -> list[LessonChunk]:
    """
    Slice page texts into per-lesson chunks using the detected boundaries.
    The last lesson runs to the end of the extracted page range.
    """
    chunks: list[LessonChunk] = []
    page_nums = sorted(pages.keys())

    for i, (lesson_num, title, start_page) in enumerate(boundaries):
        end_page = (
            boundaries[i + 1][2] - 1
            if i + 1 < len(boundaries)
            else page_nums[-1]
        )
        lesson_pages = [p for p in page_nums if start_page <= p <= end_page]
        combined_text = "\n\n--- PAGE %d ---\n\n".join(
            pages[p] for p in lesson_pages
        )
        # Inject page numbers so Claude knows which page each block came from
        parts = []
        for p in lesson_pages:
            parts.append(f"--- PAGE {p} ---\n{pages[p]}")
        combined_text = "\n\n".join(parts)

        has_tables = any("[TABLE]" in pages[p] for p in lesson_pages)

        chunks.append(LessonChunk(
            lesson_num=lesson_num,
            title=title,
            pages=lesson_pages,
            raw_text=combined_text,
            has_tables=has_tables,
        ))

    return chunks


# ---------------------------------------------------------------------------
# Stage 2 — Claude API structuring
# ---------------------------------------------------------------------------

# The system prompt encodes the full v1.1 schema so Claude produces
# schema-compliant YAML without needing examples in every user message.
_SYSTEM_PROMPT = """You are a structured data extraction assistant for the Reachy Mini (BAY-min) educational tutoring robot.
Your job is to convert raw text extracted from GO Math elementary textbook PDFs into YAML files that strictly follow the schema below.

## OUTPUT FORMAT
You must return EXACTLY two YAML documents separated by the delimiter:
    ---CONCEPT---
    <concept.yaml content>
    ---QUESTIONS---
    <questions.yaml content>

Do not include any other text, explanation, or markdown fences.

## SCHEMA v1.1

### concept.yaml
```yaml
lesson_id: "math_g{grade}_ch{chapter}_l{lesson_flat}"   # e.g. math_g4_ch1_l1
subject: math
grade: <int>
unit: <int>                  # same as chapter for GO Math
chapter: <int>
lesson: <int>
title: "<string>"
essential_question: "<string>"
standards: ["<4.NBT.x>"]    # ALWAYS a list, even for one entry
mathematical_practices: ["MP.x", ...]

citation:
  textbook: "GO Math Grade {grade} California (Houghton Mifflin Harcourt)"
  chapter: <int>
  lesson: <int>
  pages: [<int>, ...]

has_visual: <bool>
visual_handling: cite_only   # only present when has_visual: true
visual_description: >        # only present when has_visual: true
  <Plain-English description of what the visual contains>

concepts:
  - id: c1
    term: "<term>"
    definition: >
      <definition>
    example: "<example>"

worked_examples:
  - id: we1
    title: "<title>"
    has_visual: <bool>
    visual_handling: cite_only      # only when has_visual: true
    visual_description: "<string>"  # only when has_visual: true
    steps:
      - "<step 1>"
      - "<step 2>"
    answer: "<answer>"
    citation_page: <int>
```

### questions.yaml
```yaml
# PENDING DECISION: Josh/Kip to confirm whether questions should be
# a subcollection (lessons/{lesson_id}/questions/{question_id}) in Firestore
# or remain as an array inside the lesson document.
# This affects ingestion script design — resolve before seeding.

lesson_id: "math_g{grade}_ch{chapter}_l{lesson_flat}"
subject: math
grade: <int>
unit: <int>
chapter: <int>
lesson: <int>
title: "<string>"
standards: ["<4.NBT.x>"]

citation:
  textbook: "GO Math Grade {grade} California (Houghton Mifflin Harcourt)"
  chapter: <int>
  lesson: <int>
  pages: [<int>, ...]

questions:
  guided:
    - id: q_g1
      type: <question_type>    # see type taxonomy below
      has_visual: <bool>
      visual_handling: cite_only      # only when has_visual: true
      visual_description: "<string>"  # only when has_visual: true
      prompt: >
        <question text>
      answer: "<answer>"
      citation_page: <int>
      difficulty: <difficulty_tag>    # only when explicitly marked
      items:                          # only for true_false_set / multiple_select
        - statement: "<text>"
          answer: "<True|False>"

  independent:
    - id: q_i1
      ...

  word_problems:
    - id: q_w1
      ...
```

## QUESTION TYPE TAXONOMY
find_value, compare, compare_values, order, conversion, round, rename,
rename_chart, addition, subtraction, addition_with_estimate,
subtraction_with_estimate, subtraction_grid, algebra_fill, algebra_property,
word_problem, word_problem_diagram, error_analysis, true_false_set,
multiple_select, short_answer, fill_in, reasonableness, benchmark_estimation,
copy_and_solve

## DIFFICULTY TAGS (only add when the textbook explicitly marks the question)
deeper, think_smarter, think_smarter_plus, mathematical_practice

## VISUAL DETECTION RULES
Set has_visual: true on a question or worked_example when:
- The prompt references a number line, diagram, bar model, tape diagram,
  place-value chart, base-ten block, table, graph, quick picture, or benchmark image
- The textbook instructs "Use the [visual] to help" or "Draw a [visual]"
- The question requires reading data from a figure or table embedded on the page

## SECTION MAPPING
GO Math sections map to YAML questions blocks as follows:
- "Share and Show" / "Guided Practice" → guided
- "On Your Own" / "Independent Practice"  → independent
- "Problem Solving" / "H.O.T." / word problems → word_problems

## HANDLING UNCERTAINTY
If you cannot confidently extract a field, write:
  field_name: "# TODO: could not extract — review page <n>"
Never fabricate content. It is better to leave a TODO than to invent text.

## IDs
- Concepts:        c1, c2, c3 ...
- Worked examples: we1, we2 ...
- Guided:          q_g1, q_g2 ...
- Independent:     q_i1, q_i2 ...
- Word problems:   q_w1, q_w2 ...
"""


def _make_user_message(chunk: LessonChunk, grade: int, chapter: int) -> str:
    """Build the user-turn message sent to the Claude API for one lesson."""
    return f"""Extract structured YAML for the following GO Math lesson.

Grade: {grade}
Chapter: {chapter}
Lesson: {chunk.lesson_num}
Detected title: {chunk.title}
Pages in this lesson: {chunk.pages}
Contains tables: {chunk.has_tables}

Raw extracted text (page markers included):
===BEGIN TEXT===
{chunk.raw_text}
===END TEXT===

Return EXACTLY the two YAML documents in the format specified:
---CONCEPT---
<concept.yaml>
---QUESTIONS---
<questions.yaml>
"""


def call_claude(chunk: LessonChunk, grade: int, chapter: int, client) -> tuple[str, str]:
    """
    Call the Claude API and return (concept_yaml_str, questions_yaml_str).
    Raises ValueError if the response cannot be parsed into two sections.
    """
    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=4096,
        system=_SYSTEM_PROMPT,
        messages=[
            {"role": "user", "content": _make_user_message(chunk, grade, chapter)}
        ],
    )

    raw_response = message.content[0].text

    # Split on the delimiters
    if "---CONCEPT---" not in raw_response or "---QUESTIONS---" not in raw_response:
        raise ValueError(
            f"Claude response for lesson {chunk.lesson_num} did not contain "
            f"expected delimiters. Response preview:\n{raw_response[:500]}"
        )

    _, after_concept = raw_response.split("---CONCEPT---", 1)
    concept_part, questions_part = after_concept.split("---QUESTIONS---", 1)

    return concept_part.strip(), questions_part.strip()


# ---------------------------------------------------------------------------
# Stage 3 — YAML validation
# ---------------------------------------------------------------------------

_REQUIRED_CONCEPT_KEYS = {
    "lesson_id", "subject", "grade", "unit", "chapter", "lesson",
    "title", "standards", "citation", "has_visual", "concepts", "worked_examples"
}

_REQUIRED_QUESTIONS_KEYS = {
    "lesson_id", "subject", "grade", "chapter", "lesson",
    "title", "standards", "citation", "questions"
}


def validate_yaml(yaml_str: str, required_keys: set[str], label: str) -> list[str]:
    """
    Parse YAML and check for required top-level keys.
    Returns a list of warning strings (empty = clean).
    """
    if yaml is None:
        return ["pyyaml not installed — skipping validation"]

    warnings: list[str] = []
    try:
        data = yaml.safe_load(yaml_str)
    except yaml.YAMLError as e:
        return [f"{label}: YAML parse error — {e}"]

    if not isinstance(data, dict):
        return [f"{label}: parsed to non-dict type {type(data)}"]

    missing = required_keys - set(data.keys())
    if missing:
        warnings.append(f"{label}: missing required keys: {missing}")

    # Check for TODO placeholders that signal uncertain extraction
    todo_count = yaml_str.count("# TODO")
    if todo_count:
        warnings.append(f"{label}: {todo_count} TODO placeholder(s) require manual review")

    return warnings


# ---------------------------------------------------------------------------
# Stage 4 — File output
# ---------------------------------------------------------------------------

def lesson_folder_name(lesson_num: str, title: str) -> str:
    """
    Convert "1.1" + "Model Place Value Relationships"
    → "lesson_1_1_model_place_value_relationships"
    """
    num_part = "lesson_" + lesson_num.replace(".", "_")
    title_part = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    # Truncate title part to keep folder names manageable
    title_part = "_".join(title_part.split("_")[:6])
    return f"{num_part}_{title_part}"


def write_lesson_files(result: ParseResult, output_dir: Path) -> None:
    """Write concept.yaml and questions.yaml for one lesson."""
    folder = output_dir / result.lesson_folder
    folder.mkdir(parents=True, exist_ok=True)

    concept_path = folder / "concept.yaml"
    questions_path = folder / "questions.yaml"

    concept_path.write_text(result.concept_yaml, encoding="utf-8")
    questions_path.write_text(result.questions_yaml, encoding="utf-8")

    log.info("  Written: %s", concept_path)
    log.info("  Written: %s", questions_path)


def write_chapter_metadata(
    results: list[ParseResult],
    chapter: int,
    grade: int,
    output_dir: Path,
) -> None:
    """
    Write a minimal chapter_metadata.yaml stub.
    Full metadata can be enriched manually or in a follow-up pass.
    """
    lines = [
        f"# chapter_metadata.yaml — auto-generated by parse_chapter.py",
        f"# Review and enrich manually before ingesting to Firestore.",
        f"",
        f"chapter: {chapter}",
        f"grade: {grade}",
        f"total_lessons: {len(results)}",
        f"schema_version: '1.1'",
        f"",
        f"lessons:",
    ]
    for r in results:
        lines.append(f"  - lesson_id: # TODO — extract from {r.lesson_folder}/concept.yaml")
        lines.append(f"    folder: {r.lesson_folder}")
        if r.warnings:
            lines.append(f"    warnings:")
            for w in r.warnings:
                lines.append(f"      - \"{w}\"")

    meta_path = output_dir / "chapter_metadata.yaml"
    meta_path.write_text("\n".join(lines), encoding="utf-8")
    log.info("Written: %s", meta_path)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_page_range(s: str) -> tuple[int, int]:
    """Parse '5-38' → (5, 38). Also accepts single page '5' → (5, 5)."""
    parts = s.split("-")
    if len(parts) == 1:
        p = int(parts[0])
        return p, p
    if len(parts) == 2:
        return int(parts[0]), int(parts[1])
    raise argparse.ArgumentTypeError(f"Invalid page range '{s}'. Use 'start-end' e.g. '5-38'")


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Convert a GO Math PDF chapter into Reachy Mini YAML files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--pdf",     required=True,  help="Path to the GO Math PDF file")
    p.add_argument("--pages",   required=True,  type=parse_page_range,
                   help="Page range to process, e.g. '5-38' (printed page numbers)")
    p.add_argument("--chapter", required=True,  type=int, help="Chapter number, e.g. 1")
    p.add_argument("--grade",   required=True,  type=int, help="Grade level, e.g. 4")
    p.add_argument(
        "--output",
        default=None,
        help=(
            "Output directory override. If omitted, files are written to "
            r"D:\Users\haneu\Desktop\CBU\CBU_Courses_S6\EGR302\Robot-Tutor\data\mnt\user-data\outputs\chapter_XX"
        ),
    )
    p.add_argument("--dry-run", action="store_true",
                   help="Extract text only, skip Claude API calls, print raw text per lesson")
    p.add_argument("--lesson",  default=None,
                   help="Process only this lesson number, e.g. '1.3' (useful for reruns)")
    p.add_argument("--verbose", action="store_true", help="Show DEBUG-level logs")
    return p


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run(args: argparse.Namespace) -> int:
    if args.verbose:
        log.setLevel(logging.DEBUG)

    # ── Dependency checks ────────────────────────────────────────────────────
    if pdfplumber is None:
        log.error("pdfplumber is not installed. Run: pip install pdfplumber")
        return 1
    if not args.dry_run and anthropic is None:
        log.error("anthropic is not installed. Run: pip install anthropic")
        return 1
    if not args.dry_run:
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            log.error("ANTHROPIC_API_KEY environment variable is not set.")
            return 1

    # ── Setup ────────────────────────────────────────────────────────────────
    pdf_path = args.pdf
    start_page, end_page = args.pages
    output_dir = (
        Path(args.output)
        if args.output
        else DEFAULT_OUTPUT_ROOT / f"chapter_{args.chapter:02d}"
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    log.info("PDF:     %s", pdf_path)
    log.info("Pages:   %d–%d", start_page, end_page)
    log.info("Chapter: %d  Grade: %d", args.chapter, args.grade)
    log.info("Output:  %s", output_dir.resolve())

    # ── Stage 1: Extract text ────────────────────────────────────────────────
    log.info("Stage 1 — Extracting text from PDF...")
    pages = extract_pages(pdf_path, start_page, end_page)
    log.info("  Extracted %d pages", len(pages))

    log.info("Stage 1 — Detecting lesson boundaries...")
    boundaries = detect_lesson_boundaries(pages)

    if not boundaries:
        log.warning(
            "No lesson headings detected. Check that your --pages range covers "
            "the lesson title pages, or that the PDF is not scanned/image-based."
        )
        log.warning(
            "Tip: run with --dry-run to inspect raw extracted text before calling the API."
        )

    chunks = build_lesson_chunks(pages, boundaries)
    log.info("  Built %d lesson chunk(s)", len(chunks))

    # ── Filter to a single lesson if requested ───────────────────────────────
    if args.lesson:
        chunks = [c for c in chunks if c.lesson_num == args.lesson]
        if not chunks:
            log.error("Lesson %s not found in detected boundaries: %s",
                      args.lesson, [b[0] for b in boundaries])
            return 1

    # ── Dry-run: print raw text and exit ────────────────────────────────────
    if args.dry_run:
        log.info("DRY RUN — printing raw extracted text per lesson (no API calls)")
        for chunk in chunks:
            print(f"\n{'='*70}")
            print(f"LESSON {chunk.lesson_num}: {chunk.title}")
            print(f"Pages: {chunk.pages}")
            print(f"{'='*70}")
            print(chunk.raw_text[:3000])  # Show first 3000 chars per lesson
            if len(chunk.raw_text) > 3000:
                print(f"... [{len(chunk.raw_text) - 3000} more chars]")
        return 0

    # ── Stage 2: Call Claude API ─────────────────────────────────────────────
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    results: list[ParseResult] = []

    for chunk in chunks:
        log.info("Stage 2 — Processing Lesson %s: %s...", chunk.lesson_num, chunk.title)

        try:
            concept_yaml, questions_yaml = call_claude(
                chunk, args.grade, args.chapter, client
            )
        except Exception as e:
            log.error("  API call failed for Lesson %s: %s", chunk.lesson_num, e)
            # Write a fallback stub so the pipeline doesn't lose the lesson entirely
            concept_yaml = (
                f"# AUTO-GENERATED STUB — API call failed\n"
                f"# Lesson {chunk.lesson_num}: {chunk.title}\n"
                f"# Error: {e}\n"
                f"lesson_id: '# TODO'\n"
            )
            questions_yaml = (
                f"# AUTO-GENERATED STUB — API call failed\n"
                f"# Lesson {chunk.lesson_num}: {chunk.title}\n"
                f"# Error: {e}\n"
                f"lesson_id: '# TODO'\n"
            )

        # ── Stage 3: Validate ────────────────────────────────────────────────
        folder_name = lesson_folder_name(chunk.lesson_num, chunk.title)
        warnings: list[str] = []
        warnings += validate_yaml(concept_yaml,   _REQUIRED_CONCEPT_KEYS,   "concept.yaml")
        warnings += validate_yaml(questions_yaml, _REQUIRED_QUESTIONS_KEYS, "questions.yaml")

        if warnings:
            for w in warnings:
                log.warning("  [%s] %s", folder_name, w)

        result = ParseResult(
            lesson_num=chunk.lesson_num,
            lesson_folder=folder_name,
            concept_yaml=concept_yaml,
            questions_yaml=questions_yaml,
            warnings=warnings,
        )
        results.append(result)

        # ── Stage 4: Write files ─────────────────────────────────────────────
        write_lesson_files(result, output_dir)

    # ── Chapter metadata ─────────────────────────────────────────────────────
    write_chapter_metadata(results, args.chapter, args.grade, output_dir)

    # ── Summary ──────────────────────────────────────────────────────────────
    log.info("")
    log.info("Done. Processed %d lesson(s).", len(results))
    total_warnings = sum(len(r.warnings) for r in results)
    if total_warnings:
        log.warning("%d warning(s) across all lessons — search YAML files for '# TODO'", total_warnings)
    else:
        log.info("No warnings — all required fields detected.")

    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    parser = build_arg_parser()
    args = parser.parse_args()
    sys.exit(run(args))
