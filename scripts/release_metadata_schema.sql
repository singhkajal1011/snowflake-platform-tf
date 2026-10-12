CREATE OR REPLACE DATABASE IF NOT EXISTS PLATFORM_CONTROL;
CREATE OR REPLACE SCHEMA IF NOT EXISTS PLATFORM_CONTROL.DEPLOYMENT;

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
    is_current BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE PLATFORM_CONTROL.DEPLOYMENT.HEALTH_HISTORY (
    health_id NUMBER AUTOINCREMENT,
    environment STRING,
    database_name STRING,
    component STRING,
    health_status STRING,
    last_checked_at TIMESTAMP_LTZ,
    details STRING,
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

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

CREATE OR REPLACE VIEW PLATFORM_CONTROL.DEPLOYMENT.ENVIRONMENT_HEALTH AS
SELECT
    h.environment,
    h.database_name,
    h.component,
    h.health_status,
    h.last_checked_at,
    h.details
FROM PLATFORM_CONTROL.DEPLOYMENT.HEALTH_HISTORY h
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY h.environment, h.database_name, h.component
    ORDER BY h.last_checked_at DESC
) = 1;

CREATE OR REPLACE VIEW PLATFORM_CONTROL.DEPLOYMENT.ENVIRONMENT_SUMMARY AS
SELECT
    c.environment,
    c.database_name,
    c.infra_git_sha,
    c.infra_release_version,
    c.ingestion_git_sha,
    c.ingestion_release_version,
    c.dbt_git_sha,
    c.dbt_release_version,
    c.last_deployment_at,
    LISTAGG(DISTINCT CASE WHEN h.component = 'infra' AND h.health_status = 'GREEN' THEN 'infra:green' END, ', ') AS infra_health,
    LISTAGG(DISTINCT CASE WHEN h.component = 'ingestion' AND h.health_status = 'GREEN' THEN 'ingestion:green' END, ', ') AS ingestion_health,
    LISTAGG(DISTINCT CASE WHEN h.component = 'dbt' AND h.health_status = 'GREEN' THEN 'dbt:green' END, ', ') AS dbt_health
FROM PLATFORM_CONTROL.DEPLOYMENT.CURRENT_ENV_RELEASES c
LEFT JOIN PLATFORM_CONTROL.DEPLOYMENT.ENVIRONMENT_HEALTH h
  ON h.environment = c.environment
 AND h.database_name = c.database_name
GROUP BY
    c.environment,
    c.database_name,
    c.infra_git_sha,
    c.infra_release_version,
    c.ingestion_git_sha,
    c.ingestion_release_version,
    c.dbt_git_sha,
    c.dbt_release_version,
    c.last_deployment_at;
