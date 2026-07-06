#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Assert SowerBase Level 3 Airtable parity fields are first-class operator fields.

.DESCRIPTION
    Checks the certified SowerBase/NocoDB HVAC intake table for physical
    PostgreSQL columns, NocoDB column metadata, and grid visibility for the
    common, HVAC, and plumber parity fields required by Gate 3-Fix.
#>

param(
    [string]$DbContainer = "sowerbase-local-db-1",
    [string]$DbUser = "nocodb",
    [string]$DbName = "nocodb",
    [string]$SchemaName = "peoc8ioej5ejtj7",
    [string]$TableName = "HVAC Intake",
    [string]$ModelTitle = "HVAC Intake"
)

$ErrorActionPreference = "Stop"

function Invoke-Psql {
    param([Parameter(Mandatory)][string]$Sql)

    $result = $Sql | docker exec -i $DbContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -t -A
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed with exit code $LASTEXITCODE"
    }

    return @($result)
}

$requiredFields = @(
    [pscustomobject]@{ Scope = "shared";  Title = "Trace ID";                  Column = "Trace_ID";                  Uidt = "SingleLineText"; TypePattern = "text" },
    [pscustomobject]@{ Scope = "shared";  Title = "Submitted At";              Column = "Submitted_At";              Uidt = "DateTime";       TypePattern = "timestamp" },
    [pscustomobject]@{ Scope = "shared";  Title = "Transcript";                Column = "Transcript";                Uidt = "LongText";       TypePattern = "text" },
    [pscustomobject]@{ Scope = "hvac";    Title = "System Type";               Column = "System_Type";               Uidt = "SingleLineText"; TypePattern = "text" },
    [pscustomobject]@{ Scope = "hvac";    Title = "System Age";                Column = "System_Age";                Uidt = "SingleLineText"; TypePattern = "text" },
    [pscustomobject]@{ Scope = "hvac";    Title = "Preferred Service Window";  Column = "Preferred_Service_Window";  Uidt = "SingleLineText"; TypePattern = "text" },
    [pscustomobject]@{ Scope = "plumber"; Title = "Preferred Callback Time";   Column = "Preferred_Callback_Time";   Uidt = "SingleLineText"; TypePattern = "text" }
)

$valuesSql = ($requiredFields | ForEach-Object {
    "('$($_.Scope)', '$($_.Title -replace "'", "''")', '$($_.Column)', '$($_.Uidt)', '$($_.TypePattern)')"
}) -join ",`n        "

$sql = @"
WITH required(scope, title, column_name, uidt, type_pattern) AS (
    VALUES
        $valuesSql
),
target_model AS (
    SELECT id
    FROM public.nc_models_v2
    WHERE title = '$($ModelTitle -replace "'", "''")'
      AND table_name = '$($TableName -replace "'", "''")'
    LIMIT 1
),
target_view AS (
    SELECT id
    FROM public.nc_views_v2
    WHERE fk_model_id = (SELECT id FROM target_model)
      AND type = 3
    ORDER BY created_at NULLS LAST, id
    LIMIT 1
),
physical AS (
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = '$($SchemaName -replace "'", "''")'
      AND table_name = '$($TableName -replace "'", "''")'
),
metadata AS (
    SELECT title, column_name, uidt, id
    FROM public.nc_columns_v2
    WHERE fk_model_id = (SELECT id FROM target_model)
),
grid AS (
    SELECT c.title, g.show
    FROM public.nc_grid_view_columns_v2 g
    JOIN public.nc_columns_v2 c ON c.id = g.fk_column_id
    WHERE g.fk_view_id = (SELECT id FROM target_view)
)
SELECT scope || '|' || title || '|physical_missing|' || column_name
FROM required r
WHERE NOT EXISTS (
    SELECT 1 FROM physical p
    WHERE p.column_name = r.column_name
      AND p.data_type ILIKE '%' || r.type_pattern || '%'
)
UNION ALL
SELECT scope || '|' || title || '|metadata_missing|' || column_name
FROM required r
WHERE NOT EXISTS (
    SELECT 1 FROM metadata m
    WHERE m.title = r.title
      AND m.column_name = r.column_name
      AND m.uidt = r.uidt
)
UNION ALL
SELECT scope || '|' || title || '|grid_hidden_or_missing|' || column_name
FROM required r
WHERE NOT EXISTS (
    SELECT 1 FROM grid g
    WHERE g.title = r.title
      AND g.show = true
)
ORDER BY 1;
"@

$failures = @(Invoke-Psql -Sql $sql | Where-Object { $_ -and $_.Trim() })

if ($failures.Count -gt 0) {
    Write-Host "FAIL: SowerBase Level 3 first-class operator fields are incomplete." -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: SowerBase Level 3 first-class operator fields are present and grid-visible." -ForegroundColor Green
Write-Host "Shared/common intake fields: Trace ID, Submitted At, Transcript"
Write-Host "HVAC parity fields: System Type, System Age, Preferred Service Window"
Write-Host "Plumber parity fields: Preferred Callback Time"
