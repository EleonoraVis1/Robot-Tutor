#!/usr/bin/env python3
"""
pipeline_job.py
---------------
Cloud Run job: GCS upload -> parse_upload -> merge -> Firestore
Triggered by Eventarc when a PDF lands in raw-uploads/
"""
import logging
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)
STALE_JOB_TIMEOUT = timedelta(minutes=5)

# Add repo root to path so lib.parser imports work
sys.path.insert(0, str(Path(__file__).parents[1]))


def _get_blob_with_retry(bucket, object_path: str, attempts: int = 5, delay_seconds: float = 1.5):
    """Retry GCS lookup briefly because finalize events can arrive before reads settle."""
    blob = bucket.blob(object_path)

    for attempt in range(1, attempts + 1):
        if blob.exists():
            if attempt > 1:
                log.info("GCS object became available on attempt %d: %s", attempt, object_path)
            return blob

        if attempt < attempts:
            log.warning(
                "GCS object not yet readable (attempt %d/%d): %s",
                attempt,
                attempts,
                object_path,
            )
            time.sleep(delay_seconds)

    raise FileNotFoundError(f"GCS object not found after {attempts} attempts: {object_path}")


def _slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def _coerce_int(value, default: int = 0) -> int:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def _coerce_text(value, default: str = "") -> str:
    if value is None:
        return default
    text = str(value).strip()
    return text if text else default


def _coerce_list(value) -> list:
    return value if isinstance(value, list) else []


def _coerce_lesson_value(value):
    if value is None:
        return "Upload"
    if isinstance(value, int):
        return value
    text = str(value).strip()
    if not text:
        return "Upload"
    try:
        return int(text)
    except ValueError:
        return text


def _normalize_subject_id(subject_name: str) -> str:
    subject_slug = _slugify(subject_name)
    subject_map = {
        "math": "math",
        "mathematics": "math",
        "english": "english",
        "ela": "english",
        "reading": "english",
        "science": "science",
    }
    return subject_map.get(subject_slug, subject_slug or "custom")


def _normalize_citation(concept_doc: dict, *, chapter: int, lesson, source_type: str) -> dict:
    citation = concept_doc.get("citation", {})
    if not isinstance(citation, dict):
        citation = {}

    pages = citation.get("pages")
    if not isinstance(pages, list):
        pages = pages if pages else "uploaded document"

    textbook_default = (
        "Not specified (Worksheet)"
        if source_type == "worksheet"
        else "Not specified (Uploaded document)"
    )

    return {
        "textbook": _coerce_text(citation.get("textbook"), textbook_default),
        "chapter": _coerce_int(citation.get("chapter"), chapter),
        "lesson": citation.get("lesson", lesson),
        "pages": pages,
    }


def _build_upload_module_id(subject_id: str, grade_level: int, chapter: int, lesson, title: str) -> str:
    lesson_slug = _slugify(str(lesson)) or "upload"
    title_slug = _slugify(title) or "uploaded_document"
    return f"{subject_id}_grade{grade_level}_ch{chapter}_les{lesson_slug}_{title_slug}"


def _build_lesson_id(subject_id: str, grade_level: int, chapter: int, lesson, object_path: str) -> str:
    if isinstance(lesson, int):
        return f"{subject_id}_g{grade_level}_ch{chapter}_l{lesson}"
    return f"upload_{_slugify(Path(object_path).stem)}"


def _extract_question_sections(questions_doc: dict) -> dict:
    question_block = questions_doc.get("questions", questions_doc)
    if not isinstance(question_block, dict):
        question_block = {}
    return {
        "guided": _coerce_list(question_block.get("guided")),
        "independent": _coerce_list(question_block.get("independent")),
        "word_problems": _coerce_list(question_block.get("word_problems")),
    }


def _parse_started_at(value) -> datetime | None:
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None

    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _is_stale_in_progress(started_at_value, *, now: datetime | None = None) -> bool:
    started_at = _parse_started_at(started_at_value)
    if started_at is None:
        return True
    now = now or datetime.now(timezone.utc)
    return now - started_at > STALE_JOB_TIMEOUT


