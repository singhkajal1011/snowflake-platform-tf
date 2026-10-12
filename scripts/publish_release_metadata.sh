#!/usr/bin/env bash
set -euo pipefail

: "${REPO_NAME:?REPO_NAME is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
: "${GIT_SHA:?GIT_SHA is required}"
: "${ENVIRONMENT:?ENVIRONMENT is required}"
: "${DATABASE_NAME:?DATABASE_NAME is required}"
: "${SNOWFLAKE_ACCOUNT:?SNOWFLAKE_ACCOUNT is required}"
: "${SNOWFLAKE_USER:?SNOWFLAKE_USER is required}"
: "${SNOWFLAKE_ROLE:?SNOWFLAKE_ROLE is required}"
: "${SNOWFLAKE_WAREHOUSE:?SNOWFLAKE_WAREHOUSE is required}"

RUN_URL="${RUN_URL:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-local}}"
REPO_URL="${REPO_URL:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}}"

SQL=$(cat <<SQL
CREATE DATABASE IF NOT EXISTS PLATFORM_CONTROL;
CREATE SCHEMA IF NOT EXISTS PLATFORM_CONTROL.DEPLOYMENT;

CREATE OR REPLACE TABLE IF NOT EXISTS PLATFORM_CONTROL.DEPLOYMENT.RELEASE_HISTORY (
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
  is_current BOOLEAN
);

UPDATE PLATFORM_CONTROL.DEPLOYMENT.RELEASE_HISTORY
SET is_current = FALSE
WHERE repo_name = '${REPO_NAME}'
  AND environment = '${ENVIRONMENT}'
  AND database_name = '${DATABASE_NAME}'
  AND is_current = TRUE;

INSERT INTO PLATFORM_CONTROL.DEPLOYMENT.RELEASE_HISTORY (
  repo_name,
  repo_url,
  git_sha,
  release_version,
  environment,
  database_name,
  deployed_by,
  deployed_at,
  status,
  run_url,
  release_manifest,
  is_current
)
VALUES (
  '${REPO_NAME}',
  '${REPO_URL}',
  '${GIT_SHA}',
  '${RELEASE_VERSION}',
  '${ENVIRONMENT}',
  '${DATABASE_NAME}',
  'github-actions',
  CURRENT_TIMESTAMP(),
  'SUCCESS',
  '${RUN_URL}',
  '${REPO_NAME}:${RELEASE_VERSION}:${GIT_SHA}',
  TRUE
);
SQL
)

# Create the Snowflake CLI connection once per job and use it for the insert.
snow connection add \
  --connection-name github \
  --account "$SNOWFLAKE_ACCOUNT" \
  --user "$SNOWFLAKE_USER" \
  --role "$SNOWFLAKE_ROLE" \
  --warehouse "$SNOWFLAKE_WAREHOUSE" \
  --authenticator WORKLOAD_IDENTITY \
  --workload-identity-provider OIDC \
  --default \
  --no-interactive

snow sql --connection github -q "$SQL"
