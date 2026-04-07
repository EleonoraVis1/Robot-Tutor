#!/usr/bin/env python3
"""
seed_firestore.py - YAML -> Firestore ingestion script.

Reads `module.yaml` produced by `merge_lesson_yaml.py` and seeds it into the
existing Firestore `modules` collection. If `module.yaml` is missing, falls
back to building the module document from `concept.yaml` + `questions.yaml`.
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


logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)
log = logging.getLogger("seed_firestore")


def safe_print(text: str) -> None:
    try:
        print(text)
    except UnicodeEncodeError:
        encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
        fallback = text.encode(encoding, errors="replace").decode(encoding, errors="replace")
        print(fallback)


def make_module_id(subject: str, grade: int, chapter: int, title: str) -> str:
    title_slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    title_slug = "_".join(title_slug.split("_")[:5])
    return f"{subject}_grade{grade}_ch{chapter}_{title_slug}"


def load_yaml(path: Path) -> dict:
    if yaml is None:
        raise ImportError("pyyaml not installed. Run: pip install pyyaml")
    try:
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as exc:
        log.error("Failed to load %s: %s", path, exc)
        return {}


def build_module_document(concept: dict, questions: dict, chapter: int):
    subject = concept.get("subject", "math")
    grade = int(concept.get("grade", 4))
    title = concept.get("title", "# TODO")
    lesson = int(concept.get("lesson", 0))

    module_id = make_module_id(subject, grade, chapter, title)
    standard_tags = [str(s).strip() for s in concept.get("standards", [])]

    instructional_content = {
        "text": "",
        "example_walkthrough": concept.get("worked_examples", []),
        "concepts": concept.get("concepts", []),
    }

    q_block = questions.get("questions", {})
    quiz_questions = {
        "guided": q_block.get("guided", []),
        "independent": q_block.get("independent", []),
        "word_problems": q_block.get("word_problems", []),
    }

    doc = {
        "module_id": module_id,
        "title": title,
        "description": concept.get("essential_question", f"Learn {title}."),
        "grade_level": grade,
        "subject_id": subject,
        "session_mode": "teach_then_quiz",
        "source": "parse_chapter.py",
        "created_at": datetime.now(timezone.utc),
        "standard_tags": standard_tags,
        "prerequisites": [],
        "instructional_content": instructional_content,
        "chapter": chapter,
        "lesson": lesson,
        "citation": concept.get("citation", {}),
        "has_visual": concept.get("has_visual", False),
        "quiz_questions": quiz_questions,
        "_meta": {
            "schema_version": "1.1",
            "ingested_at": datetime.now(timezone.utc).isoformat(),
            "lesson_id": concept.get("lesson_id", ""),
            "source_script": "seed_firestore.py",
        },
    }
    return module_id, doc


def build_module_document_from_module_yaml(module_doc: dict, chapter: int):
    module_id = str(module_doc.get("module_id", "")).strip()
    if not module_id:
        subject = str(module_doc.get("subject", module_doc.get("subject_id", "math"))).strip() or "math"
        grade = int(module_doc.get("grade", module_doc.get("grade_level", 4)) or 4)
        title = str(module_doc.get("title", "# TODO")).strip() or "# TODO"
        module_id = make_module_id(subject, grade, chapter, title)
        module_doc["module_id"] = module_id

    module_doc.setdefault("subject_id", module_doc.get("subject", "math"))
    module_doc.setdefault("grade_level", module_doc.get("grade", 4))
    module_doc.setdefault("description", module_doc.get("essential_question", module_doc.get("title", "")))
    module_doc.setdefault("standard_tags", module_doc.get("standards", []))
    module_doc.setdefault("prerequisites", [])
    module_doc.setdefault("session_mode", "teach_then_quiz")
    module_doc.setdefault("source", "parse_chapter.py")
    module_doc.setdefault("created_at", datetime.now(timezone.utc))
    module_doc.setdefault("chapter", chapter)
    module_doc.setdefault("instructional_content", {
        "text": "",
        "concepts": module_doc.get("concepts", []),
        "example_walkthrough": module_doc.get("worked_examples", []),
    })

    quiz_questions = module_doc.get("quiz_questions")
    if not isinstance(quiz_questions, dict):
        quiz_questions = {}
    quiz_questions.setdefault("guided", [])
    quiz_questions.setdefault("independent", [])
    quiz_questions.setdefault("word_problems", [])
    module_doc["quiz_questions"] = quiz_questions

    meta = module_doc.get("_meta")
    if not isinstance(meta, dict):
        meta = {}
    meta.setdefault("schema_version", "1.1")
    meta.setdefault("ingested_at", datetime.now(timezone.utc).isoformat())
    meta.setdefault("lesson_id", module_doc.get("lesson_id", ""))
    meta["source_script"] = "seed_firestore.py"
    module_doc["_meta"] = meta

    return module_id, module_doc


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
    except Exception as exc:
        log.error("  Failed: modules/%s -> %s", module_id, exc)
        return False


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
        if lesson_filter and lesson_filter.replace(".", "_") not in lesson_dir.name:
            continue

        module_path = lesson_dir / "module.yaml"
        concept_path = lesson_dir / "concept.yaml"
        questions_path = lesson_dir / "questions.yaml"

        if module_path.exists():
            module_doc = load_yaml(module_path)
            if not module_doc:
                log.warning("  Skipping %s - module.yaml parse failed", lesson_dir.name)
                failure += 1
                continue
            module_id, document = build_module_document_from_module_yaml(module_doc, chapter)
        else:
            if not concept_path.exists() or not questions_path.exists():
                log.warning("  Skipping %s - missing YAML files", lesson_dir.name)
                failure += 1
                continue

            concept = load_yaml(concept_path)
            questions = load_yaml(questions_path)
            if not concept or not questions:
                log.warning("  Skipping %s - YAML parse failed", lesson_dir.name)
                failure += 1
                continue
            module_id, document = build_module_document(concept, questions, chapter)

        q = document.get("quiz_questions", {})
        n_g = len(q.get("guided", []))
        n_i = len(q.get("independent", []))
        n_w = len(q.get("word_problems", []))

        log.info("  %-55s  guided:%-3d  ind:%-3d  word:%-3d",
                 module_id, n_g, n_i, n_w)

        if preview:
            safe_print(f"\n{'=' * 70}")
            safe_print(f"PREVIEW: modules/{module_id}")
            safe_print(f"{'=' * 70}")
            preview_doc = {k: v for k, v in document.items()
                           if k not in ("quiz_questions", "instructional_content")}
            safe_print(json.dumps(preview_doc, indent=2, default=str, ensure_ascii=False))
            safe_print(f"  instructional_content.concepts:           {len(document['instructional_content'].get('concepts', []))} items")
            safe_print(f"  instructional_content.example_walkthrough:{len(document['instructional_content'].get('example_walkthrough', []))} items")
            safe_print(f"  quiz_questions.guided:                    {n_g} items")
            safe_print(f"  quiz_questions.independent:               {n_i} items")
            safe_print(f"  quiz_questions.word_problems:             {n_w} items")

        ok = write_to_firestore(db, module_id, document,
                                overwrite=overwrite, dry_run=dry_run)
        if ok:
            success += 1
        else:
            failure += 1

    return success, failure


def build_arg_parser():
    p = argparse.ArgumentParser(
        description="Seed Firestore modules collection from GO Math YAML files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--data-dir", required=True, help="Chapter folder e.g. data\\chapter_01")
    p.add_argument("--chapter", required=True, type=int, help="Chapter number e.g. 1")
    p.add_argument("--grade", required=True, type=int, help="Grade level e.g. 4")
    p.add_argument("--subject", default="math", help="Subject (default: math)")
    p.add_argument("--lesson", default=None, help="Seed only this lesson e.g. '1.1'")
    p.add_argument("--project", default=None, help="Target Firebase/GCP project ID e.g. robot-tutor")
    p.add_argument("--creds", default=None, help="Path to Firebase service account JSON")
    p.add_argument("--dry-run", action="store_true", help="No writes; just log what would happen")
    p.add_argument("--preview", action="store_true", help="Print full document JSON before writing")
    p.add_argument("--overwrite", action="store_true", help="Replace documents fully (default: merge)")
    p.add_argument("--verbose", action="store_true", help="DEBUG logs")
    return p


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
                log.info("Auth:  Service account -> %s", creds_path)
            else:
                cred = credentials.ApplicationDefault()
                log.info("Auth:  Application Default Credentials")

            if not firebase_admin._apps:
                options = {"projectId": args.project} if args.project else None
                firebase_admin.initialize_app(cred, options)
            db = firestore.client()
            if args.project:
                log.info("Firestore: connected (project=%s)", args.project)
            else:
                log.info("Firestore: connected")
        except Exception as exc:
            log.error("Firestore init failed: %s", exc)
            return 1

    success, failure = process_chapter(
        data_dir=data_dir,
        chapter=args.chapter,
        grade=args.grade,
        subject=args.subject,
        lesson_filter=args.lesson,
        db=db,
        dry_run=args.dry_run,
        overwrite=args.overwrite,
        preview=args.preview,
    )

    log.info("")
    log.info("Done. %d seeded, %d failed.", success, failure)
    return 0 if failure == 0 else 1


if __name__ == "__main__":
    parser = build_arg_parser()
    args = parser.parse_args()
    sys.exit(run(args))
