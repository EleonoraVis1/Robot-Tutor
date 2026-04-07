# Parser Gemini Handoff (Chapter 2.1)

## What We Confirmed
- The API failure was caused by an unsupported model ID, not by API key auth.
- Error observed:
  - `404 NOT_FOUND ... models/gemini-1.5-flash-latest is not found for API version v1beta, or is not supported for generateContent`
- This means the parser was reaching the Gemini endpoint, but with a deprecated/unsupported model name.

## Changes Already Made
- Updated Gemini model selection in:
  - `lib/parser/parse_chapter.py`
- New model strategy:
  - Primary: `gemini-2.5-flash`
  - Fallback: `gemini-2.0-flash`
- Updated Stage 2 log label to reflect new Gemini model strategy.

## Secret Handling Changes
- Added local key file:
  - `secrets/gemini_api_key.txt`
- Added ignore rule in `.gitignore`:
  - `secrets/gemini_api_key.txt`
- Status check showed `secrets/` is ignored by git.

## Environment/Dependency Findings
- `pdfplumber` was missing and installed.
- `google-generativeai` was installed, but parser imports `google.genai` from `google-genai`.
- `google-genai` was then installed successfully.

## Current Status
- Code changes are applied.
- Dependencies needed by this parser are installed in the shell environment used during debugging.
- Final end-to-end parse verification was started but manually interrupted before completion.

## Future Action Items
1. Re-run the parser command and confirm no `404 NOT_FOUND` on Gemini model call.
2. Validate output YAML for Lesson 2.1 (required keys, no `# TODO` placeholders if possible).
3. If model issues continue, add a CLI `--model` option to avoid future hardcoded model breakage.
4. Rotate the exposed Gemini API key (it appeared in chat history) and update `secrets/gemini_api_key.txt`.

## Commands To Resume Later
Use these exact commands from repo root:

```powershell
# 1) Load API key from local ignored file for current shell
$env:GEMINI_API_KEY = Get-Content -Path secrets\gemini_api_key.txt -Raw

# 2) Re-run the same lesson parse
python lib\parser\parse_chapter.py --pdf lib\parser\gomath_g4_ca.pdf --pages 57-114 --chapter 2 --grade 4 --lesson 2.1
```

Optional quick checks:

```powershell
# Check model references in parser code
rg -n "gemini-2.5-flash|gemini-2.0-flash|gemini-1.5-flash-latest" lib\parser\parse_chapter.py -S

# Inspect output files after run
Get-ChildItem data\mnt\user-data\outputs\chapter_02\lesson_2_1_multiplication_comparisons
```

## Notes
- Keep `secrets/gemini_api_key.txt` local-only.
- Do not commit API keys.

codex resume 019cbce7-60dc-7551-bcfa-482785f59e9b
