"""
_gemini_prompt.py
-----------------
Shared Gemini REST API caller + YAML prompt templates for BAY-min pipeline.

Uses raw HTTP (requests) instead of google-generativeai SDK to avoid SDK
version mismatch issues across environments. Works with any Gemini model that
accepts the /v1beta/models/{model}:generateContent endpoint.

Usage:
    from lib.parser._gemini_prompt import call_gemini, CONCEPT_PROMPT, QUESTIONS_PROMPT
"""

import os
import re
import json
import time
import base64
import logging
from pathlib import Path
from typing import Optional

import requests

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Model config
# ---------------------------------------------------------------------------
DEFAULT_MODEL = "gemini-2.5-flash"          # Free tier: 15 req/min, 1M tok/day
GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
DEFAULT_GEMINI_MAX_RETRIES = 8
DEFAULT_GEMINI_RETRY_DELAY = 5.0
DEFAULT_GEMINI_MAX_RETRY_DELAY = 120.0


def _get_retry_delay_seconds(resp, attempt: int, delay: float) -> float:
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

# ---------------------------------------------------------------------------
# YAML schema v1.1 reminder injected into every prompt
# ---------------------------------------------------------------------------
_SCHEMA_REMINDER = """
OUTPUT FORMAT — strict YAML, no markdown fences, no extra commentary.
Follow this schema exactly:

concept.yaml:
  lesson_id: <string>          # e.g. "math_g4_ch1_l3"
  title: <string>
  standard_tags: [<list>]      # e.g. ["4.OA.1", "4.NBT.5"]
  instructional_content:
    text: <string>             # prose explanation of concept
    concepts: [<list of key terms>]
    example_walkthrough: <string>   # step-by-step worked example
  cite_only: <bool>            # true if visual-heavy, student directed to textbook
  citation:
    textbook: "GO Math Grade 4 California Edition"
    chapter: <int>
    lesson: <string>           # e.g. "1.3"
    pages: <string>            # e.g. "pp. 45-48"

questions.yaml:
  lesson_id: <string>          # e.g. "math_g4_ch1_l3"
  title: <string>
  guided:
    - id: <string>             # e.g. "q_1_3_g1"
      type: "multiple_choice"
      prompt: <string>
      options: [<exactly 3 strings>]
      correct_answer: <string> # must match one of the options exactly
  independent:
    - id: <string>             # e.g. "q_1_3_i1"
      type: "multiple_choice"
      prompt: <string>
      options: [<exactly 3 strings>]
      correct_answer: <string>
  word_problems:
    - id: <string>             # e.g. "q_1_3_w1"
      type: "multiple_choice"
      prompt: <string>
      options: [<exactly 3 strings>]
      correct_answer: <string>
""".strip()

# ---------------------------------------------------------------------------
# Prompt templates
# ---------------------------------------------------------------------------
CONCEPT_PROMPT = """You are a curriculum parser for an elementary school tutoring robot (BAY-min).
Extract the CONCEPT content from this lesson page for Grade 4 math students.

{schema_reminder}

Rules:
- Keep language simple (Grade 4 reading level) in the text field.
- If the lesson page is mostly visual (diagrams, number lines, base-ten blocks),
  set cite_only: true and leave instructional_content fields as empty strings.
- standard_tags should be California Common Core math standards (e.g. 4.OA.1).
- Do NOT invent content; only extract what is on the page.
- lesson_id format should be the canonical machine id supplied by the caller.

Lesson metadata:
  chapter: {chapter}
  lesson_number: {lesson_number}
  lesson_title: {lesson_title}
  pages: {pages}

Page content:
{page_content}
""".strip()

