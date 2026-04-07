"""Run order: 1) seed_modules.py, 2) seed_questions.py, 3) seed_dialogues.py.
Requirements note: `datasets` is needed for future babi_qa seeding (not used here).
"""

import json
import re
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore


def init_app() -> None:
    cred = credentials.ApplicationDefault()
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(cred, {"projectId": "robot-tutor"})


def _topic_to_module_id(topic: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", topic.lower()).strip("_")
    candidate = f"science_grade4_{slug}" if slug else "science_grade4_general"
    if candidate == "science_grade4_archimedes_principle":
        return candidate
    return "science_grade4_general"


def seed_dialogues() -> None:
    db = firestore.client()
    repo_root = Path(__file__).resolve().parents[2]
    conversations_path = repo_root / "data" / "Education-Dialogue-Dataset" / "conversations_train1.json"

    with conversations_path.open("r", encoding="utf-8") as infile:
        records = json.load(infile)

    for idx, record in enumerate(records, start=1):
        dialogue_id = f"dlg_science_{idx:03d}"
        background_info = record.get("background_info", {}) or {}
        topic = str(background_info.get("topic", "")).strip()
        module_id = _topic_to_module_id(topic)

        turns = []
        for turn in record.get("conversation", []):
            role = turn.get("role")
            text = turn.get("text", "")
            if role == "Teacher":
                turns.append(
                    {
                        "speaker": "reachy",
                        "text": text,
                        "expected_intent": None,
                    }
                )
            elif role == "Student":
                turns.append(
                    {
                        "speaker": "student",
                        "text": None,
                        "expected_intent": "provide_answer",
                    }
                )

        payload = {
            "dialogue_id": dialogue_id,
            "module_id": module_id,
            "subject_id": "science",
            "grade_level": 4,
            "turns": turns,
            "source": "Education-Dialogue-Dataset",
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        db.collection("dialogues").document(dialogue_id).set(payload)
        print(f"Created dialogue: {dialogue_id}")


if __name__ == "__main__":
    init_app()
    seed_dialogues()
