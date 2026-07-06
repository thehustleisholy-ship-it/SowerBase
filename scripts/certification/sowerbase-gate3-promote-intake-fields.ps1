#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Promote Gate 3 intake parity fields to first-class SowerBase operator fields.

.DESCRIPTION
    Adds the shared, HVAC, and plumber Airtable parity fields to the certified
    NocoDB/PostgreSQL HVAC Intake table, registers them in NocoDB metadata, and
    makes them visible in the grid view used by operators.
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

function ConvertTo-SqlLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

$schemaSql = ConvertTo-SqlLiteral $SchemaName
$tableSql = ConvertTo-SqlLiteral $TableName
$modelTitleSql = ConvertTo-SqlLiteral $ModelTitle

$sqlTemplate = @'
BEGIN;

ALTER TABLE "__SCHEMA__"."__TABLE__" ADD COLUMN IF NOT EXISTS "Trace_ID" text;
ALTER TABLE "__SCHEMA__"."__TABLE__" ADD COLUMN IF NOT EXISTS "Submitted_At" timestamp without time zone;
ALTER TABLE "__SCHEMA__"."__TABLE__" ADD COLUMN IF NOT EXISTS "Transcript" text;
ALTER TABLE "__SCHEMA__"."__TABLE__" ADD COLUMN IF NOT EXISTS "System_Type" text;
ALTER TABLE "__SCHEMA__"."__TABLE__" ADD COLUMN IF NOT EXISTS "System_Age" text;
ALTER TABLE "__SCHEMA__"."__TABLE__" ADD COLUMN IF NOT EXISTS "Preferred_Service_Window" text;
ALTER TABLE "__SCHEMA__"."__TABLE__" ADD COLUMN IF NOT EXISTS "Preferred_Callback_Time" text;

CREATE OR REPLACE FUNCTION pg_temp.sowerbase_try_jsonb(input text)
RETURNS jsonb
LANGUAGE plpgsql
AS $try_json$
BEGIN
    RETURN input::jsonb;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$try_json$;

WITH parsed AS (
    SELECT id, pg_temp.sowerbase_try_jsonb("Raw_Payload") AS payload
    FROM "__SCHEMA__"."__TABLE__"
)
UPDATE "__SCHEMA__"."__TABLE__" t
SET
    "Trace_ID" = COALESCE(NULLIF(t."Trace_ID", ''), NULLIF(parsed.payload->>'trace_id', '')),
    "Submitted_At" = COALESCE(
        t."Submitted_At",
        CASE
            WHEN parsed.payload ? 'submitted_at'
             AND (parsed.payload->>'submitted_at') ~ '^\d{4}-\d{2}-\d{2}'
            THEN (parsed.payload->>'submitted_at')::timestamp
            ELSE t.created_at
        END
    ),
    "Transcript" = COALESCE(NULLIF(t."Transcript", ''), NULLIF(parsed.payload->>'transcript', '')),
    "System_Type" = COALESCE(NULLIF(t."System_Type", ''), NULLIF(parsed.payload->>'system_type', '')),
    "System_Age" = COALESCE(NULLIF(t."System_Age", ''), NULLIF(parsed.payload->>'system_age_years', '')),
    "Preferred_Service_Window" = COALESCE(NULLIF(t."Preferred_Service_Window", ''), NULLIF(parsed.payload->>'preferred_service_window', '')),
    "Preferred_Callback_Time" = COALESCE(NULLIF(t."Preferred_Callback_Time", ''), NULLIF(parsed.payload->>'preferred_callback_time', ''))
FROM parsed
WHERE t.id = parsed.id;

DO $migration$
DECLARE
    target_model record;
    target_view_id text;
    model_order integer;
    view_order integer;
    field record;
    column_id text;