def _build_module_document(
    *,
    title: str,
    grade: str,
    subject_name: str,
    chapter,
    lesson,
    source_type: str,
    concept_doc: dict,
    questions_doc: dict,
    object_path: str,
) -> dict:
    instructional_content = concept_doc.get("instructional_content", {})
    title = title or concept_doc.get("title") or Path(object_path).stem.replace("_", " ").title()
    grade_level = _coerce_int(grade, _coerce_int(concept_doc.get("grade"), 4))
    grade_value = _coerce_text(grade, concept_doc.get("grade") or str(grade_level))

    subject_id = _normalize_subject_id(subject_name or concept_doc.get("subject") or "custom")
    subject_value = _coerce_text(subject_name, concept_doc.get("subject") or subject_id)
    chapter_value = _coerce_int(chapter, _coerce_int(concept_doc.get("chapter"), 0))
    lesson_value = _coerce_lesson_value(lesson if lesson is not None else concept_doc.get("lesson"))
    unit_value = _coerce_int(chapter, _coerce_int(concept_doc.get("unit"), chapter_value))
    lesson_id = _build_lesson_id(
        subject_id=subject_id,
        grade_level=grade_level,
        chapter=chapter_value,
        lesson=lesson_value,
        object_path=object_path,
    )
    standard_tags = [
        _coerce_text(tag) for tag in concept_doc.get("standard_tags", concept_doc.get("standards", []))
        if _coerce_text(tag)
    ]
    citation = _normalize_citation(
        concept_doc,
        chapter=chapter_value,
        lesson=lesson_value,
        source_type=source_type,
    )
    has_visual = bool(concept_doc.get("has_visual", concept_doc.get("cite_only", False)))
    visual_handling = _coerce_text(
        concept_doc.get("visual_handling"),
        "cite_only" if concept_doc.get("cite_only", False) else "",
    )
    visual_description = _coerce_text(concept_doc.get("visual_description"))
    concepts = _coerce_list(concept_doc.get("concepts")) or _coerce_list(instructional_content.get("concepts"))
    worked_examples = _coerce_list(concept_doc.get("worked_examples"))
    example_walkthrough = instructional_content.get("example_walkthrough")
    if not example_walkthrough and worked_examples:
        example_walkthrough = worked_examples
    questions = _extract_question_sections(questions_doc)
    now = datetime.now(timezone.utc)
    merged_at = now.isoformat()
    description = _coerce_text(
        concept_doc.get("description") or concept_doc.get("essential_question"),
        _coerce_text(instructional_content.get("text"))[:500],
    )
    essential_question = _coerce_text(
        concept_doc.get("essential_question"),
        description,
    )
    module_id = _build_upload_module_id(
        subject_id=subject_id,
        grade_level=grade_level,
        chapter=chapter_value,
        lesson=lesson_value,
        title=title,
    )

    return {
        "module_id": module_id,
        "title": title,
        "description": description,
        "essential_question": essential_question,
        "grade": grade_value,
        "grade_level": grade_level,
        "subject": subject_value,
        "subject_id": subject_id,
        "session_mode": "teach_then_quiz",
        "source": "pipeline",
        "created_at": now,
        "standard_tags": standard_tags,
        "standards": standard_tags,
        "prerequisites": _coerce_list(concept_doc.get("prerequisites")),
        "instructional_content": {
            "text": _coerce_text(instructional_content.get("text")),
            "concepts": _coerce_list(instructional_content.get("concepts")),
            "example_walkthrough": example_walkthrough if example_walkthrough is not None else "",
        },
        "chapter": chapter_value,
        "lesson": lesson_value,
        "lesson_id": lesson_id,
        "unit": unit_value,
        "citation": citation,
        "has_visual": has_visual,
        "visual_description": visual_description,
        "visual_handling": visual_handling,
        "concepts": concepts,
        "worked_examples": worked_examples,
        "mathematical_practices": _coerce_list(concept_doc.get("mathematical_practices")),
        "quiz_questions": questions,
        "_meta": {
            "schema_version": "1.1",
            "ingested_at": now.isoformat(),
            "merged_at": merged_at,
            "lesson_id": lesson_id,
            "source_files": {
                "concept": "concept.yaml",
                "questions": "questions.yaml",
                "source_script": "pipeline_job.py",
            },
            "object_path": object_path,
            "generated_by": "cloudrun.pipeline_job",
        },
    }