QUESTIONS_PROMPT = """You are a curriculum parser for an elementary school tutoring robot (BAY-min).
Generate QUIZ QUESTIONS from this lesson page for Grade 4 math students.

{schema_reminder}

Rules:
- guided: 3 questions — scaffolded, direct application of the concept shown.
- independent: 3 questions — slightly harder, student works alone.
- word_problems: 2 questions — real-world context, multi-step if appropriate.
- Each question MUST have exactly 3 options. Wrong options should be plausible
  (common mistakes, not obviously wrong).
- correct_answer must be copied verbatim from the options list.
- Question ids: "q_{{chapter}}_{{lesson}}_g1", "q_{{chapter}}_{{lesson}}_i1", etc.
- If the page is visual-only (cite_only), still generate questions but note
  "(See textbook p.X)" in the prompt so students know where to look.
- Do NOT invent math facts; base questions on the content shown.

Lesson metadata:
  chapter: {chapter}
  lesson_number: {lesson_number}
  lesson_title: {lesson_title}
  pages: {pages}

Page content:
{page_content}
""".strip()

UPLOAD_CONCEPT_PROMPT = """You are a curriculum parser for an elementary school tutoring robot (BAY-min).
A teacher or student has uploaded this document page. Extract CONCEPT content.

{schema_reminder}

Rules:
- Infer grade level from content difficulty if not stated.
- For handwritten notes: transcribe faithfully, then structure into the YAML.
- For worksheets: extract the concept being practiced, not the practice problems.
- If the content is not math-related, set cite_only: true and explain in the
  text field what the document appears to be about.
- Use the supplied upload metadata when it is present for subject, grade, chapter,
  lesson, and lesson_id. Only infer missing metadata from the document itself.
- pages: "uploaded document"

Document filename: {filename}
Upload metadata:
  subject: {subject}
  grade: {grade}
  chapter: {chapter}
  lesson: {lesson}
  lesson_id: {lesson_id}
""".strip()

UPLOAD_QUESTIONS_PROMPT = """You are a curriculum parser for an elementary school tutoring robot (BAY-min).
A teacher or student has uploaded this document. Generate quiz questions from it.

{schema_reminder}

Rules (same as standard pipeline, plus):
- For worksheets that already contain problems: reformat them into the schema.
- For handwritten notes: generate questions that test the concepts written.
- Aim for 2 guided, 2 independent, 1 word_problem minimum (scale up if content
  is rich enough for more).
- Use the supplied upload metadata when it is present for subject, grade, chapter,
  lesson, and lesson_id. Only infer missing metadata from the document itself.

Document filename: {filename}
Upload metadata:
  subject: {subject}
  grade: {grade}
  chapter: {chapter}
  lesson: {lesson}
  lesson_id: {lesson_id}
""".strip()


