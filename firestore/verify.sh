#!/usr/bin/env bash
set -euo pipefail

echo "Listing active Firestore indexes..."
firebase firestore:indexes

echo
echo "Listing bucket root to confirm folder structure..."
gcloud storage ls gs://robot-tutor.firebasestorage.app/

echo
echo "Manual checklist:"
echo "- [ ] Open Firebase Console > Firestore > Data"
echo "- [ ] Confirm 'subjects' collection exists with docs: math, english, science, custom"