def main() -> int:
    # --- 1. Env vars ---
    bucket_name = os.environ.get("GCS_BUCKET", "robot-tutor.firebasestorage.app")
    object_path = os.environ.get("GCS_OBJECT_PATH")
    gemini_key = os.environ.get("GEMINI_API_KEY")
    gcp_project = os.environ.get("GCP_PROJECT", "robot-tutor")

    if not object_path:
        log.error("GCS_OBJECT_PATH not set")
        return 1
    if not gemini_key:
        log.error("GEMINI_API_KEY not set")
        return 1

    os.environ["GEMINI_API_KEY"] = gemini_key
    # --- 2. Init Firebase ---
    import firebase_admin
    from firebase_admin import credentials, firestore
    from google.cloud import storage
    from google.cloud.exceptions import Conflict

    if not firebase_admin._apps:
        creds_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if creds_path:
            cred = credentials.Certificate(creds_path)
            firebase_admin.initialize_app(cred)
        else:
            firebase_admin.initialize_app()  # uses ADC on Cloud Run
    db = firestore.client()

    # --- 3. Download PDF + read metadata ---
    gcs_client = storage.Client(project=gcp_project)
    bucket = gcs_client.bucket(bucket_name)
    blob = _get_blob_with_retry(bucket, object_path)
    blob.reload()
    generation = blob.generation
    job_key = f"{object_path.replace('/', '_')}_{generation}"
    job_ref = db.collection("upload_jobs").document(job_key)
    started_at = datetime.now(timezone.utc).isoformat()
    lock_payload = {
        "status": "in_progress",
        "object_path": object_path,
        "generation": generation,
        "started_at": started_at,
        "processed_at": None,
        "error_message": None,
    }
    try:
        job_ref.create(lock_payload)
    except Conflict:
        job_doc = job_ref.get()
        job_data = job_doc.to_dict() or {}
        existing_status = job_data.get("status")
        if existing_status == "complete":
            log.info("Skipping duplicate event - job %s already %s", job_key, existing_status)
            return 0
        if existing_status == "in_progress":
            if _is_stale_in_progress(job_data.get("started_at")):
                log.warning("Stale job detected for %s; reclaiming lock", job_key)
                job_ref.set(lock_payload, merge=True)
            else:
                log.info("Skipping duplicate event - job %s already %s", job_key, existing_status)
                return 0
        if existing_status == "error":
            job_ref.set(lock_payload, merge=True)
            log.info("Retrying previously errored job %s", job_key)
        elif existing_status not in ("complete", "in_progress"):
            log.warning(
                "Skipping duplicate event - job %s has unexpected status %r",
                job_key,
                existing_status,
            )
            return 0

    meta = blob.metadata or {}

    subject = meta.get("subject_name") or meta.get("subject") or "Custom Upload"
    grade = meta.get("grade_level") or meta.get("grade") or "4"
    source_type = meta.get("source_type", "worksheet")
    chapter = meta.get("chapter", "0")
    lesson = meta.get("lesson", "0")

    log.info(
        "Processing: %s | subject=%s grade=%s chapter=%s lesson=%s",
        object_path,
        subject,
        grade,
        chapter,
        lesson,
    )

    try:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pdf_path = tmp_path / Path(object_path).name
            out_dir = tmp_path / "output"
            out_dir.mkdir()

            # --- 4. Download ---
            log.info("Downloading PDF...")
            blob.download_to_filename(str(pdf_path))

            # --- 5. Parse ---
            log.info("Parsing PDF...")
            from lib.parser.parse_upload import process_upload

            concept_doc, questions_doc = process_upload(
                input_path=pdf_path,
                out_dir=out_dir,
                upload_subject=subject,
                upload_grade=str(grade),
                upload_chapter=str(chapter),
                upload_lesson=str(lesson),
            )

            # --- 6. Seed Firestore ---
            module = _build_module_document(
                title=concept_doc.get("title", ""),
                grade=grade,
                subject_name=subject,
                chapter=chapter,
                lesson=lesson,
                source_type=source_type,
                concept_doc=concept_doc,
                questions_doc=questions_doc,
                object_path=object_path,
            )
            module_id = module["module_id"]

            log.info("Seeding Firestore: modules/%s", module_id)
            db.collection("modules").document(module_id).set(module, merge=True)

            # --- 8. Move GCS object to processed/ ---
            new_path = object_path.replace("raw-uploads/", "processed/", 1)
            log.info("Moving GCS object to %s", new_path)
            bucket.copy_blob(blob, bucket, new_path)
            blob.delete()

            # --- 9. Write success status ---
            job_ref.set({
                "status": "complete",
                "module_id": module_id,
                "object_path": object_path,
                "generation": generation,
                "started_at": started_at,
                "processed_at": datetime.now(timezone.utc).isoformat(),
                "error_message": None,
            })

            log.info("Pipeline complete: %s", module_id)

    except Exception as exc:
        log.error("Pipeline failed: %s", exc, exc_info=True)
        try:
            job_ref.set({
                "status": "error",
                "error_message": str(exc),
                "processed_at": datetime.now(timezone.utc).isoformat(),
            }, merge=True)
        except Exception:
            pass
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
