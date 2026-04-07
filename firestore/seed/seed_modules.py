"""Run order: 1) seed_modules.py, 2) seed_questions.py, 3) seed_dialogues.py.
Requirements note: `datasets` is needed for future babi_qa seeding (not used here).
"""

import firebase_admin
from firebase_admin import credentials, firestore


def init_app() -> None:
    cred = credentials.ApplicationDefault()
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(cred, {"projectId": "robot-tutor"})


def seed_modules() -> None:
    db = firestore.client()

    modules = [
        {
            "module_id": "math_grade1_addition_subtraction",
            "title": "Addition and Subtraction",
            "description": "Learn to add and subtract numbers.",
            "grade_level": 1,
            "subject_id": "math",
            "session_mode": "teach_then_quiz",
            "source": "manual",
            "standard_tags": ["CCSS.MATH.CONTENT.1.OA.A.1"],
            "prerequisites": [],
        },
        {
            "module_id": "math_grade3_arithmetic",
            "title": "Arithmetic Operations",
            "description": "Practice mixed arithmetic operations including multiplication and division.",
            "grade_level": 3,
            "subject_id": "math",
            "session_mode": "teach_then_quiz",
            "source": "manual",
            "standard_tags": ["CCSS.MATH.CONTENT.3.OA.A.1"],
            "prerequisites": ["math_grade1_addition_subtraction"],
        },
        {
            "module_id": "math_grade3_wordproblems",
            "title": "Word Problems",
            "description": "Solve real-world word problems using multiple operations.",
            "grade_level": 3,
            "subject_id": "math",
            "session_mode": "teach_then_quiz",
            "source": "manual",
            "standard_tags": ["CCSS.MATH.CONTENT.3.OA.D.8"],
            "prerequisites": ["math_grade3_arithmetic"],
        },
        {
            "module_id": "math_grade4_division",
            "title": "Division",
            "description": "Understand and practice division of whole numbers.",
            "grade_level": 4,
            "subject_id": "math",
            "session_mode": "teach_then_quiz",
            "source": "manual",
            "standard_tags": ["CCSS.MATH.CONTENT.4.NBT.B.6"],
            "prerequisites": ["math_grade3_arithmetic"],
        },
        {
            "module_id": "math_grade5_sequences",
            "title": "Number Sequences",
            "description": "Identify patterns and find the next term in number sequences.",
            "grade_level": 5,
            "subject_id": "math",
            "session_mode": "teach_then_quiz",
            "source": "manual",
            "standard_tags": ["CCSS.MATH.CONTENT.5.OA.B.3"],
            "prerequisites": ["math_grade4_division"],
        },
        {
            "module_id": "science_grade4_archimedes_principle",
            "title": "Archimedes' Principle",
            "description": "Understand buoyancy and how objects float or sink in fluids.",
            "grade_level": 4,
            "subject_id": "science",
            "session_mode": "dialogue",
            "source": "manual",
            "standard_tags": [],
            "prerequisites": [],
        },
        {
            "module_id": "science_grade4_general",
            "title": "General Science",
            "description": "Explore general science concepts through guided dialogue.",
            "grade_level": 4,
            "subject_id": "science",
            "session_mode": "dialogue",
            "source": "manual",
            "standard_tags": [],
            "prerequisites": [],
        },
    ]

    for module in modules:
        payload = {
            **module,
            "instructional_content": {
                "text": "",
                "example_walkthrough": [],
            },
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        db.collection("modules").document(module["module_id"]).set(payload)
        print(f"Created module: {module['module_id']}")


if __name__ == "__main__":
    init_app()
    seed_modules()
