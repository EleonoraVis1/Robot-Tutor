from __future__ import annotations

import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import firebase_admin
import yaml
from firebase_admin import credentials, firestore
from google.cloud import storage

REPO_ROOT = Path(__file__).resolve().parents[1]
PARSER_DIR = REPO_ROOT / "lib" / "parser"

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(PARSER_DIR) not in sys.path:
    sys.path.insert(0, str(PARSER_DIR))

from merge_lesson_yaml import merge_lesson_dir
from parse_upload import filename_to_slug, process_upload


def get_required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def init_firestore(project_id: str):
    creds_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if creds_path:
        cred = credentials.Certificate(creds_path)
    else:
        cred = credentials.ApplicationDefault()

    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred, {"projectId": project_id})

    return firestore.client()


def apply_metadata_defaults(path: Path, metadata: dict[str, str]) -> None:
    if not path.exists():
        return

    with path.open(encoding="utf-8") as handle:
        doc = yaml.safe_load(handle) or {}

    if not isinstance(doc, dict):
        raise RuntimeError(f"Expected YAML object in {path}")

    doc["subject"] = metadata["subject"]
    doc["grade"] = metadata["grade"]
    doc["grade_level"] = metadata["grade"]
    doc["chapter"] = metadata["chapter"]
    doc["lesson"] = metadata["lesson"]
    doc["source_type"] = metadata["source_type"]

    with path.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(doc, handle, sort_keys=False, allow_unicode=True, width=120)


def load_module_yaml(module_yaml_path: Path) -> dict:
    with module_yaml_path.open(encoding="utf-8") as handle:
        module_doc = yaml.safe_load(handle) or {}
    if not isinstance(module_doc, dict):
        raise RuntimeError(f"Expected YAML object in {module_yaml_path}")
    module_id = str(module_doc.get("module_id", "")).strip()
    if not module_id:
        raise RuntimeError(f"module_id missing in {module_yaml_path}")
    return module_doc


def write_job_status(
    db,
    slug: str,
    *,
    status: str,
    module_id: str | None,
    error_message: str,
) -> None:
    db.collection("upload_jobs").document(slug).set(
        {
            "status": status,
            "module_id": module_id,
            "processed_at": datetime.now(timezone.utc),
            "error_message": error_message,
        },
        merge=True,
    )


def processed_object_path(object_path: str) -> str:
    raw_prefix = "raw-uploads/"
    processed_prefix = "processed/"
    if object_path.startswith(raw_prefix):
        return processed_prefix + object_path[len(raw_prefix):]
    return processed_prefix + object_path.lstrip("/")


def move_blob(bucket, source_path: str, destination_path: str) -> None:
    source_blob = bucket.blob(source_path)
    if not source_blob.exists():
        raise RuntimeError(f"GCS object not found during move: {source_path}")
    bucket.copy_blob(source_blob, bucket, new_name=destination_path)
    source_blob.delete()


def main() -> int:
    bucket_name = os.environ.get("GCS_BUCKET", "robot-tutor.firebasestorage.app").strip()
    object_path = get_required_env("GCS_OBJECT_PATH")
    gemini_api_key = get_required_env("GEMINI_API_KEY")
    project_id = os.environ.get("GCP_PROJECT", "robot-tutor").strip() or "robot-tutor"
    creds_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()

    if creds_path:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = creds_path
    os.environ["GEMINI_API_KEY"] = gemini_api_key

    slug = filename_to_slug(Path(object_path).name)
    db = init_firestore(project_id)
    storage_client = storage.Client(project=project_id)
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_path)

    try:
        if not blob.exists():
            raise RuntimeError(f"GCS object not found: {object_path}")

        metadata = {
            "subject": "math",
            "grade": "4",
            "chapter": "0",
            "lesson": "0",
            "source_type": "worksheet",
        }
        blob.reload()
        for key in metadata:
            if blob.metadata and blob.metadata.get(key):
                metadata[key] = str(blob.metadata[key]).strip()

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            pdf_path = tmp_path / Path(object_path).name
            out_dir = tmp_path / "parsed"
            blob.download_to_filename(str(pdf_path))

            process_upload(
                input_path=pdf_path,
                out_dir=out_dir,
                subject=metadata["subject"],
                grade=metadata["grade"],
                source_type=metadata["source_type"],
                api_key=gemini_api_key,
            )

            lesson_dir = out_dir / slug
            if not lesson_dir.exists():
                raise RuntimeError(f"Expected parsed lesson directory: {lesson_dir}")

            apply_metadata_defaults(lesson_dir / "concept.yaml", metadata)
            apply_metadata_defaults(lesson_dir / "questions.yaml", metadata)

            if not merge_lesson_dir(lesson_dir):
                raise RuntimeError(f"Failed to merge lesson YAML in {lesson_dir}")

            module_doc = load_module_yaml(lesson_dir / "module.yaml")
            module_id = str(module_doc["module_id"]).strip()
            db.collection("modules").document(module_id).set(module_doc)

        move_blob(bucket, object_path, processed_object_path(object_path))
        write_job_status(
            db,
            slug,
            status="processed",
            module_id=module_id,
            error_message="",
        )
        return 0
    except Exception as exc:
        error_message = str(exc)
        try:
            write_job_status(
                db,
                slug,
                status="error",
                module_id=None,
                error_message=error_message,
            )
        except Exception:
            pass
        print(error_message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
