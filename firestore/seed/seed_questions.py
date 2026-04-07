"""Run order: 1) seed_modules.py, 2) seed_questions.py, 3) seed_dialogues.py.
Requirements note: `datasets` is needed for future babi_qa seeding (not used here).
"""

import json
import re
from collections import defaultdict
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore


def init_app() -> None:
    cred = credentials.ApplicationDefault()
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(cred, {"projectId": "robot-tutor"})


def _extract_grade_school_math_answer(answer_text: str) -> tuple[str, str]:
    match = re.findall(r"####\s*([^\n\r]+)", answer_text)
    final_answer = match[-1].strip() if match else ""

    explanation = answer_text.split("####", 1)[0]
    explanation = re.sub(r"<<.*?>>", "", explanation)
    explanation = explanation.strip()
    return final_answer, explanation


def _to_float(value: object) -> float | None:
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def seed_questions() -> None:
    db = firestore.client()
    repo_root = Path(__file__).resolve().parents[2]

    gsm_path = repo_root / "data" / "grade-school-math" / "grade_school_math" / "data" / "train.jsonl"
    with gsm_path.open("r", encoding="utf-8") as infile:
        for idx, line in enumerate(infile, start=1):
            if idx > 50:
                break
            if not line.strip():
                continue

            record = json.loads(line)
            question_id = f"q_math_grade3_wordproblems_{idx:03d}"
            answer, explanation = _extract_grade_school_math_answer(record.get("answer", ""))
            payload = {
                "question_id": question_id,
                "module_id": "math_grade3_wordproblems",
                "subject_id": "math",
                "grade_level": 3,
                "type": "quiz",
                "prompt": record.get("question", ""),
                "answer": answer,
                "explanation": explanation,
                "hints": [],
                "media_url": None,
                "source": "grade-school-math",
                "created_at": firestore.SERVER_TIMESTAMP,
            }
            db.collection("questions").document(question_id).set(payload)
            print(f"Created question: {question_id}")

    subcategory_to_module = {
        "add_or_sub": ("math_grade1_addition_subtraction", 1),
        "arithmetic_mixed": ("math_grade3_arithmetic", 3),
        "div": ("math_grade4_division", 4),
        "sequence_next_term": ("math_grade5_sequences", 5),
    }
    counters: defaultdict[str, int] = defaultdict(int)

    arithmetic_path = repo_root / "data" / "math_elem" / "I_Arithmetic" / "arithmetic_100.json"
    with arithmetic_path.open("r", encoding="utf-8") as infile:
        for line in infile:
            if not line.strip():
                continue
            record = json.loads(line)
            subcategory = str(record.get("subcategory", "")).strip()
            if subcategory not in subcategory_to_module:
                continue

            if subcategory == "arithmetic_mixed":
                numeric_answer = _to_float(record.get("answer"))
                if numeric_answer is not None and numeric_answer > 10000:
                    continue

            counters[subcategory] += 1
            question_id = f"q_math_{subcategory}_{counters[subcategory]:03d}"
            module_id, grade_level = subcategory_to_module[subcategory]
            reasoning = record.get("reasoning")
            payload = {
                "question_id": question_id,
                "module_id": module_id,
                "subject_id": "math",
                "grade_level": grade_level,
                "type": "instructional",
                "prompt": record.get("question", ""),
                "answer": str(record.get("answer", "")),
                "explanation": reasoning if reasoning is not None else "",
                "hints": [],
                "media_url": None,
                "source": "math_elem",
                "created_at": firestore.SERVER_TIMESTAMP,
            }
            db.collection("questions").document(question_id).set(payload)
            print(f"Created question: {question_id}")


if __name__ == "__main__":
    init_app()
    seed_questions()
