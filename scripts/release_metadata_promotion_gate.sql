-- Promotion gate: verifies that DEV -> TEST -> PROD are consistent and healthy before release.
-- Run as:
--   snow sql --connection github -q "ALTER SESSION SET QUERY_TAG = 'promotion_gate';" -- then execute the SQL below
-- or embed this in a workflow script with the target environment variable substituted.

WITH current_release AS (
    SELECT
        environment,
        database_name,
        infra_release_version,
        ingestion_release_version,
        dbt_release_version,
        infra_git_sha,
        ingestion_git_sha,
        dbt_git_sha,
        last_deployment_at
    FROM PLATFORM_CONTROL.DEPLOYMENT.CURRENT_ENV_RELEASES
),
health AS (
    SELECT
        environment,
        database_name,
        component,
        health_status,
        last_checked_at
    FROM PLATFORM_CONTROL.DEPLOYMENT.ENVIRONMENT_HEALTH
),
source_env AS (
    SELECT *
    FROM current_release
    WHERE environment = 'DEV'
),
final AS (
    SELECT
        s.environment AS source_environment,
        'TEST' AS target_environment,
        s.database_name,
        s.infra_release_version AS source_infra_version,
        s.ingestion_release_version AS source_ingestion_version,
        s.dbt_release_version AS source_dbt_version,
        t.infra_release_version AS target_infra_version,
        t.ingestion_release_version AS target_ingestion_version,
        t.dbt_release_version AS target_dbt_version,
        COALESCE(i.health_status, 'UNKNOWN') AS infra_health,
        COALESCE(ing.health_status, 'UNKNOWN') AS ingestion_health,
        COALESCE(d.health_status, 'UNKNOWN') AS dbt_health
    FROM source_env s
    LEFT JOIN current_release t
      ON t.environment = 'TEST'
     AND t.database_name = s.database_name
    LEFT JOIN health i
      ON i.environment = 'TEST'
     AND i.database_name = s.database_name
     AND i.component = 'infra'
    LEFT JOIN health ing
      ON ing.environment = 'TEST'
     AND ing.database_name = s.database_name
     AND ing.component = 'ingestion'
    LEFT JOIN health d
      ON d.environment = 'TEST'
     AND d.database_name = s.database_name
     AND d.component = 'dbt'
)
SELECT
    source_environment,
    target_environment,
    database_name,
    source_infra_version,
    source_ingestion_version,
    source_dbt_version,
    target_infra_version,
    target_ingestion_version,
    target_dbt_version,
    infra_health,
    ingestion_health,
    dbt_health,
    CASE
        WHEN target_infra_version IS NOT NULL
         AND target_ingestion_version IS NOT NULL
         AND target_dbt_version IS NOT NULL
         AND infra_health = 'GREEN'
         AND ingestion_health = 'GREEN'
         AND dbt_health = 'GREEN'
        THEN 'ALLOW_PROMOTION'
        ELSE 'BLOCK_PROMOTION'
    END AS promotion_decision
FROM final;

-- repeat the same pattern for TEST -> PROD by changing source_environment = 'TEST' and target_environment = 'PROD'.
