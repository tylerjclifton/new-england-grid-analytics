# dbt transform job: builds silver views and gold tables, runs their tests,
# then checks bronze freshness. Built from transform/ (scripts/build-image.sh).
FROM python:3.13-slim

# Set the working directory inside the container
WORKDIR /app

# Install dependencies first so this layer is cached across model changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the dbt project (models, macros, tests, profiles)
COPY . .

# dbt build, then dbt source freshness; on failure, logs a failure report that
# emails an alert (see run.py)
CMD ["python", "run.py"]
