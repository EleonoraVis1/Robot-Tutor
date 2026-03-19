"""
_gemini_rest_patch.py
---------------------
Drop-in replacement for the Gemini SDK call in parse_chapter.py.

Your Chapter 2 failure is almost certainly this SDK call pattern:
    model = genai.GenerativeModel("gemini-1.5-flash")
    response = model.generate_content([system_prompt, user_prompt])

This fails because:
  1. Older SDK versions don't support passing a list to generate_content()
  2. System prompts must go in system_instruction=, not as a list item
  3. SDK version in jrdes conda env may not match what the code expects

This module replaces all of that with a raw REST call — zero SDK dependency.

HOW TO USE IN parse_chapter.py:
---------------------------------
Replace this pattern wherever it appears:

    # OLD (failing):
    import google.generativeai as genai
    genai.configure(api_key=os.environ["GEMINI_API_KEY"])
    model = genai.GenerativeModel("gemini-1.5-flash")
    response = model.generate_content([system_prompt, text_prompt])
    result_text = response.text

    # NEW (works anywhere):
    from lib.parser._gemini_rest_patch import gemini_text_call
    result_text = gemini_text_call(system_prompt + "\\n\\n" + text_prompt)

Or with the system/user split (cleaner):
    result_text = gemini_text_call(text_prompt, system=system_prompt)

That's it. No SDK import, no configure(), no GenerativeModel().
"""

from __future__ import annotations
import os
import time
import logging
from typing import Optional

import requests

log = logging.getLogger(__name__)

GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
DEFAULT_MODEL = "gemini-2.5-flash"


def gemini_text_call(
    prompt: str,
    *,
    system: Optional[str] = None,
    model: str = DEFAULT_MODEL,
    api_key: Optional[str] = None,
    temperature: float = 0.2,
    max_tokens: int = 4096,
    max_retries: int = 5,
    retry_delay: float = 15.0,
) -> str:
    """
    Call Gemini REST API with a text prompt. Returns response text.

    Args:
        prompt:      User prompt text.
        system:      Optional system instruction (prepended in user turn if provided,
                     since system_instruction is only in v1beta for some models).
        model:       Gemini model name (default: gemini-1.5-flash).
        api_key:     API key (default: GEMINI_API_KEY env var).
        temperature: Generation temperature (default 0.2 for structured YAML output).
        max_tokens:  Max output tokens (default 4096).
        max_retries: Retry attempts on rate limit / server error.
        retry_delay: Initial delay in seconds between retries (doubles each time).

    Returns:
        Response text string from Gemini.

    Raises:
        RuntimeError on API errors or empty responses.
    """
    key = api_key or os.environ.get("GEMINI_API_KEY")
    if not key:
        raise RuntimeError(
            "GEMINI_API_KEY not set. "
            "In PowerShell: $env:GEMINI_API_KEY = 'your_key_here'"
        )

    # Combine system + user if system is provided
    # The v1beta REST API does support system_instruction for flash models,
    # but prepending to user turn is more universally compatible.
    full_prompt = f"{system.strip()}\n\n{prompt.strip()}" if system else prompt.strip()

    url = f"{GEMINI_API_BASE}/{model}:generateContent?key={key}"
    payload = {
        "contents": [
            {"role": "user", "parts": [{"text": full_prompt}]}
        ],
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": max_tokens,
        },
    }

    delay = retry_delay
    last_error = None

    # Flat throttle before every API call so higher-level callers cannot burst
    # past the free-tier request ceiling.
    time.sleep(4)

    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.post(url, json=payload, timeout=60)

            if resp.status_code == 429:
                log.warning(
                    "Gemini rate limited (attempt %d/%d). Waiting %.0fs...",
                    attempt, max_retries, delay,
                )
                time.sleep(delay)
                delay *= 2
                continue

            if resp.status_code >= 500:
                log.warning(
                    "Gemini server error %d (attempt %d/%d). Waiting %.0fs...",
                    resp.status_code, attempt, max_retries, delay,
                )
                time.sleep(delay)
                delay *= 2
                continue

            if resp.status_code != 200:
                body = resp.text[:600]
                raise RuntimeError(
                    f"Gemini API returned HTTP {resp.status_code}:\n{body}\n\n"
                    f"Check your API key and model name ('{model}')."
                )

            data = resp.json()

            # Check for API-level error in 200 response (happens with bad model names)
            if "error" in data:
                err = data["error"]
                raise RuntimeError(
                    f"Gemini API error {err.get('code')}: {err.get('message')}\n"
                    f"Hint: check model name '{model}'. "
                    f"Valid names: gemini-1.5-flash, gemini-1.5-pro, gemini-2.0-flash-exp"
                )

            candidates = data.get("candidates", [])
            if not candidates:
                # Could be a safety filter block
                block_reason = data.get("promptFeedback", {}).get("blockReason", "unknown")
                raise RuntimeError(
                    f"Gemini returned no candidates. "
                    f"Block reason: {block_reason}. Full response: {data}"
                )

            finish_reason = candidates[0].get("finishReason", "")
            if finish_reason == "SAFETY":
                raise RuntimeError(
                    "Gemini blocked the response for safety reasons. "
                    "Review your prompt content."
                )

            content = candidates[0].get("content", {})
            parts = content.get("parts", [])
            text = "".join(p.get("text", "") for p in parts).strip()

            if not text:
                raise RuntimeError(
                    f"Gemini returned empty text (finishReason={finish_reason}). "
                    f"Response: {data}"
                )

            return text

        except requests.Timeout:
            last_error = "Request timed out (60s)"
            log.warning("Timeout (attempt %d/%d)", attempt, max_retries)
            time.sleep(delay)
            delay *= 2
        except requests.RequestException as exc:
            last_error = str(exc)
            log.warning("Network error (attempt %d/%d): %s", attempt, max_retries, exc)
            time.sleep(delay)
            delay *= 2

    raise RuntimeError(
        f"Gemini call failed after {max_retries} attempts. Last error: {last_error}"
    )


def verify_api_key(api_key: Optional[str] = None, model: str = DEFAULT_MODEL) -> bool:
    """
    Quick smoke test: send a minimal request to verify API key and model work.
    Returns True if successful, prints error and returns False otherwise.

    Usage in PowerShell:
        python -c "from lib.parser._gemini_rest_patch import verify_api_key; verify_api_key()"
    """
    try:
        result = gemini_text_call(
            "Reply with only the word: OK",
            api_key=api_key,
            model=model,
            max_tokens=10,
        )
        print(f"API key OK. Model '{model}' response: {result.strip()}")
        return True
    except RuntimeError as exc:
        print(f"API key / model check FAILED:\n{exc}")
        return False


if __name__ == "__main__":
    # Run as: python lib/parser/_gemini_rest_patch.py
    verify_api_key()
