#!/usr/bin/env python3
"""
seed_firestore.py — YAML → Firestore Ingestion Script
=======================================================
EGR302 Junior Design | Reachy Mini (BAY-min) Tutoring Robot
Role owner: Haneul (data pipelines & module/question design)

Reads concept.yaml + questions.yaml produced by parse_chapter.py and seeds
them into the existing Firestore `modules` collection, matching the schema
already used by the team.

Firestore target:
  modules/{module_id}
    module_id:             "math_grade4_ch2_multiplication_comparisons"
    title:                 "Multiplication Comparisons"
    description:           "How do you solve multiplication comparison problems?"
    grade_level:           4
    subject_id:            "math"
    session_mode:          "teach_then_quiz"
    source:                "parse_chapter.py"
    created_at:            <timestamp>
    standard_tags:         ["4.OA.1"]
    prerequisites:         []
    chapter:               2
    lesson:                1
    citation:              { textbook, chapter, lesson, pages }
    instructional_content:
      text:                ""   (reserved for RAG pipeline)
      example_walkthrough: [ {id, title, steps, answer, has_visual, ...} ]
      concepts:            [ {id, term, definition, example} ]
    quiz_questions:
      guided:              [ {id, type, prompt, answer, has_visual, ...} ]
      independent:         [ {id, type, prompt, answer, has_visual, ...} ]
      word_problems:       [ {id, type, prompt, answer, has_visual, ...} ]

Usage:
  # Dry run (no writes)
  python seed_firestore.py --data-dir data\\chapter_01 --chapter 1 --grade 4 --dry-run

  # Preview document JSON before writing
  python seed_firestore.py --data-dir data\\chapter_01 --chapter 1 --grade 4 --preview --dry-run

  # Seed one lesson
  python seed_firestore.py --data-dir data\\chapter_01 --chapter 1 --grade 4 --lesson 1.1 --creds serviceAccountKey.json

  # Seed full chapter
  python seed_firestore.py --data-dir data\\chapter_01 --chapter 1 --grade 4 --creds serviceAccountKey.json

Requirements:
  pip install firebase-admin pyyaml

Auth (pick one):
  --creds path/to/serviceAccountKey.json
  set GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccountKey.json
  gcloud auth application-default login
"""

import os
import sys
import re
import json
import argparse
import logging
from pathlib import Path
from datetime import datetime, timezone

try:
    import yaml
except ImportError:
    yaml = None

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    firebase_admin = None
    credentials = None
    firestore = None

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)
log = logging.getLogger("seed_firestore")


# ---------------------------------------------------------------------------
# module_id formatter — matches existing naming convention
# e.g. "math_grade4_ch2_multiplication_comparisons"
# ---------------------------------------------------------------------------
def make_module_id(subject: str, grade: int, chapter: int, title: str) -> str:
    title_slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    title_slug = "_".join(title_slug.split("_")[:5])
    return f"{subject}_grade{grade}_ch{chapter}_{title_slug}"


# ---------------------------------------------------------------------------
# YAML loader
# ---------------------------------------------------------------------------
def load_yaml(path: Path) -> dict:
    if yaml is None:
        raise ImportError("pyyaml not installed. Run: pip install pyyaml")
    try:
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        log.error("Failed to load %s: %s", path, e)
        return {}


# ---------------------------------------------------------------------------
# Document builder
# Maps concept.yaml + questions.yaml → existing Firestore modules schema
# ---------------------------------------------------------------------------
def build_module_document(concept: dict, questions: dict, chapter: int):
    subject = concept.get("subject", "math")
    grade   = int(concept.get("grade", 4))
    title   = concept.get("title", "# TODO")
    lesson  = int(concept.get("lesson", 0))

    module_id = make_module_id(subject, grade, chapter, title)

    # standard_tags — keep short form (4.NBT.1) consistent with existing docs
    standard_tags = [str(s).strip() for s in concept.get("standards", [])]

    # instructional_content — extends existing map structure
    instructional_content = {
        "text":               "",           # reserved for RAG pipeline (Josh/Kip)
        "example_walkthrough": concept.get("worked_examples", []),
        "concepts":            concept.get("concepts", []),
    }

    # quiz_questions — new field added to existing schema (Option A: arrays)
    q_block = questions.get("questions", {})
    quiz_questions = {
        "guided":        q_block.get("guided", []),
        "independent":   q_block.get("independent", []),
        "word_problems": q_block.get("word_problems", []),
    }

    doc = {
        # Existing schema fields
        "module_id":             module_id,
        "title":                 title,
        "description":           concept.get("essential_question", f"Learn {title}."),
        "grade_level":           grade,
        "subject_id":            subject,
        "session_mode":          "teach_then_quiz",
        "source":                "parse_chapter.py",
        "created_at":            datetime.now(timezone.utc),
        "standard_tags":         standard_tags,
        "prerequisites":         [],
        "instructional_content": instructional_content,

        # New fields extending existing schema
        "chapter":               chapter,
        "lesson":                lesson,
        "citation":              concept.get("citation", {}),
        "has_visual":            concept.get("has_visual", False),
        "quiz_questions":        quiz_questions,

        # Internal metadata
        "_meta": {
            "schema_version": "1.1",
            "ingested_at":    datetime.now(timezone.utc).isoformat(),
            "lesson_id":      concept.get("lesson_id", ""),
            "source_script":  "seed_firestore.py",
        },
    }

    return module_id, doc


