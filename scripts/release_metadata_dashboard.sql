-- Current deployed bundle by environment and database
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
ORDER BY environment, database_name;

-- Latest health for each component in each environment
SELECT
    environment,
    database_name,
    component,
    health_status,
    last_checked_at,
    details
FROM PLATFORM_CONTROL.DEPLOYMENT.ENVIRONMENT_HEALTH
ORDER BY environment, database_name, component;

-- Promotion-ready environment summary
SELECT
    environment,
    database_name,
    infra_release_version,
    ingestion_release_version,
    dbt_release_version,
    CASE
        WHEN infra_release_version IS NOT NULL
         AND ingestion_release_version IS NOT NULL
         AND dbt_release_version IS NOT NULL
        THEN 'READY'
        ELSE 'NOT_READY'
    END AS bundle_status
FROM PLATFORM_CONTROL.DEPLOYMENT.CURRENT_ENV_RELEASES
ORDER BY environment, database_name;
