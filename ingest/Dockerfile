# One image for every ingest job. Each Cloud Run job selects its script via
# container args (e.g. `openmeteo-forecast/main.py`), set in infra/cloud-run-jobs.tf.
FROM python:3.13-slim

# Set the working directory inside the container
WORKDIR /app

# Install dependencies first so this layer is cached across code changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the shared helpers and every job's script
COPY . .

# Let job scripts import the shared helpers (`from common.load import append_to_bronze`)
ENV PYTHONPATH=/app

# The job's script path is supplied as the container argument
ENTRYPOINT ["python3"]