# ---------------------------------------------------------------------------
# Firestore writer
# ---------------------------------------------------------------------------
def write_to_firestore(db, module_id: str, document: dict,
                       overwrite: bool = False, dry_run: bool = False) -> bool:
    if dry_run:
        log.info("  [DRY RUN] modules/%s", module_id)
        return True
    try:
        ref = db.collection("modules").document(module_id)
        if overwrite:
            ref.set(document)
            log.info("  Overwrote: modules/%s", module_id)
        else:
            ref.set(document, merge=True)
            log.info("  Merged:    modules/%s", module_id)
        return True
    except Exception as e:
        log.error("  Failed: modules/%s — %s", module_id, e)
        return False


# ---------------------------------------------------------------------------
# Chapter processor
# ---------------------------------------------------------------------------
def process_chapter(data_dir, chapter, grade, subject,
                    lesson_filter, db, dry_run, overwrite, preview):
    lesson_dirs = sorted([
        d for d in data_dir.iterdir()
        if d.is_dir() and d.name.startswith("lesson_")
    ])

    if not lesson_dirs:
        log.warning("No lesson folders found in %s", data_dir)
        return 0, 0

    log.info("Found %d lesson folder(s)", len(lesson_dirs))
    success = failure = 0

    for lesson_dir in lesson_dirs:
        concept_path   = lesson_dir / "concept.yaml"
        questions_path = lesson_dir / "questions.yaml"

        if not concept_path.exists() or not questions_path.exists():
            log.warning("  Skipping %s — missing YAML files", lesson_dir.name)
            failure += 1
            continue

        concept   = load_yaml(concept_path)
        questions = load_yaml(questions_path)

        if not concept or not questions:
            log.warning("  Skipping %s — YAML parse failed", lesson_dir.name)
            failure += 1
            continue

        # Apply --lesson filter
        if lesson_filter:
            if lesson_filter.replace(".", "_") not in lesson_dir.name:
                continue

        module_id, document = build_module_document(concept, questions, chapter)

        q = document.get("quiz_questions", {})
        n_g = len(q.get("guided", []))
        n_i = len(q.get("independent", []))
        n_w = len(q.get("word_problems", []))

        log.info("  %-55s  guided:%-3d  ind:%-3d  word:%-3d",
                 module_id, n_g, n_i, n_w)

        if preview:
            print(f"\n{'='*70}")
            print(f"PREVIEW: modules/{module_id}")
            print(f"{'='*70}")
            preview_doc = {k: v for k, v in document.items()
                           if k not in ("quiz_questions", "instructional_content")}
            print(json.dumps(preview_doc, indent=2, default=str, ensure_ascii=False))
            print(f"  instructional_content.concepts:           {len(document['instructional_content'].get('concepts', []))} items")
            print(f"  instructional_content.example_walkthrough:{len(document['instructional_content'].get('example_walkthrough', []))} items")
            print(f"  quiz_questions.guided:                    {n_g} items")
            print(f"  quiz_questions.independent:               {n_i} items")
            print(f"  quiz_questions.word_problems:             {n_w} items")

        ok = write_to_firestore(db, module_id, document,
                                overwrite=overwrite, dry_run=dry_run)
        if ok:
            success += 1
        else:
            failure += 1

    return success, failure


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(
        description="Seed Firestore modules collection from GO Math YAML files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--data-dir",  required=True, help="Chapter folder e.g. data\\chapter_01")
    p.add_argument("--chapter",   required=True, type=int, help="Chapter number e.g. 1")
    p.add_argument("--grade",     required=True, type=int, help="Grade level e.g. 4")
    p.add_argument("--subject",   default="math", help="Subject (default: math)")
    p.add_argument("--lesson",    default=None, help="Seed only this lesson e.g. '1.1'")
    p.add_argument("--creds",     default=None, help="Path to Firebase service account JSON")
    p.add_argument("--dry-run",   action="store_true", help="No writes — just log what would happen")
    p.add_argument("--preview",   action="store_true", help="Print full document JSON before writing")
    p.add_argument("--overwrite", action="store_true", help="Replace documents fully (default: merge)")
    p.add_argument("--verbose",   action="store_true", help="DEBUG logs")
    return p


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def run(args):
    if args.verbose:
        log.setLevel(logging.DEBUG)

    if yaml is None:
        log.error("pyyaml not installed. Run: pip install pyyaml")
        return 1

    if not args.dry_run and firebase_admin is None:
        log.error("firebase-admin not installed. Run: pip install firebase-admin")
        return 1

    data_dir = Path(args.data_dir)
    if not data_dir.exists():
        log.error("Data directory not found: %s", data_dir)
        return 1

    log.info("Data dir:  %s", data_dir.resolve())
    log.info("Chapter:   %d  Grade: %d  Subject: %s", args.chapter, args.grade, args.subject)
    log.info("Mode:      %s",
             "DRY RUN" if args.dry_run else
             "OVERWRITE" if args.overwrite else "MERGE")

    db = None
    if not args.dry_run:
        creds_path = args.creds or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        try:
            if creds_path:
                cred = credentials.Certificate(creds_path)
                log.info("Auth:  Service account — %s", creds_path)
            else:
                cred = credentials.ApplicationDefault()
                log.info("Auth:  Application Default Credentials")

            if not firebase_admin._apps:
                firebase_admin.initialize_app(cred)
            db = firestore.client()
            log.info("Firestore: connected")
        except Exception as e:
            log.error("Firestore init failed: %s", e)
            return 1

    success, failure = process_chapter(
        data_dir=data_dir, chapter=args.chapter, grade=args.grade,
        subject=args.subject, lesson_filter=args.lesson, db=db,
        dry_run=args.dry_run, overwrite=args.overwrite, preview=args.preview,
    )

    log.info("")
    log.info("Done. %d seeded, %d failed.", success, failure)
    return 0 if failure == 0 else 1


if __name__ == "__main__":
    parser = build_arg_parser()
    args = parser.parse_args()
    sys.exit(run(args))