#!/usr/bin/env python3
"""
parse_chapter.py — GO Math PDF → Reachy Mini YAML Pipeline
============================================================
EGR302 Junior Design | Reachy Mini (BAY-min) Tutoring Robot
Role owner: Haneul (data pipelines & module/question design)

Strategy: Hybrid
  1. pdfplumber  → extracts raw text per page (deterministic, free)
  2. AI provider → structures raw text into concept.yaml + questions.yaml
                   using the v1.1 schema as the system prompt

Supported providers (--provider flag):
  gemini   — Google Gemini 1.5 Flash (FREE, recommended)
  claude   — Anthropic Claude Sonnet  (paid, ~$0.04/lesson)

Usage:
  # Gemini (free) — recommended
  python parse_chapter.py \\
      --pdf     path/to/gomath_g4.pdf \\
      --pages   5-38 \\
      --chapter 1 \\
      --grade   4 \\
      --output  ./chapter_01 \\
      --provider gemini

  # Claude (paid)
  python parse_chapter.py \\
      --pdf     path/to/gomath_g4.pdf \\
      --pages   5-38 \\
      --chapter 1 \\
      --grade   4 \\
      --output  ./chapter_01 \\
      --provider claude

  # Dry-run (extraction only, no API calls):
  python parse_chapter.py --pdf gomath_g4.pdf --pages 5-38 --chapter 1 --grade 4 --dry-run

Requirements:
  pip install pdfplumber pyyaml requests            # Gemini (REST)
  pip install pdfplumber pyyaml anthropic             # Claude

Environment variables:
  GEMINI_API_KEY     — required when --provider gemini (get free key at aistudio.google.com)
  ANTHROPIC_API_KEY  — required when --provider claude
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

try:
    from lib.parser._gemini_rest_patch import gemini_text_call
except ModuleNotFoundError:
    from _gemini_rest_patch import gemini_text_call


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)
log = logging.getLogger("parse_chapter")


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
# The title regex skips lines that are just "Name" (student name field),
# blank, or pure whitespace — these appear above the real lesson title.
_LESSON_HEADING = re.compile(
    r"Lesson\s+(\d+\.\d+)",
    re.IGNORECASE,
)

# Matches a real lesson title: non-empty, not just "Name", not all digits/symbols
_TITLE_LINE = re.compile(
    r"^(?!\s*Name\s*$)(?!\s*$)\s*([A-Z][\w\s•\'\-\.]{4,})$",
    re.MULTILINE,
)


# ---------------------------------------------------------------------------
# GO Math Grade 4 CA — known lesson titles lookup table
# Key: (chapter, "lesson_num")  e.g. (2, "2.3")
# Used by detect_lesson_boundaries() as primary title source before regex.
# Covers all 13 chapters. Add/correct entries as needed.
# ---------------------------------------------------------------------------
GO_MATH_G4_TITLES: dict[tuple[int, str], str] = {
    # Chapter 1 — Place Value, Addition, and Subtraction to One Million
    (1, "1.1"): "Model Place Value Relationships",
    (1, "1.2"): "Read and Write Numbers",
    (1, "1.3"): "Compare and Order Numbers",
    (1, "1.4"): "Round Numbers",
    (1, "1.5"): "Rename Numbers",
    (1, "1.6"): "Add Whole Numbers",
    (1, "1.7"): "Subtract Whole Numbers",
    (1, "1.8"): "Problem Solving: Comparison Problems with Addition and Subtraction",

    # Chapter 2 — Multiply by 1-Digit Numbers
    (2, "2.1"):  "Multiplication Comparisons",
    (2, "2.2"):  "Comparison Problems",
    (2, "2.3"):  "Multiply Tens, Hundreds, and Thousands",
    (2, "2.4"):  "Estimate Products",
    (2, "2.5"):  "Multiply Using the Distributive Property",
    (2, "2.6"):  "Multiply Using Expanded Form",
    (2, "2.7"):  "Multiply Using Partial Products",
    (2, "2.8"):  "Multiply Using Mental Math",
    (2, "2.9"):  "Problem Solving: Multistep Multiplication Problems",
    (2, "2.10"): "Multiply 2-Digit Numbers with Regrouping",
    (2, "2.11"): "Multiply 3-Digit and 4-Digit Numbers with Regrouping",
    (2, "2.12"): "Algebra: Solve Multistep Problems Using Equations",

    # Chapter 3 — Multiply 2-Digit Numbers
    (3, "3.1"): "Multiply Tens",
    (3, "3.2"): "Estimate Products",
    (3, "3.3"): "Area Models and Partial Products",
    (3, "3.4"): "Multiply Using Partial Products",
    (3, "3.5"): "Multiply with Regrouping",
    (3, "3.6"): "Choose a Multiplication Method",
    (3, "3.7"): "Problem Solving: Multiply 2-Digit Numbers",

    # Chapter 4 — Divide by 1-Digit Numbers
    (4, "4.1"): "Estimate Quotients Using Multiples",
    (4, "4.2"): "Remainders",
    (4, "4.3"): "Interpret the Remainder",
    (4, "4.4"): "Divide Tens, Hundreds, and Thousands",
    (4, "4.5"): "Estimate Quotients Using Compatible Numbers",
    (4, "4.6"): "Division and the Distributive Property",
    (4, "4.7"): "Divide Using Repeated Subtraction",
    (4, "4.8"): "Divide Using Partial Quotients",
    (4, "4.9"): "Model Division with Regrouping",
    (4, "4.10"): "Place the First Digit",
    (4, "4.11"): "Divide by 1-Digit Numbers",
    (4, "4.12"): "Problem Solving: Multistep Division Problems",

    # Chapter 5 — Factors, Multiples, and Patterns
    (5, "5.1"): "Model Factors",
    (5, "5.2"): "Factors and Divisibility",
    (5, "5.3"): "Problem Solving: Common Factors",
    (5, "5.4"): "Factors and Multiples",
    (5, "5.5"): "Prime and Composite Numbers",
    (5, "5.6"): "Algebra: Number Patterns",

    # Chapter 6 — Fraction Equivalence and Comparison
    (6, "6.1"): "Investigate: Equivalent Fractions",
    (6, "6.2"): "Generate Equivalent Fractions",
    (6, "6.3"): "Simplest Form",
    (6, "6.4"): "Common Denominators",
    (6, "6.5"): "Problem Solving: Find Equivalent Fractions",
    (6, "6.6"): "Compare Fractions Using Benchmarks",
    (6, "6.7"): "Compare Fractions",
    (6, "6.8"): "Compare and Order Fractions",

    # Chapter 7 — Add and Subtract Fractions
    (7, "7.1"): "Add and Subtract Parts of a Whole",
    (7, "7.2"): "Write Fractions as Sums",
    (7, "7.3"): "Add Fractions Using Models",
    (7, "7.4"): "Subtract Fractions Using Models",
    (7, "7.5"): "Add and Subtract Fractions",
    (7, "7.6"): "Rename Fractions and Mixed Numbers",
    (7, "7.7"): "Add and Subtract Mixed Numbers",
    (7, "7.8"): "Subtraction with Renaming",
    (7, "7.9"): "Algebra: Fractions and Properties of Addition",
    (7, "7.10"): "Problem Solving: Multistep Fraction Problems",

    # Chapter 8 — Multiply Fractions by Whole Numbers
    (8, "8.1"): "Multiples of Unit Fractions",
    (8, "8.2"): "Multiples of Fractions",
    (8, "8.3"): "Multiply a Fraction by a Whole Number Using Models",
    (8, "8.4"): "Multiply a Fraction or Mixed Number by a Whole Number",
    (8, "8.5"): "Problem Solving: Comparison Problems with Fractions",

    # Chapter 9 — Relate Fractions and Decimals
    (9, "9.1"): "Relate Tenths and Decimals",
    (9, "9.2"): "Relate Hundredths and Decimals",
    (9, "9.3"): "Equivalent Fractions and Decimals",
    (9, "9.4"): "Relate Fractions, Decimals, and Money",
    (9, "9.5"): "Problem Solving: Money",
    (9, "9.6"): "Add Fractional Parts of 10 and 100",
    (9, "9.7"): "Compare Decimals",

    # Chapter 10 — Two-Dimensional Figures
    (10, "10.1"): "Lines, Rays, and Angles",
    (10, "10.2"): "Classify Triangles by Angles",
    (10, "10.3"): "Parallel Lines and Perpendicular Lines",
    (10, "10.4"): "Classify Quadrilaterals",
    (10, "10.5"): "Line Symmetry",
    (10, "10.6"): "Find and Draw Lines of Symmetry",
    (10, "10.7"): "Problem Solving: Shape Patterns",

    # Chapter 11 — Angles
    (11, "11.1"): "Angles and Fractional Parts of a Circle",
    (11, "11.2"): "Degrees",
    (11, "11.3"): "Measure and Draw Angles",
    (11, "11.4"): "Investigate: Join and Separate Angles",
    (11, "11.5"): "Problem Solving: Unknown Angle Measures",

    # Chapter 12 — Relative Sizes of Measurement Units
    (12, "12.1"): "Measurement Benchmarks",
    (12, "12.2"): "Customary Units of Length",
    (12, "12.3"): "Customary Units of Weight",
    (12, "12.4"): "Customary Units of Liquid Volume",
    (12, "12.5"): "Line Plots",
    (12, "12.6"): "Metric Units of Length",
    (12, "12.7"): "Metric Units of Mass and Liquid Volume",
    (12, "12.8"): "Units of Time",
    (12, "12.9"): "Problem Solving: Elapsed Time",
    (12, "12.10"): "Mixed Measures",
    (12, "12.11"): "Algebra: Patterns in Measurement Units",

    # Chapter 13 — Perimeter and Area
    (13, "13.1"): "Perimeter",
    (13, "13.2"): "Area",
    (13, "13.3"): "Area of Combined Rectangles",
    (13, "13.4"): "Find Unknown Measures",
    (13, "13.5"): "Problem Solving: Find the Area",
}

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


def deduplicate_text(text: str) -> str:
    """
    Fix tripled/doubled characters caused by pdfplumber reading bold or
    shadowed font layers as separate text streams.
    e.g. "UUUnnnllloooccckkk" -> "Unlock"
    Strategy: if every character in a word repeats N times consecutively,
    keep only every Nth character.
    """
    def fix_word(word: str) -> str:
        if len(word) < 4:
            return word
        for n in (3, 2):
            if len(word) % n == 0:
                # Check if each char repeats n times in sequence
                deduped = word[::n]
                reconstructed = "".join(c * n for c in deduped)
                if reconstructed == word:
                    return deduped
        return word

    # Apply fix word-by-word, preserving whitespace/punctuation splits
    tokens = re.split(r"(\s+)", text)
    return "".join(fix_word(t) if re.match(r"^[A-Za-z]+$", t) else t for t in tokens)


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
            text = deduplicate_text(page.extract_text(layout=True) or "")

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


# Lines to skip when searching for a lesson title after the lesson number.
# These are recurring section labels that appear before the real title.
_TITLE_SKIP = re.compile(
    r"^(Name|Unlock the Problem|Investigate|Essential Question|"
    r"Share and Show|On Your Own|Problem Solving|COMMON CORE|"
    r"Mathematical Practices?|Lesson Objective)$",
    re.IGNORECASE,
)


def detect_lesson_boundaries(
    pages: dict[int, str],
    chapter: int = 0,
    title_overrides: dict[str, str] | None = None,
) -> list[tuple[str, str, int]]:
    """
    Scan page texts for lesson headings.
    Returns list of (lesson_num, title, start_page) sorted by start_page.
    e.g. [("1.1", "Model Place Value Relationships", 5), ...]

    Strategy:
      - Find "Lesson X.Y" pattern to get lesson number and page
      - Scan lines AFTER the match on the deduplicated text for the real title
      - Skip known non-title lines (Name, Unlock the Problem, etc.)
      - Apply title_overrides dict for any lesson where auto-detect still fails
        e.g. title_overrides={"2.3": "Multiply with 1-Digit Numbers"}
    """
    found: list[tuple[str, str, int]] = []
    title_overrides = title_overrides or {}

    for page_num, text in sorted(pages.items()):
        # Dedup the text before title scanning so tripled chars don't slip through
        clean_text = deduplicate_text(text)

        for m in _LESSON_HEADING.finditer(clean_text):
            lesson_num = m.group(1)

            # Priority 1: manual --title-overrides from CLI
            if lesson_num in title_overrides:
                title = title_overrides[lesson_num]
            # Priority 2: known title lookup table (GO Math G4 CA)
            elif (chapter, lesson_num) in GO_MATH_G4_TITLES:
                title = GO_MATH_G4_TITLES[(chapter, lesson_num)]
            else:
                # Priority 3: regex scan of page text (fallback)
                after = clean_text[m.end():]
                title = "# TODO: title not detected — add to --title-overrides"
                for line in after.splitlines():
                    line = line.strip()
                    if (line
                            and not _TITLE_SKIP.match(line)
                            and len(line) > 4
                            and re.search(r"[A-Za-z]{3,}", line)
                            and not line.replace(" ", "").isdigit()):
                        title = line
                        break

            # Deduplicate: same lesson appears in running header on multiple pages
            if not found or found[-1][0] != lesson_num:
                found.append((lesson_num, title, page_num))
                log.info("  Detected Lesson %s -- '%s' at page %d", lesson_num, title, page_num)
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
lesson_id: "math_g{grade}_ch{chapter}_l{lesson_index}"   # e.g. math_g4_ch2_l1
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
      answer: "<full answer with working>"
      options:                        # ALWAYS required — exactly 3 strings
        - "<wrong answer 1>"
        - "<correct answer>"          # position is shuffled — do not always put correct first
        - "<wrong answer 2>"
      correct_answer: "<string>"      # MUST match one option exactly (same string, same punctuation)
      citation_page: <int>
      difficulty: <difficulty_tag>    # only when explicitly marked
      items:                          # only for true_false_set / multiple_select
        - statement: "<text>"
          answer: "<True|False>"
          options: ["True", "False"]
          correct_answer: "<True|False>"

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
Use canonical lesson_id format: subject + grade + chapter + lesson index.
Example: math_g4_ch2_l1 for Chapter 2, Lesson 2.1.
Do not use short forms like '2.1' or malformed forms like 'math_g4_ch2_l2.1'.

## IDs
- Concepts:        c1, c2, c3 ...
- Worked examples: we1, we2 ...
- Guided:          q_g1, q_g2 ...
- Independent:     q_i1, q_i2 ...
- Word problems:   q_w1, q_w2 ...

## OPTIONS AND CORRECT_ANSWER RULES
Every question MUST include both `options` (list of exactly 3 strings) and `correct_answer` (string).

Rules for generating options:
1. ALWAYS exactly 3 options — no more, no less
2. One option is the correct answer; the other two are plausible distractors
3. correct_answer MUST match one option exactly — same string, same punctuation, same units
4. Shuffle position — do not always put the correct answer first or last
5. Distractors must be plausible for a Grade 4 student — use:
   - Common calculation errors (off-by-one, wrong operation, transposed digits)
   - Nearby numbers that could result from a partial step
   - For subtraction problems: result of adding instead of subtracting, or vice versa
6. For numerical answers: correct_answer is the final number only (short form), not the full working
   - answer field keeps the full working: "68,986 - 64,997 = 3,989 feet higher."
   - correct_answer is just: "3,989 feet"
7. For comparison questions (more/less/equal, true/false): options are the comparison words only
8. For dollar amounts: preserve the $ sign in both options and correct_answer
9. For true_false_set: add options and correct_answer to each item in the items list
10. Never use the same string twice in options
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


def call_gemini(
    chunk: LessonChunk,
    grade: int,
    chapter: int,
    model: str,
) -> tuple[str, str]:
    """
    Call the Gemini 1.5 Flash API and return (concept_yaml_str, questions_yaml_str).
    Uses the Gemini REST API via requests.
    The API key is read from the GEMINI_API_KEY environment variable.
    Raises ValueError if the response cannot be parsed into two sections.
    """
    raw_response = gemini_text_call(
        _make_user_message(chunk, grade, chapter),
        system=_SYSTEM_PROMPT,
        model=model,
        temperature=0.1,
        max_tokens=16000,
    )

    log.debug(
        "Gemini raw_response preview for lesson %s: %r",
        chunk.lesson_num,
        raw_response[:200],
    )

    # Prepend system prompt as first user turn — works across all API versions
    

    # Strip markdown fences if Gemini wraps the output (it sometimes does)
    raw_response = re.sub(r"^```(?:yaml)?\s*", "", raw_response, flags=re.MULTILINE)
    raw_response = re.sub(r"\s*```\s*$", "", raw_response, flags=re.MULTILINE)

    has_concept = "---CONCEPT---" in raw_response
    has_questions = "---QUESTIONS---" in raw_response

    if has_concept and has_questions:
        _, after_concept = raw_response.split("---CONCEPT---", 1)
        concept_part, questions_part = after_concept.split("---QUESTIONS---", 1)
        return concept_part.strip(), questions_part.strip()

    if has_concept and not has_questions:
        _, concept_part = raw_response.split("---CONCEPT---", 1)

        questions_only_prompt = f"""Extract ONLY the questions.yaml for the following GO Math lesson.

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

