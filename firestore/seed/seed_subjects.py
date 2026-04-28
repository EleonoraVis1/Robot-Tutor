import firebase_admin
from firebase_admin import credentials, firestore


def init_app() -> None:
    cred = credentials.ApplicationDefault()
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(cred, {"projectId": "robot-tutor"})


def seed_subjects() -> None:
    db = firestore.client()

    subjects = [
        {
            "subject_id": "math",
            "name": "Mathematics",
            "description": "Elementary math concepts for K-6 students.",
            "icon_url": "gs://robot-tutor.firebasestorage.app/icons/math.png",
        },
        {
            "subject_id": "english",
            "name": "English / Reading",
            "description": "Vocabulary and reading comprehension for K-6 students.",
            "icon_url": "gs://robot-tutor.firebasestorage.app/icons/english.png",
        },
        {
            "subject_id": "science",
            "name": "Science",
            "description": "Elementary science concepts for K-6 students.",
            "icon_url": "gs://robot-tutor.firebasestorage.app/icons/science.png",
        },
        {
            "subject_id": "custom",
            "name": "Custom",
            "description": "Modules generated via supervisor upload pipeline.",
            "icon_url": "gs://robot-tutor.firebasestorage.app/icons/custom.png",
        },
    ]

    for subject in subjects:
        payload = {
            **subject,
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        db.collection("subjects").document(subject["subject_id"]).set(payload)
        print(f"Created subject: {subject['subject_id']}")


if __name__ == "__main__":
    init_app()
    seed_subjects()