BEGIN
    SELECT *
    INTO target_model
    FROM public.nc_models_v2
    WHERE title = '__MODEL_TITLE__'
      AND table_name = '__TABLE__'
      AND base_id = '__SCHEMA__'
    LIMIT 1;

    IF target_model.id IS NULL THEN
        RAISE EXCEPTION 'NocoDB model metadata not found for %.%', '__SCHEMA__', '__TABLE__';
    END IF;

    SELECT id
    INTO target_view_id
    FROM public.nc_views_v2
    WHERE fk_model_id = target_model.id
      AND type = 3
    ORDER BY created_at NULLS LAST, id
    LIMIT 1;

    SELECT COALESCE(MAX("order"), 0)
    INTO model_order
    FROM public.nc_columns_v2
    WHERE fk_model_id = target_model.id;

    SELECT COALESCE(MAX("order"), 0)
    INTO view_order
    FROM public.nc_grid_view_columns_v2
    WHERE fk_view_id = target_view_id;

    FOR field IN
        SELECT *
        FROM (VALUES
            ('shared',  'Trace ID',                 'Trace_ID',                 'SingleLineText', 'text',      1, '180px'),
            ('shared',  'Submitted At',             'Submitted_At',             'DateTime',       'timestamp', 2, '180px'),
            ('shared',  'Transcript',               'Transcript',               'LongText',       'text',      3, '260px'),
            ('hvac',    'System Type',              'System_Type',              'SingleLineText', 'text',      4, '180px'),
            ('hvac',    'System Age',               'System_Age',               'SingleLineText', 'text',      5, '140px'),
            ('hvac',    'Preferred Service Window', 'Preferred_Service_Window', 'SingleLineText', 'text',      6, '220px'),
            ('plumber', 'Preferred Callback Time',  'Preferred_Callback_Time',  'SingleLineText', 'text',      7, '220px')
        ) AS f(scope, title, column_name, uidt, dt, order_offset, width)
    LOOP
        SELECT id
        INTO column_id
        FROM public.nc_columns_v2
        WHERE fk_model_id = target_model.id
          AND (title = field.title OR column_name = field.column_name)
        LIMIT 1;

        IF column_id IS NULL THEN
            column_id := 'c' || substr(md5(random()::text || clock_timestamp()::text || field.column_name), 1, 14);

            INSERT INTO public.nc_columns_v2 (
                id, source_id, base_id, fk_model_id, title, column_name,
                uidt, dt, pk, pv, rqd, "system", "order",
                fk_workspace_id, created_at, updated_at
            ) VALUES (
                column_id, target_model.source_id, target_model.base_id, target_model.id,
                field.title, field.column_name, field.uidt, field.dt,
                false, false, false, false, model_order + field.order_offset,
                target_model.fk_workspace_id, now(), now()
            );
        ELSE
            UPDATE public.nc_columns_v2
            SET title = field.title,
                column_name = field.column_name,
                uidt = field.uidt,
                dt = field.dt,
                "system" = false,
                updated_at = now()
            WHERE id = column_id;
        END IF;

        IF target_view_id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1
                FROM public.nc_grid_view_columns_v2
                WHERE fk_view_id = target_view_id
                  AND fk_column_id = column_id
            ) THEN
                UPDATE public.nc_grid_view_columns_v2
                SET show = true,
                    width = field.width,
                    updated_at = now()
                WHERE fk_view_id = target_view_id
                  AND fk_column_id = column_id;
            ELSE
                INSERT INTO public.nc_grid_view_columns_v2 (
                    id, fk_view_id, fk_column_id, source_id, base_id,
                    width, show, "order", fk_workspace_id, created_at, updated_at
                ) VALUES (
                    'nc' || substr(md5(random()::text || clock_timestamp()::text || column_id), 1, 13),
                    target_view_id, column_id, target_model.source_id, target_model.base_id,
                    field.width, true, view_order + field.order_offset,
                    target_model.fk_workspace_id, now(), now()
                );
            END IF;
        END IF;
    END LOOP;
END;
$migration$;

COMMIT;
'@

$sql = $sqlTemplate.Replace("__SCHEMA__", $schemaSql).Replace("__TABLE__", $tableSql).Replace("__MODEL_TITLE__", $modelTitleSql)

Write-Host "Promoting Gate 3 first-class intake fields on $SchemaName.""$TableName""..."
$sql | docker exec -i $DbContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) {
    throw "Level 3 field promotion failed with exit code $LASTEXITCODE"
}

Write-Host "Promotion complete."
Write-Host "Shared/common intake fields: Trace ID, Submitted At, Transcript"
Write-Host "HVAC parity fields: System Type, System Age, Preferred Service Window"
Write-Host "Plumber parity fields: Preferred Callback Time"