Return EXACTLY one section in this format:
---QUESTIONS---
<questions.yaml>

Do not return ---CONCEPT---.
"""

        questions_response = gemini_text_call(
            questions_only_prompt,
            system=_SYSTEM_PROMPT,
            model=model,
            temperature=0.1,
            max_tokens=16000,
        )

        log.debug(
            "Gemini questions-only raw_response preview for lesson %s: %r",
            chunk.lesson_num,
            questions_response[:200],
        )

        questions_response = re.sub(r"^```(?:yaml)?\s*", "", questions_response, flags=re.MULTILINE)
        questions_response = re.sub(r"\s*```\s*$", "", questions_response, flags=re.MULTILINE)

        if "---QUESTIONS---" not in questions_response:
            raise ValueError(
                f"Gemini questions-only response for lesson {chunk.lesson_num} did not contain "
                f"expected delimiter. Response preview:\n{questions_response[:500]}"
            )

        _, questions_part = questions_response.split("---QUESTIONS---", 1)
        return concept_part.strip(), questions_part.strip()

    if not has_concept and not has_questions:
        raise ValueError(
            f"Gemini response for lesson {chunk.lesson_num} did not contain "
            f"expected delimiters. Response preview:\n{raw_response[:500]}"
        )

    raise ValueError(
        f"Gemini response for lesson {chunk.lesson_num} contained incomplete delimiters. "
        f"Response preview:\n{raw_response[:500]}"
    )


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


def canonical_lesson_index(lesson_num: str) -> int:
    """
    Convert a lesson number like '2.1' to its lesson index within the chapter: 1.
    """
    try:
        return int(str(lesson_num).split(".")[-1])
    except (TypeError, ValueError, IndexError):
        return 0


def canonical_lesson_id(subject: str, grade: int, chapter: int, lesson_num: str) -> str:
    subject_slug = re.sub(r"[^a-z0-9]+", "_", str(subject).lower()).strip("_") or "subject"
    lesson_index = canonical_lesson_index(lesson_num)
    return f"{subject_slug}_g{grade}_ch{chapter}_l{lesson_index}"


def normalize_generated_yaml(
    yaml_str: str,
    *,
    chunk: LessonChunk,
    grade: int,
    chapter: int,
    is_questions: bool,
) -> str:
    """
    Post-process model output into a consistent schema shape for critical IDs/metadata.
    If parsing fails, return the original string unchanged so validation can surface it.
    """
    if yaml is None:
        return yaml_str

    try:
        doc = yaml.safe_load(yaml_str)
    except yaml.YAMLError:
        return yaml_str

    if not isinstance(doc, dict):
        return yaml_str

    subject = str(doc.get("subject", "math")).strip() or "math"
    lesson_index = canonical_lesson_index(chunk.lesson_num)

    doc["lesson_id"] = canonical_lesson_id(subject, grade, chapter, chunk.lesson_num)
    doc["subject"] = subject
    doc["grade"] = grade
    doc["unit"] = int(doc.get("unit", chapter) or chapter)
    doc["chapter"] = chapter
    doc["lesson"] = int(doc.get("lesson", lesson_index) or lesson_index)
    doc["title"] = str(doc.get("title", chunk.title)).strip() or chunk.title

    citation = doc.get("citation")
    if not isinstance(citation, dict):
        citation = {}
    citation.setdefault("textbook", f"GO Math Grade {grade} California (Houghton Mifflin Harcourt)")
    citation["chapter"] = chapter
    citation["lesson"] = lesson_index
    doc["citation"] = citation

    if is_questions:
        questions = doc.get("questions")
        if not isinstance(questions, dict):
            questions = {}
        questions.setdefault("guided", [])
        questions.setdefault("independent", [])
        questions.setdefault("word_problems", [])
        doc["questions"] = questions

    return yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)


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
    p.add_argument("--provider", default="gemini", choices=["gemini", "claude"],
                   help="AI provider to use: 'gemini' (free, default) or 'claude' (paid)")
    p.add_argument("--model", default="gemini-2.5-flash",
                   help="Gemini model name to use at runtime (default: gemini-2.5-flash)")
    p.add_argument("--pdf",     required=True,  help="Path to the GO Math PDF file")
    p.add_argument("--pages",   required=True,  type=parse_page_range,
                   help="Page range to process, e.g. '5-38' (printed page numbers)")
    p.add_argument("--chapter", required=True,  type=int, help="Chapter number, e.g. 1")
    p.add_argument("--grade",   required=True,  type=int, help="Grade level, e.g. 4")
    p.add_argument("--output", default=r"D:\Users\haneu\Desktop\CBU\CBU_Courses_S6\EGR302\Robot-Tutor\data\mnt\user-data\outputs", help="Output directory (default: Robot-Tutor data outputs folder)")
    p.add_argument("--dry-run", action="store_true",
                   help="Extract text only, skip Claude API calls, print raw text per lesson")
    p.add_argument("--lesson",  default=None,
                   help="Process only this lesson number, e.g. '1.3' (useful for reruns)")
    p.add_argument("--title-overrides", default=None,
                   help=(
                       "Manually specify lesson titles that auto-detect gets wrong. "
                       "Format: '2.3=Multiply with 1-Digit Numbers,2.6=Multiply Using Expanded Form'. "
                       "Separate multiple overrides with commas."
                   ))
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

    if not args.dry_run:
        if args.provider == "gemini":
            if not os.environ.get("GEMINI_API_KEY"):
                log.error("GEMINI_API_KEY environment variable is not set.")
                log.error("Get a free key at: https://aistudio.google.com")
                return 1
        elif args.provider == "claude":
            if anthropic is None:
                log.error("anthropic is not installed. Run: pip install anthropic")
                return 1
            if not os.environ.get("ANTHROPIC_API_KEY"):
                log.error("ANTHROPIC_API_KEY environment variable is not set.")
                return 1

    # ── Setup ────────────────────────────────────────────────────────────────
    pdf_path = args.pdf
    start_page, end_page = args.pages
    chapter_folder = f"chapter_{args.chapter:02d}"
    output_dir = Path(args.output) / chapter_folder
    output_dir.mkdir(parents=True, exist_ok=True)

    log.info("PDF:      %s", pdf_path)
    log.info("Pages:    %d–%d", start_page, end_page)
    log.info("Chapter:  %d  Grade: %d", args.chapter, args.grade)
    log.info("Provider: %s", args.provider)
    log.info("Output:   %s", output_dir.resolve())

    # ── Stage 1: Extract text ────────────────────────────────────────────────
    log.info("Stage 1 — Extracting text from PDF...")
    pages = extract_pages(pdf_path, start_page, end_page)
    log.info("  Extracted %d pages", len(pages))

    log.info("Stage 1 — Detecting lesson boundaries...")
    log.info("Stage 1 — Detecting lesson boundaries...")
    # Parse --title-overrides if provided
    # Format: "2.3=Some Title,2.6=Another Title"
    title_overrides: dict[str, str] = {}
    if args.title_overrides:
        for pair in args.title_overrides.split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                title_overrides[k.strip()] = v.strip()
        if title_overrides:
            log.info("  Title overrides: %s", title_overrides)

    boundaries = detect_lesson_boundaries(pages, chapter=args.chapter, title_overrides=title_overrides)
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

    # ── Stage 2: Initialise AI client ───────────────────────────────────────
    if args.provider == "gemini":

        log.info("Stage 2 — Using Gemini model %s", args.model)
    else:
        claude_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
        log.info("Stage 2 — Using Claude Sonnet")

    results: list[ParseResult] = []

    for chunk in chunks:
        log.info("Stage 2 — Processing Lesson %s: %s...", chunk.lesson_num, chunk.title)

        try:
            if args.provider == "gemini":
                    concept_yaml, questions_yaml = call_gemini(
                        chunk, args.grade, args.chapter, args.model
                    )
            else:
                concept_yaml, questions_yaml = call_claude(
                    chunk, args.grade, args.chapter, claude_client
                )
        except Exception as e:
            log.error("  API call failed for Lesson %s: %s", chunk.lesson_num, e)
            # Write a fallback stub so the pipeline doesn't lose the lesson entirely
            concept_yaml = (
                f"# AUTO-GENERATED STUB -- API call failed\n"
                f"# Lesson {chunk.lesson_num}: {chunk.title}\n"
                f"# Error: {e}\n"
                f"lesson_id: '# TODO'\n"
            )
            questions_yaml = (
                f"# AUTO-GENERATED STUB -- API call failed\n"
                f"# Lesson {chunk.lesson_num}: {chunk.title}\n"
                f"# Error: {e}\n"
                f"lesson_id: '# TODO'\n"
            )

        concept_yaml = normalize_generated_yaml(
            concept_yaml,
            chunk=chunk,
            grade=args.grade,
            chapter=args.chapter,
            is_questions=False,
        )
        questions_yaml = normalize_generated_yaml(
            questions_yaml,
            chunk=chunk,
            grade=args.grade,
            chapter=args.chapter,
            is_questions=True,
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
