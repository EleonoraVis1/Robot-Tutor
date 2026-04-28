"""
_yaml_validator.py
------------------
Validates parsed YAML output against BAY-min schema v1.1.

Used by both parse_chapter.py (textbook) and parse_upload.py (user uploads)
to catch Gemini hallucinations / schema drift before Firestore ingestion.

Usage:
    from lib.parser._yaml_validator import validate_concept, validate_questions, ValidationError
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any


class ValidationError(Exception):
    """Raised when a YAML document fails schema validation."""
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__("\n".join(f"  - {e}" for e in errors))


@dataclass
class ValidationResult:
    valid: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def raise_if_invalid(self):
        if not self.valid:
            raise ValidationError(self.errors)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _require(errors: list, doc: dict, *keys: str, label: str = ""):
    """Append an error if any key in keys is missing from doc."""
    for key in keys:
        if key not in doc:
            errors.append(f"Missing required field '{key}'" + (f" in {label}" if label else ""))


def _require_string(errors: list, doc: dict, key: str, label: str = ""):
    if key not in doc:
        errors.append(f"Missing field '{key}'" + (f" in {label}" if label else ""))
    elif not isinstance(doc[key], str) or not doc[key].strip():
        errors.append(f"Field '{key}' must be a non-empty string" + (f" in {label}" if label else ""))


def _require_list(errors: list, doc: dict, key: str, min_len: int = 0, label: str = ""):
    if key not in doc:
        errors.append(f"Missing field '{key}'" + (f" in {label}" if label else ""))
    elif not isinstance(doc[key], list):
        errors.append(f"Field '{key}' must be a list" + (f" in {label}" if label else ""))
    elif len(doc[key]) < min_len:
        errors.append(
            f"Field '{key}' must have at least {min_len} items (got {len(doc[key])})"
            + (f" in {label}" if label else "")
        )


def _validate_question(q: Any, qid_prefix: str, idx: int) -> list[str]:
    """Validate a single question dict. Returns list of error strings."""
    errs = []
    label = f"question[{idx}] (id={q.get('id', '?')})"

    if not isinstance(q, dict):
        return [f"{qid_prefix}[{idx}] is not a dict"]

    _require_string(errs, q, "id", label)
    _require_string(errs, q, "prompt", label)
    _require_string(errs, q, "correct_answer", label)

    if "type" not in q:
        errs.append(f"Missing field 'type' in {label}")
    elif q["type"] != "multiple_choice":
        errs.append(f"Field 'type' must be 'multiple_choice' in {label} (got '{q['type']}')")

    if "options" not in q:
        errs.append(f"Missing field 'options' in {label}")
    elif not isinstance(q["options"], list):
        errs.append(f"Field 'options' must be a list in {label}")
    elif len(q["options"]) != 3:
        errs.append(
            f"Field 'options' must have exactly 3 items in {label} "
            f"(got {len(q['options'])})"
        )
    else:
        # Validate correct_answer matches one of the options
        if "correct_answer" in q and q["correct_answer"] not in q["options"]:
            errs.append(
                f"'correct_answer' does not match any option in {label}. "
                f"correct_answer='{q['correct_answer']}', "
                f"options={q['options']}"
            )

    return errs


# ---------------------------------------------------------------------------
# Public validators
# ---------------------------------------------------------------------------
def validate_concept(doc: Any) -> ValidationResult:
    """
    Validate a parsed concept.yaml document.

    Args:
        doc: Parsed YAML dict (already loaded via yaml.safe_load).

    Returns:
        ValidationResult with .valid, .errors, .warnings.
    """
    errors: list[str] = []
    warnings: list[str] = []

    if not isinstance(doc, dict):
        return ValidationResult(valid=False, errors=["Root document must be a YAML mapping (dict)"])

    # Required top-level fields
    _require_string(errors, doc, "lesson_id")
    _require_string(errors, doc, "title")

    if "cite_only" not in doc:
        warnings.append("'cite_only' field missing; defaulting to false")
    elif not isinstance(doc["cite_only"], bool):
        errors.append("'cite_only' must be a boolean (true/false)")

    cite_only = doc.get("cite_only", False)

    # standard_tags
    if "standard_tags" not in doc:
        warnings.append("'standard_tags' missing; RAG tagging will be degraded")
    elif not isinstance(doc["standard_tags"], list):
        errors.append("'standard_tags' must be a list")

    # instructional_content
    if "instructional_content" not in doc:
        if not cite_only:
            errors.append("'instructional_content' is required when cite_only is false")
    else:
        ic = doc["instructional_content"]
        if not isinstance(ic, dict):
            errors.append("'instructional_content' must be a mapping")
        else:
            if not cite_only:
                _require_string(errors, ic, "text", "instructional_content")
                _require_string(errors, ic, "example_walkthrough", "instructional_content")
                _require_list(errors, ic, "concepts", min_len=1, label="instructional_content")
            else:
                # cite_only: fields present but may be empty strings — just warn
                for key in ("text", "example_walkthrough", "concepts"):
                    if key not in ic:
                        warnings.append(
                            f"'instructional_content.{key}' missing in cite_only lesson; "
                            "Firestore will store empty value"
                        )

    # citation
    if "citation" not in doc:
        warnings.append("'citation' block missing; provenance metadata will be incomplete")
    else:
        cit = doc["citation"]
        if not isinstance(cit, dict):
            errors.append("'citation' must be a mapping")
        else:
            _require_string(errors, cit, "textbook", "citation")
            _require(errors, cit, "chapter", label="citation")
            _require_string(errors, cit, "lesson", "citation")
            _require_string(errors, cit, "pages", "citation")

    return ValidationResult(valid=len(errors) == 0, errors=errors, warnings=warnings)


def validate_questions(doc: Any) -> ValidationResult:
    """
    Validate a parsed questions.yaml document.

    Args:
        doc: Parsed YAML dict.

    Returns:
        ValidationResult with .valid, .errors, .warnings.
    """
    errors: list[str] = []
    warnings: list[str] = []

    if not isinstance(doc, dict):
        return ValidationResult(valid=False, errors=["Root document must be a YAML mapping (dict)"])

    _require_string(errors, doc, "lesson_id")
    _require_string(errors, doc, "title")

    question_sections = {
        "guided":       {"min": 2, "warn_min": 3},
        "independent":  {"min": 2, "warn_min": 3},
        "word_problems":{"min": 1, "warn_min": 2},
    }

    for section, config in question_sections.items():
        if section not in doc:
            errors.append(f"Missing question section '{section}'")
            continue

        if not isinstance(doc[section], list):
            errors.append(f"'{section}' must be a list")
            continue

        count = len(doc[section])
        if count < config["min"]:
            errors.append(
                f"'{section}' has {count} question(s); minimum is {config['min']}"
            )
        elif count < config["warn_min"]:
            warnings.append(
                f"'{section}' has only {count} question(s); "
                f"recommend at least {config['warn_min']}"
            )

        for i, q in enumerate(doc[section]):
            errors.extend(_validate_question(q, section, i))

        # Check for duplicate IDs within section
        ids = [q.get("id") for q in doc[section] if isinstance(q, dict) and "id" in q]
        if len(ids) != len(set(ids)):
            from collections import Counter
            dupes = [qid for qid, cnt in Counter(ids).items() if cnt > 1]
            errors.append(f"Duplicate question IDs in '{section}': {dupes}")

    # Check for duplicate IDs across all sections
    all_ids = []
    for section in question_sections:
        if isinstance(doc.get(section), list):
            all_ids.extend(
                q.get("id") for q in doc[section]
                if isinstance(q, dict) and "id" in q
            )
    from collections import Counter
    cross_dupes = [qid for qid, cnt in Counter(all_ids).items() if cnt > 1]
    if cross_dupes:
        errors.append(f"Duplicate question IDs across sections: {cross_dupes}")

    return ValidationResult(valid=len(errors) == 0, errors=errors, warnings=warnings)


def validate_pair(concept_doc: Any, questions_doc: Any) -> ValidationResult:
    """
    Validate a concept + questions pair together.
    Checks that lesson_ids match between the two documents.
    """
    errors: list[str] = []
    warnings: list[str] = []

    cr = validate_concept(concept_doc)
    qr = validate_questions(questions_doc)

    errors.extend([f"[concept] {e}" for e in cr.errors])
    errors.extend([f"[questions] {e}" for e in qr.errors])
    warnings.extend([f"[concept] {w}" for w in cr.warnings])
    warnings.extend([f"[questions] {w}" for w in qr.warnings])

    # Cross-document consistency
    c_id = concept_doc.get("lesson_id") if isinstance(concept_doc, dict) else None
    q_id = questions_doc.get("lesson_id") if isinstance(questions_doc, dict) else None
    if c_id and q_id and c_id != q_id:
        errors.append(
            f"lesson_id mismatch: concept has '{c_id}', questions has '{q_id}'"
        )

    c_title = concept_doc.get("title") if isinstance(concept_doc, dict) else None
    q_title = questions_doc.get("title") if isinstance(questions_doc, dict) else None
    if c_title and q_title and c_title != q_title:
        warnings.append(
            f"title mismatch: concept='{c_title}', questions='{q_title}' — "
            "ensure these are the same lesson"
        )

    return ValidationResult(valid=len(errors) == 0, errors=errors, warnings=warnings)
