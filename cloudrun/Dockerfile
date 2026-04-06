FROM python:3.10-slim
RUN apt-get update && apt-get install -y poppler-utils && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY lib/ ./lib/
COPY cloudrun/ ./cloudrun/
RUN pip install -r cloudrun/requirements.txt
CMD ["python", "cloudrun/pipeline_job.py"]
