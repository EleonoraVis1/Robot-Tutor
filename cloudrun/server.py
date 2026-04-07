import base64
import json
import os

from flask import Flask, request

app = Flask(__name__)


@app.route("/", methods=["POST"])
def handle_event():
    import logging
    log = logging.getLogger(__name__)

    # Log all headers and raw body for debugging
    log.info("Headers: %s", dict(request.headers))
    raw = request.get_data(as_text=True)
    log.info("Raw body: %s", raw[:500])

    object_path = ""
    bucket = ""

    # Try CloudEvents format (ce-subject header)
    ce_subject = request.headers.get("ce-subject", "")
    if ce_subject:
        # ce-subject looks like: /objects/raw-uploads%2Ftest%2Ffile.pdf
        from urllib.parse import unquote
        object_path = unquote(ce_subject.lstrip("/objects/"))
        bucket = request.headers.get("ce-source", "").split("/")[-1]
        log.info("CloudEvents format: object=%s bucket=%s", object_path, bucket)

    # Try Pub/Sub format fallback
    if not object_path:
        try:
            import json, base64
            envelope = request.get_json(silent=True) or {}
            message = envelope.get("message", {})
            data = json.loads(base64.b64decode(message.get("data", "e30=")).decode())
            object_path = data.get("name", "")
            bucket = data.get("bucket", "")
            log.info("PubSub format: object=%s bucket=%s", object_path, bucket)
        except Exception as e:
            log.warning("PubSub parse failed: %s", e)

    # Try direct JSON body (GCS_NOTIFICATION format)
    if not object_path:
        try:
            import json
            data = request.get_json(silent=True) or {}
            object_path = data.get("name", "")
            bucket = data.get("bucket", "")
            log.info("Direct JSON format: object=%s bucket=%s", object_path, bucket)
        except Exception as e:
            log.warning("Direct JSON parse failed: %s", e)

    log.info("Final: object_path=%s bucket=%s", object_path, bucket)

    if not object_path:
        log.warning("Could not extract object path — skipping")
        return "Skipped: no object path", 200

    if not object_path.startswith("raw-uploads/"):
        log.info("Skipping non raw-uploads path: %s", object_path)
        return "Skipped", 200

    if not object_path.lower().endswith(".pdf"):
        log.info("Skipping non-PDF: %s", object_path)
        return "Skipped", 200

    os.environ["GCS_OBJECT_PATH"] = object_path
    os.environ["GCS_BUCKET"] = bucket or os.environ.get("GCS_BUCKET", "robot-tutor.firebasestorage.app")

    try:
        import sys
        sys.path.insert(0, "/app")
        from cloudrun.pipeline_job import main
        main()
        return "OK", 200
    except SystemExit as e:
        code = e.code if hasattr(e, 'code') else 1
        return ("OK" if code == 0 else "Pipeline failed"), (200 if code == 0 else 500)
    except Exception as e:
        log.error("Pipeline error: %s", e, exc_info=True)
        return f"Error: {e}", 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