# ---------------------------------------------------------------------------
# REST caller
# ---------------------------------------------------------------------------
def call_gemini(
    prompt: str,
    *,
    model: str = DEFAULT_MODEL,
    image_b64: Optional[str] = None,
    image_mime: str = "image/png",
    api_key: Optional[str] = None,
    max_retries: int = 3,
    retry_delay: float = 5.0,
    temperature: float = 0.2,
) -> str:
    """
    Call Gemini via raw REST API. Returns the text response string.

    Args:
        prompt:      Text prompt.
        model:       Gemini model name (default: gemini-2.5-flash).
        image_b64:   Base64-encoded image bytes (for Vision calls).
        image_mime:  MIME type of image (default: image/png).
        api_key:     Gemini API key. Falls back to GEMINI_API_KEY env var.
        max_retries: Number of retry attempts on 429/5xx errors.
        retry_delay: Seconds between retries (doubles on each retry).
        temperature: Generation temperature (lower = more deterministic YAML).

    Returns:
        Raw text content from Gemini response.

    Raises:
        RuntimeError: If all retries fail or API returns an error.
    """
    key = api_key or os.environ.get("GEMINI_API_KEY")
    if not key:
        raise RuntimeError(
            "No Gemini API key found. Set GEMINI_API_KEY environment variable "
            "or pass api_key= to call_gemini()."
        )

    url = f"{GEMINI_API_BASE}/{model}:generateContent?key={key}"

    # Build content parts
    parts = []
    if image_b64:
        parts.append({
            "inline_data": {
                "mime_type": image_mime,
                "data": image_b64,
            }
        })
    parts.append({"text": prompt})

    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": 4096,
        },
    }

    max_retries = int(os.environ.get("GEMINI_MAX_RETRIES", max_retries))
    delay = float(os.environ.get("GEMINI_RETRY_DELAY", retry_delay))
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.post(url, json=payload, timeout=60)

            if resp.status_code == 429:
                wait_seconds = _get_retry_delay_seconds(resp, attempt, delay)
                log.warning(
                    "Rate limited (attempt %d/%d). Waiting %.0fs...",
                    attempt, max_retries, wait_seconds,
                )
                time.sleep(wait_seconds)
                delay = min(wait_seconds * 2, DEFAULT_GEMINI_MAX_RETRY_DELAY)
                continue

            if resp.status_code != 200:
                body = resp.text[:500]
                raise RuntimeError(
                    f"Gemini API error {resp.status_code}: {body}"
                )

            data = resp.json()

            # Navigate response structure
            candidates = data.get("candidates", [])
            if not candidates:
                raise RuntimeError(
                    f"Gemini returned no candidates. Response: {data}"
                )

            content = candidates[0].get("content", {})
            parts_out = content.get("parts", [])
            text = " ".join(p.get("text", "") for p in parts_out).strip()

            if not text:
                raise RuntimeError(
                    f"Gemini returned empty text. Full response: {data}"
                )

            return text

        except requests.RequestException as exc:
            log.warning("Network error (attempt %d/%d): %s", attempt, max_retries, exc)
            if attempt == max_retries:
                raise RuntimeError(f"Network error after {max_retries} attempts: {exc}") from exc
            time.sleep(delay)
            delay = min(delay * 2, DEFAULT_GEMINI_MAX_RETRY_DELAY)

    raise RuntimeError(f"Gemini call failed after {max_retries} attempts.")


def strip_yaml_fences(text: str) -> str:
    """
    Remove markdown code fences that Gemini sometimes wraps YAML in,
    even when told not to. Handles ```yaml ... ``` and ``` ... ```.
    """
    text = text.strip()
    text = re.sub(r"^```(?:yaml)?\s*\n?", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\n?```\s*$", "", text, flags=re.IGNORECASE)
    return text.strip()


def build_concept_prompt(
    chapter: int,
    lesson_number: str,
    lesson_title: str,
    pages: str,
    page_content: str,
) -> str:
    return CONCEPT_PROMPT.format(
        schema_reminder=_SCHEMA_REMINDER,
        chapter=chapter,
        lesson_number=lesson_number,
        lesson_title=lesson_title,
        pages=pages,
        page_content=page_content,
    )


def build_questions_prompt(
    chapter: int,
    lesson_number: str,
    lesson_title: str,
    pages: str,
    page_content: str,
) -> str:
    return QUESTIONS_PROMPT.format(
        schema_reminder=_SCHEMA_REMINDER,
        chapter=chapter,
        lesson_number=lesson_number,
        lesson_title=lesson_title,
        pages=pages,
        page_content=page_content,
    )


def build_upload_concept_prompt(
    filename: str,
    *,
    subject: str = "unknown",
    grade: str = "unknown",
    chapter: str = "unknown",
    lesson: str = "unknown",
    lesson_id: str = "upload_document",
) -> str:
    return UPLOAD_CONCEPT_PROMPT.format(
        schema_reminder=_SCHEMA_REMINDER,
        filename=filename,
        subject=subject,
        grade=grade,
        chapter=chapter,
        lesson=lesson,
        lesson_id=lesson_id,
    )


def build_upload_questions_prompt(
    filename: str,
    *,
    subject: str = "unknown",
    grade: str = "unknown",
    chapter: str = "unknown",
    lesson: str = "unknown",
    lesson_id: str = "upload_document",
) -> str:
    return UPLOAD_QUESTIONS_PROMPT.format(
        schema_reminder=_SCHEMA_REMINDER,
        filename=filename,
        subject=subject,
        grade=grade,
        chapter=chapter,
        lesson=lesson,
        lesson_id=lesson_id,
    )
