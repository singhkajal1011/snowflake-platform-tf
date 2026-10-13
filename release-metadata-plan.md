# Release metadata tracking plan for the 3-repo platform

## Goal

Track the exact code version deployed to each Snowflake environment so operations can answer:

- which Git SHA is currently deployed?
- which release version is active?
- which repo version is running in DEV / TEST / PROD?
- is the database healthy and consistent across infra + ingestion + dbt?

## Recommended branch names

- infra repo: `feature/release-metadata-tracking`
- ingestion repo: `feature/release-metadata-ingestion`
- domain repo: `feature/release-metadata-domain`

## Operational design

Each repo publishes its own deployment record to Snowflake after a successful deployment or pipeline run. A central metadata table then aggregates the current state by environment and database.

### Metadata to persist

For each successful deployment, store:

- repo_name
- repo_url
- git_sha
- release_version
- environment
- database_name
- deployed_at
- status
- run_url
- commit_message
- is_current

## Recommended Snowflake tables

```sql
CREATE OR REPLACE DATABASE PLATFORM_CONTROL;
CREATE OR REPLACE SCHEMA PLATFORM_CONTROL.DEPLOYMENT;

CREATE OR REPLACE TABLE PLATFORM_CONTROL.DEPLOYMENT.RELEASE_HISTORY (
    deployment_id NUMBER AUTOINCREMENT,
    repo_name STRING,
    repo_url STRING,
    git_sha STRING,
    release_version STRING,
    environment STRING,
    database_name STRING,
    deployed_by STRING,
    deployed_at TIMESTAMP_LTZ,
    status STRING,
    run_url STRING,
    release_manifest STRING,
    is_current BOOLEAN,
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

## Current state view

```sql
CREATE OR REPLACE VIEW PLATFORM_CONTROL.DEPLOYMENT.CURRENT_ENV_RELEASES AS
SELECT
    environment,
    database_name,
    MAX(CASE WHEN repo_name = 'snowflake-platform-tf' THEN git_sha END) AS infra_git_sha,
    MAX(CASE WHEN repo_name = 'snowflake-platform-tf' THEN release_version END) AS infra_release_version,
    MAX(CASE WHEN repo_name = 'data-ingestion-raw' THEN git_sha END) AS ingestion_git_sha,
    MAX(CASE WHEN repo_name = 'data-ingestion-raw' THEN release_version END) AS ingestion_release_version,
    MAX(CASE WHEN repo_name = 'customer-domain-dbt' THEN git_sha END) AS dbt_git_sha,
    MAX(CASE WHEN repo_name = 'customer-domain-dbt' THEN release_version END) AS dbt_release_version,
    MAX(deployed_at) AS last_deployment_at
FROM PLATFORM_CONTROL.DEPLOYMENT.RELEASE_HISTORY
WHERE is_current = TRUE
GROUP BY environment, database_name;
```

## Repo-specific responsibilities

### 1. infra repo

- Successful Terraform apply writes infra metadata
- Stores platform version and git sha for the DB/platform stack
- Records the database names created/managed

### 2. ingestion repo

- Successful ingestion deploy writes ingestion metadata
- Stores pipeline version and last successful ingestion timestamp
- Ties deployment to environment database and RAW table scope

### 3. dbt repo

- Successful dbt run writes dbt metadata
- Stores model version and last successful build timestamp
- Ties deployment to the domain database / marts models

## Promotion logic

Promotion should be gated on the environment manifest being consistent:

- infra release record is current
- ingestion release record is current
- dbt release record is current
- all component health checks are green

## Health checks to correlate with release metadata

Use metadata records alongside DB health checks such as:

- database exists and is accessible
- schemas exist
- critical tables are populated
- ingestion last_success_ts is recent
- dbt run last_success_ts is recent
- warehouse is healthy and queryable

## Recommended next step

Create the same pattern in each repo and then implement the publish step in GitHub Actions after successful deployment.

- infra repo: publish version on successful terraform apply
- ingestion repo: publish version after successful ingestion deploy
- domain repo: publish version after successful dbt run
