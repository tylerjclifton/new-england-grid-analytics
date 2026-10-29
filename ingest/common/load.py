"""
Step 3 of every ingest job: load the shaped DataFrame into bronze.

Bronze tables are defined in Terraform (infra/bigquery.tf). append_to_bronze()
loads against the live table's schema, so column names and types are owned in
that one place: a DataFrame with a missing or misnamed column fails the load
instead of silently creating a mismatched table.

Bronze is append-only: jobs never update or delete rows (decision 0001). So a
local run writes to dev_bronze unless told otherwise (decision 0008): a bug
tried out on a laptop can't leave permanent rows in production bronze.
"""

# Import standard libraries
import logging
import os

# Import third party libraries
import pandas
from google.cloud import bigquery

# Import shared ingest helpers
from common.run import JOB_NAME, RUN_STARTED_AT, fail


def append_to_bronze(df: pandas.DataFrame):
    """
    Append a DataFrame to this job's bronze table, adding the audit columns.

    The target comes from BQ_PROJECT_ID / BQ_DATASET_ID / BQ_TABLE_ID, which
    the Cloud Run jobs set (infra/cloud-run-jobs.tf). Without them, as in a
    local run, it's this job's table in dev_bronze (same schema as bronze,
    rows expire after 7 days; infra/bigquery.tf).
    """
    if df.empty:
        logging.info("No rows to write")
        return

    # Resolve the target table
    project_id = os.getenv('BQ_PROJECT_ID', 'new-england-grid-analytics')
    dataset_id = os.getenv('BQ_DATASET_ID', 'dev_bronze')
    table_id   = os.getenv('BQ_TABLE_ID', JOB_NAME.replace('-', '_'))
    table_ref  = f"{project_id}.{dataset_id}.{table_id}"

    # Stamp the audit columns shared by every bronze table
    df = df.assign(ingested_at=RUN_STARTED_AT, ingested_by=f"ingest-{JOB_NAME}")

    # Load against the table's own schema (owned by Terraform) and append —
    # bronze is append-only, so earlier rows are never overwritten
    client = bigquery.Client(project=project_id)
    try:
        job_config = bigquery.LoadJobConfig(
            schema=client.get_table(table_ref).schema,
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        )
        client.load_table_from_dataframe(df, table_ref, job_config=job_config).result()
    except Exception as error:
        fail(f"BigQuery load into {table_ref} failed: {error}")

    logging.info(f"Appended {len(df)} rows to {table_ref}")
