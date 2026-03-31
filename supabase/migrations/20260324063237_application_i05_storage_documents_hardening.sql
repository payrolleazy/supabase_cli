create or replace function public.platform_jsonb_text_array(p_value jsonb)
returns text[]
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select
    case
      when p_value is null or p_value = 'null'::jsonb then '{}'::text[]
      when jsonb_typeof(p_value) <> 'array' then null::text[]
      else coalesce((
        select array_agg(btrim(v)) filter (where nullif(btrim(v), '') is not null)
        from jsonb_array_elements_text(p_value) as t(v)
      ), '{}'::text[])
    end;
$function$;

create or replace function public.platform_sanitize_storage_filename(p_file_name text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select
    case
      when coalesce(nullif(btrim(p_file_name), ''), '') = '' then 'file.bin'
      else regexp_replace(
        regexp_replace(lower(btrim(p_file_name)), '[^a-z0-9._-]+', '_', 'g'),
        '_{2,}',
        '_',
        'g'
      )
    end;
$function$;

create or replace function public.platform_build_document_storage_object_name(
  p_tenant_id uuid,
  p_document_class_code text,
  p_owner_actor_user_id uuid,
  p_upload_intent_id uuid,
  p_original_file_name text
)
returns text
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select
    p_tenant_id::text || '/' ||
    lower(btrim(p_document_class_code)) || '/' ||
    coalesce(p_owner_actor_user_id::text, 'unowned') || '/' ||
    p_upload_intent_id::text || '/' ||
    public.platform_sanitize_storage_filename(p_original_file_name);
$function$;

create index if not exists idx_platform_document_record_superseded_by_document_id
on public.platform_document_record (superseded_by_document_id);;
