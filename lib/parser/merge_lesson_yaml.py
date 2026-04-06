#!/usr/bin/env python3
"""
merge_lesson_yaml.py
--------------------
Merge concept.yaml + questions.yaml into one module.yaml per lesson folder.
"""

from __future__ import annotations

import argparse
import re
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("pyyaml not installed. Run: pip install pyyaml") from exc


TEXT_REPLACEMENTS = {}


def normalize_text(value):
    if isinstance(value, str):
        normalized = value
        for src, dst in TEXT_REPLACEMENTS.items():
            normalized = normalized.replace(src, dst)
        return normalized
    if isinstance(value, list):
        return [normalize_text(item) for item in value]
    if isinstance(value, dict):
        return {key: normalize_text(item) for key, item in value.items()}
    return value


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def make_module_id(subject: str, grade: object, chapter: object, lesson: object, title: str) -> str:
    title_slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    return f"{subject}_grade{grade}_ch{chapter}_les{lesson}_{title_slug}"


def build_module_doc(concept: dict, questions: dict) -> dict:
    concept = normalize_text(concept)
    questions = normalize_text(questions)

    citation = concept.get("citation", questions.get("citation", {}))
    subject = str(concept.get("subject", questions.get("subject", citation.get("subject", "unknown")))).strip() or "unknown"
    grade = concept.get("grade_level", concept.get("grade", questions.get("grade_level", questions.get("grade", citation.get("grade", "unknown")))))
    chapter = concept.get("chapter", questions.get("chapter", citation.get("chapter", "unknown")))
    lesson = concept.get("lesson", questions.get("lesson", citation.get("lesson", "unknown")))
    title = str(concept.get("title", questions.get("title", ""))).strip()

    concepts = concept.get("concepts", [])
    worked_examples = concept.get("worked_examples", [])
    ic = concept.get("instructional_content", {})
    ic_text = ic.get("text", "") if isinstance(ic, dict) else ""
    ic_concepts = ic.get("concepts", concepts) if isinstance(ic, dict) else concepts
    ic_examples = ic.get("example_walkthrough", worked_examples) if isinstance(ic, dict) else worked_examples

    # Support both schemas:
    # Old: questions: {guided: [], independent: [], word_problems: []}
    # New (upload): guided: [], independent: [], word_problems: [] (top-level)
    q_block = questions.get("questions", {})
    if not q_block:
        q_block = questions

    module_doc = {
        "module_id": make_module_id(subject, grade, chapter, lesson, title),
        "lesson_id": concept.get("lesson_id", questions.get("lesson_id", "")),
        "subject": subject,
        "subject_id": subject,
        "grade": grade,
        "grade_level": grade,
        "unit": concept.get("unit", questions.get("unit", chapter)),
        "chapter": chapter,
        "lesson": lesson,
        "title": title,
        "description": concept.get("essential_question", ""),
        "essential_question": concept.get("essential_question", ""),
        "citation": citation,
        "standards": concept.get("standards", questions.get("standards", [])),
        "standard_tags": concept.get("standards", questions.get("standards", [])),
        "mathematical_practices": concept.get("mathematical_practices", []),
        "has_visual": concept.get("has_visual", False),
        "visual_handling": concept.get("visual_handling", ""),
        "visual_description": concept.get("visual_description", ""),
        "concepts": concepts,
        "worked_examples": worked_examples,
        "instructional_content": {
            "text": ic_text,
            "concepts": ic_concepts,
            "example_walkthrough": ic_examples,
        },
        "quiz_questions": {
            "guided": q_block.get("guided", []),
            "independent": q_block.get("independent", []),
            "word_problems": q_block.get("word_problems", []),
        },
        "prerequisites": [],
        "session_mode": "teach_then_quiz",
        "source": "pipeline",
        "_meta": {
            "schema_version": "1.1",
            "merged_at": datetime.now(timezone.utc).isoformat(),
            "lesson_id": concept.get("lesson_id", questions.get("lesson_id", "")),
            "source_script": "merge_lesson_yaml.py",
            "source_files": {
                "concept": "concept.yaml",
                "questions": "questions.yaml",
            },
        },
    }
    return module_doc


def merge_lesson_dir(lesson_dir: Path) -> bool:
    concept_path = lesson_dir / "concept.yaml"
    questions_path = lesson_dir / "questions.yaml"
    module_path = lesson_dir / "module.yaml"

    if not concept_path.exists() or not questions_path.exists():
        return False

    module_doc = build_module_doc(load_yaml(concept_path), load_yaml(questions_path))
    with module_path.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(module_doc, handle, sort_keys=False, allow_unicode=True, width=120)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge lesson concept/questions YAML into module.yaml files.")
    parser.add_argument("--data-root", default="data/mnt/user-data/outputs", help="Root outputs directory")
    args = parser.parse_args()

    data_root = Path(args.data_root)
    lesson_dirs = sorted(path for path in data_root.glob("chapter_*/*") if path.is_dir() and path.name.startswith("lesson_"))

    merged = 0
    for lesson_dir in lesson_dirs:
        if merge_lesson_dir(lesson_dir):
            merged += 1
            print(f"merged {lesson_dir}")

    print(f"merged {merged} lesson module file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
