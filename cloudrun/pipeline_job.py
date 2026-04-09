#!/usr/bin/env python3
"""
pipeline_job.py
---------------
Cloud Run job: GCS upload -> parse_upload -> merge -> Firestore
Triggered by Eventarc when a PDF lands in raw-uploads/
"""
import logging
import os
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

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


def main():
    # --- 1. Env vars ---
    bucket_name = os.environ.get("GCS_BUCKET", "robot-tutor.firebasestorage.app")
    object_path = os.environ.get("GCS_OBJECT_PATH")
    gemini_key = os.environ.get("GEMINI_API_KEY")
    gcp_project = os.environ.get("GCP_PROJECT", "robot-tutor")

    if not object_path:
        log.error("GCS_OBJECT_PATH not set")
        os._exit(1)
    if not gemini_key:
        log.error("GEMINI_API_KEY not set")
        os._exit(1)

    os.environ["GEMINI_API_KEY"] = gemini_key
    slug = object_path.replace("/", "_").replace(".", "_")

    # --- 2. Init Firebase ---
    import firebase_admin
    from firebase_admin import credentials, firestore
    from google.cloud import storage

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
    meta = blob.metadata or {}

    subject = meta.get("subject_name") or meta.get("subject") or "math"
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

            process_upload(
                input_path=pdf_path,
                out_dir=out_dir,
                subject=subject,
                grade=grade,
                source_type=source_type,
            )

            # Find the output lesson dir (parse_upload creates a slug subdir)
            lesson_dirs = [d for d in out_dir.iterdir() if d.is_dir()]
            if not lesson_dirs:
                raise RuntimeError("parse_upload produced no output directory")
            lesson_dir = lesson_dirs[0]

            # --- 6. Merge ---
            log.info("Merging YAML...")
            from lib.parser.merge_lesson_yaml import merge_lesson_dir

            merge_lesson_dir(lesson_dir)

            # --- 7. Seed Firestore ---
            module_path = lesson_dir / "module.yaml"
            if not module_path.exists():
                raise RuntimeError("module.yaml not created by merge step")

            module = yaml.safe_load(module_path.read_text(encoding="utf-8"))
            module_id = module.get("module_id", slug)

            log.info("Seeding Firestore: modules/%s", module_id)
            db.collection("modules").document(module_id).set(module)

            # --- 8. Move GCS object to processed/ ---
            new_path = object_path.replace("raw-uploads/", "processed/", 1)
            log.info("Moving GCS object to %s", new_path)
            bucket.copy_blob(blob, bucket, new_path)
            blob.delete()

            # --- 9. Write success status ---
            db.collection("upload_jobs").document(slug).set({
                "status": "complete",
                "module_id": module_id,
                "object_path": object_path,
                "processed_at": datetime.now(timezone.utc).isoformat(),
                "error_message": None,
            })

            log.info("Pipeline complete: %s", module_id)

    except Exception as exc:
        log.error("Pipeline failed: %s", exc, exc_info=True)
        try:
            db.collection("upload_jobs").document(slug).set({
                "status": "error",
                "module_id": None,
                "object_path": object_path,
                "processed_at": datetime.now(timezone.utc).isoformat(),
                "error_message": str(exc),
            })
        except Exception:
            pass
        os._exit(1)

    os._exit(0)


if __name__ == "__main__":
    main()
