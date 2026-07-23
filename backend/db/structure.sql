SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: invitation_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.invitation_role AS ENUM (
    'view',
    'edit'
);


--
-- Name: membership_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.membership_role AS ENUM (
    'edit',
    'view'
);


--
-- Name: notification_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_type AS ENUM (
    'assign',
    'progress',
    'done'
);


--
-- Name: task_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.task_status AS ENUM (
    'Pendente',
    'Em Andamento',
    'Concluído',
    'N/A'
);


--
-- Name: audit_logs_forbid_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_logs_forbid_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs é append-only: % proibido (audit-log §4.1 inv. 3)', TG_OP;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    token text NOT NULL,
    email text NOT NULL,
    role public.invitation_role NOT NULL,
    created_by_person_id uuid NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval) NOT NULL,
    used_at timestamp with time zone,
    used_by_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_invitations_consumption CHECK ((((used_at IS NULL) AND (used_by_user_id IS NULL)) OR ((used_at IS NOT NULL) AND (used_by_user_id IS NOT NULL)))),
    CONSTRAINT chk_invitations_email_length CHECK ((char_length(email) <= 254)),
    CONSTRAINT chk_invitations_email_lowercase CHECK ((email = lower(email)))
);

ALTER TABLE ONLY public.invitations FORCE ROW LEVEL SECURITY;


--
-- Name: invitation_by_token(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invitation_by_token(p_token text) RETURNS SETOF public.invitations
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  PERFORM set_config('app.invitation_token', coalesce(p_token, ''), true);
  RETURN QUERY SELECT * FROM invitations WHERE token = p_token;
END;
$$;


--
-- Name: memberships_owner_is_not_member(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.memberships_owner_is_not_member() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.user_id = (
    SELECT owner_user_id FROM workspaces WHERE id = NEW.workspace_id
  ) THEN
    RAISE EXCEPTION
      'o dono do workspace não pode ser membro (§1.1): user_id=%', NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: notifications_no_insert_read(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notifications_no_insert_read() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.read IS TRUE THEN
    RAISE EXCEPTION 'notifications: read deve ser false no INSERT (inv. 8)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: notifications_only_read_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notifications_only_read_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.read IS TRUE AND NEW.read IS FALSE THEN
    RAISE EXCEPTION 'notifications: não é permitido desmarcar como lida (inv. 4)';
  END IF;
  IF ROW(NEW.id, NEW.workspace_id, NEW.recipient_person_id, NEW.actor_person_id,
         NEW.type, NEW.msg, NEW.author_name_snapshot, NEW.recorded_at, NEW.created_at,
         NEW.ts_local, NEW.format_version, NEW.ctx_project_id, NEW.ctx_cell_id,
         NEW.ctx_robot_id, NEW.ctx_task_id)
     IS DISTINCT FROM
     ROW(OLD.id, OLD.workspace_id, OLD.recipient_person_id, OLD.actor_person_id,
         OLD.type, OLD.msg, OLD.author_name_snapshot, OLD.recorded_at, OLD.created_at,
         OLD.ts_local, OLD.format_version, OLD.ctx_project_id, OLD.ctx_cell_id,
         OLD.ctx_robot_id, OLD.ctx_task_id)
  THEN
    RAISE EXCEPTION 'notifications: só read/read_at podem mudar (inv. 4)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: people_forbid_archive_active_member(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.people_forbid_archive_active_member() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.archived_at IS NOT NULL AND OLD.archived_at IS NULL
     AND EXISTS (SELECT 1 FROM memberships WHERE person_id = NEW.id) THEN
    RAISE EXCEPTION 'pessoa com membership ativa não pode ser arquivada por esta tela '
      '(workspace-settings D-PERSON-DEL: use a remoção de membro)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: purge_expired_invitations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_expired_invitations() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  removidos integer;
BEGIN
  PERFORM set_config('app.invitation_purge', 'on', true);
  DELETE FROM invitations
   WHERE used_at IS NULL
     AND expires_at < now() - interval '30 days';
  GET DIAGNOSTICS removidos = ROW_COUNT;
  RETURN removidos;
END;
$$;


--
-- Name: secure_audit_partition(regclass); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secure_audit_partition(part regclass) RETURNS void
    LANGUAGE plpgsql
    AS $_$
BEGIN
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', part);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', part);
  BEGIN
    EXECUTE format($fmt$CREATE POLICY tenant_isolation ON %s FOR SELECT
      USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)$fmt$, part);
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    EXECUTE format($fmt$CREATE POLICY tenant_isolation_insert ON %s FOR INSERT
      WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)$fmt$, part);
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END;
$_$;


--
-- Name: task_advances_forbid_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.task_advances_forbid_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'task_advances é append-only: % proibido (progress-advances D-IMUT)', TG_OP;
END;
$$;


--
-- Name: workspaces_owner_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.workspaces_owner_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
    RAISE EXCEPTION
      'owner_user_id do workspace é imutável (§4.1 inv. 5)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: action_text_rich_texts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.action_text_rich_texts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    byte_size bigint NOT NULL,
    checksum character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    event_type text NOT NULL,
    format_version integer DEFAULT 1 NOT NULL,
    msg text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    ts_local text NOT NULL,
    by_person_id uuid,
    by_name text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_audit_by_name CHECK (((length(btrim(by_name)) >= 1) AND (length(btrim(by_name)) <= 200))),
    CONSTRAINT chk_audit_event_type CHECK ((event_type = ANY (ARRAY['task_completed'::text, 'workspace_reset'::text]))),
    CONSTRAINT chk_audit_msg CHECK ((btrim(msg) <> ''::text))
)
PARTITION BY RANGE (ts);

ALTER TABLE ONLY public.audit_logs FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs_2026_07 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    event_type text NOT NULL,
    format_version integer DEFAULT 1 NOT NULL,
    msg text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    ts_local text NOT NULL,
    by_person_id uuid,
    by_name text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_audit_by_name CHECK (((length(btrim(by_name)) >= 1) AND (length(btrim(by_name)) <= 200))),
    CONSTRAINT chk_audit_event_type CHECK ((event_type = ANY (ARRAY['task_completed'::text, 'workspace_reset'::text]))),
    CONSTRAINT chk_audit_msg CHECK ((btrim(msg) <> ''::text))
);

ALTER TABLE ONLY public.audit_logs_2026_07 FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs_2026_08 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    event_type text NOT NULL,
    format_version integer DEFAULT 1 NOT NULL,
    msg text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    ts_local text NOT NULL,
    by_person_id uuid,
    by_name text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_audit_by_name CHECK (((length(btrim(by_name)) >= 1) AND (length(btrim(by_name)) <= 200))),
    CONSTRAINT chk_audit_event_type CHECK ((event_type = ANY (ARRAY['task_completed'::text, 'workspace_reset'::text]))),
    CONSTRAINT chk_audit_msg CHECK ((btrim(msg) <> ''::text))
);

ALTER TABLE ONLY public.audit_logs_2026_08 FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs_2026_09; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs_2026_09 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    event_type text NOT NULL,
    format_version integer DEFAULT 1 NOT NULL,
    msg text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    ts_local text NOT NULL,
    by_person_id uuid,
    by_name text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_audit_by_name CHECK (((length(btrim(by_name)) >= 1) AND (length(btrim(by_name)) <= 200))),
    CONSTRAINT chk_audit_event_type CHECK ((event_type = ANY (ARRAY['task_completed'::text, 'workspace_reset'::text]))),
    CONSTRAINT chk_audit_msg CHECK ((btrim(msg) <> ''::text))
);

ALTER TABLE ONLY public.audit_logs_2026_09 FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs_2026_10; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs_2026_10 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    event_type text NOT NULL,
    format_version integer DEFAULT 1 NOT NULL,
    msg text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    ts_local text NOT NULL,
    by_person_id uuid,
    by_name text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_audit_by_name CHECK (((length(btrim(by_name)) >= 1) AND (length(btrim(by_name)) <= 200))),
    CONSTRAINT chk_audit_event_type CHECK ((event_type = ANY (ARRAY['task_completed'::text, 'workspace_reset'::text]))),
    CONSTRAINT chk_audit_msg CHECK ((btrim(msg) <> ''::text))
);

ALTER TABLE ONLY public.audit_logs_2026_10 FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs_default (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    event_type text NOT NULL,
    format_version integer DEFAULT 1 NOT NULL,
    msg text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    ts_local text NOT NULL,
    by_person_id uuid,
    by_name text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_audit_by_name CHECK (((length(btrim(by_name)) >= 1) AND (length(btrim(by_name)) <= 200))),
    CONSTRAINT chk_audit_event_type CHECK ((event_type = ANY (ARRAY['task_completed'::text, 'workspace_reset'::text]))),
    CONSTRAINT chk_audit_msg CHECK ((btrim(msg) <> ''::text))
);

ALTER TABLE ONLY public.audit_logs_default FORCE ROW LEVEL SECURITY;


--
-- Name: cells; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cells (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    project_id uuid NOT NULL,
    name text NOT NULL,
    "position" integer,
    progress_cache smallint DEFAULT 0 NOT NULL,
    progress_cached_at timestamp with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    updated_by_person_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_cells_name CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 120))),
    CONSTRAINT chk_cells_progress_cache CHECK (((progress_cache >= 0) AND (progress_cache <= 100)))
);

ALTER TABLE ONLY public.cells FORCE ROW LEVEL SECURITY;


--
-- Name: robots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.robots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    cell_id uuid NOT NULL,
    name text NOT NULL,
    application text DEFAULT 'Misto / Geral'::text NOT NULL,
    "position" integer,
    progress_cache smallint DEFAULT 0 NOT NULL,
    progress_cached_at timestamp with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    updated_by_person_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_robots_application CHECK ((application = ANY (ARRAY['Misto / Geral'::text, 'Solda Ponto'::text, 'Solda MIG'::text, 'Handling'::text, 'Sealing'::text, 'Outros'::text]))),
    CONSTRAINT chk_robots_name CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 120))),
    CONSTRAINT chk_robots_progress_cache CHECK (((progress_cache >= 0) AND (progress_cache <= 100)))
);

ALTER TABLE ONLY public.robots FORCE ROW LEVEL SECURITY;


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    robot_id uuid NOT NULL,
    cat text NOT NULL,
    "desc" text NOT NULL,
    weight numeric DEFAULT 1 NOT NULL,
    progress smallint DEFAULT 0 NOT NULL,
    status public.task_status DEFAULT 'Pendente'::public.task_status NOT NULL,
    "position" integer NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_tasks_cat CHECK (((length(btrim(cat)) >= 1) AND (length(btrim(cat)) <= 120))),
    CONSTRAINT chk_tasks_desc CHECK (((length(btrim("desc")) >= 1) AND (length(btrim("desc")) <= 200))),
    CONSTRAINT chk_tasks_progress CHECK (((progress >= 0) AND (progress <= 100))),
    CONSTRAINT chk_tasks_weight CHECK ((weight > (0)::numeric)),
    CONSTRAINT tasks_done_implies_full CHECK (((status <> 'Concluído'::public.task_status) OR (progress = 100)))
);

ALTER TABLE ONLY public.tasks FORCE ROW LEVEL SECURITY;


--
-- Name: robot_weighted_progress; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.robot_weighted_progress WITH (security_invoker='true') AS
 SELECT r.id AS robot_id,
    r.workspace_id,
        CASE
            WHEN (count(t.id) = 0) THEN 0
            WHEN (count(t.id) FILTER (WHERE (t.status <> 'N/A'::public.task_status)) = 0) THEN 100
            WHEN (COALESCE(sum((t.weight * (100)::numeric)) FILTER (WHERE (t.status <> 'N/A'::public.task_status)), (0)::numeric) = (0)::numeric) THEN 100
            ELSE (round(((sum((t.weight * (t.progress)::numeric)) FILTER (WHERE (t.status <> 'N/A'::public.task_status)) / sum((t.weight * (100)::numeric)) FILTER (WHERE (t.status <> 'N/A'::public.task_status))) * (100)::numeric)))::integer
        END AS value
   FROM (public.robots r
     LEFT JOIN public.tasks t ON (((t.robot_id = r.id) AND (t.workspace_id = r.workspace_id) AND (t.deleted_at IS NULL))))
  WHERE (r.deleted_at IS NULL)
  GROUP BY r.id, r.workspace_id;


--
-- Name: cell_weighted_progress; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.cell_weighted_progress WITH (security_invoker='true') AS
 SELECT c.id AS cell_id,
    c.workspace_id,
    (COALESCE(round(avg(rwp.value)), (0)::numeric))::integer AS value
   FROM ((public.cells c
     LEFT JOIN public.robots r ON (((r.cell_id = c.id) AND (r.workspace_id = c.workspace_id) AND (r.deleted_at IS NULL))))
     LEFT JOIN public.robot_weighted_progress rwp ON (((rwp.robot_id = r.id) AND (rwp.workspace_id = c.workspace_id))))
  WHERE (c.deleted_at IS NULL)
  GROUP BY c.id, c.workspace_id;


--
-- Name: jwt_denylist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jwt_denylist (
    id bigint NOT NULL,
    jti character varying NOT NULL,
    exp timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: jwt_denylist_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jwt_denylist_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jwt_denylist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jwt_denylist_id_seq OWNED BY public.jwt_denylist.id;


--
-- Name: membership_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.membership_revocations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    person_id uuid NOT NULL,
    role public.membership_role NOT NULL,
    invitation_id uuid,
    removed_by_user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.membership_revocations FORCE ROW LEVEL SECURITY;


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    person_id uuid NOT NULL,
    role public.membership_role NOT NULL,
    invitation_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.memberships FORCE ROW LEVEL SECURITY;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    recipient_person_id uuid NOT NULL,
    actor_person_id uuid NOT NULL,
    type public.notification_type NOT NULL,
    msg text NOT NULL,
    author_name_snapshot text NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    ts_local text NOT NULL,
    read boolean DEFAULT false NOT NULL,
    read_at timestamp with time zone,
    ctx_project_id uuid,
    ctx_cell_id uuid,
    ctx_robot_id uuid,
    ctx_task_id uuid,
    format_version smallint DEFAULT 1 NOT NULL,
    CONSTRAINT msg_max_500 CHECK ((char_length(msg) <= 500)),
    CONSTRAINT read_at_coherence CHECK ((((read = false) AND (read_at IS NULL)) OR ((read = true) AND (read_at IS NOT NULL))))
);

ALTER TABLE ONLY public.notifications FORCE ROW LEVEL SECURITY;


--
-- Name: people; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.people (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    email public.citext,
    user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    CONSTRAINT chk_people_name_not_blank CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT people_name_not_sentinel CHECK ((btrim(lower(name)) <> ALL (ARRAY['não atribuído'::text, 'nao atribuido'::text])))
);

ALTER TABLE ONLY public.people FORCE ROW LEVEL SECURITY;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    "position" integer,
    progress_cache smallint DEFAULT 0 NOT NULL,
    progress_cached_at timestamp with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    updated_by_person_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_projects_name CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 120))),
    CONSTRAINT chk_projects_progress_cache CHECK (((progress_cache >= 0) AND (progress_cache <= 100)))
);

ALTER TABLE ONLY public.projects FORCE ROW LEVEL SECURITY;


--
-- Name: project_weighted_progress; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.project_weighted_progress WITH (security_invoker='true') AS
 SELECT p.id AS project_id,
    p.workspace_id,
    (COALESCE(round(avg(cwp.value)), (0)::numeric))::integer AS value
   FROM ((public.projects p
     LEFT JOIN public.cells c ON (((c.project_id = p.id) AND (c.workspace_id = p.workspace_id) AND (c.deleted_at IS NULL))))
     LEFT JOIN public.cell_weighted_progress cwp ON (((cwp.cell_id = c.id) AND (cwp.workspace_id = p.workspace_id))))
  WHERE (p.deleted_at IS NULL)
  GROUP BY p.id, p.workspace_id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: subtree_raw_completion; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.subtree_raw_completion WITH (security_invoker='true') AS
 SELECT 'robot'::text AS scope_type,
    r.id AS scope_id,
    r.workspace_id,
    (count(t.id) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::integer AS completed,
    (count(t.id))::integer AS total,
        CASE
            WHEN (count(t.id) = 0) THEN 0
            ELSE (round((((count(t.id) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::numeric / (count(t.id))::numeric) * (100)::numeric)))::integer
        END AS percent
   FROM (public.robots r
     LEFT JOIN public.tasks t ON (((t.robot_id = r.id) AND (t.workspace_id = r.workspace_id) AND (t.deleted_at IS NULL))))
  WHERE (r.deleted_at IS NULL)
  GROUP BY r.id, r.workspace_id
UNION ALL
 SELECT 'cell'::text AS scope_type,
    c.id AS scope_id,
    c.workspace_id,
    (count(t.id) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::integer AS completed,
    (count(t.id))::integer AS total,
        CASE
            WHEN (count(t.id) = 0) THEN 0
            ELSE (round((((count(t.id) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::numeric / (count(t.id))::numeric) * (100)::numeric)))::integer
        END AS percent
   FROM ((public.cells c
     LEFT JOIN public.robots r ON (((r.cell_id = c.id) AND (r.workspace_id = c.workspace_id) AND (r.deleted_at IS NULL))))
     LEFT JOIN public.tasks t ON (((t.robot_id = r.id) AND (t.workspace_id = c.workspace_id) AND (t.deleted_at IS NULL))))
  WHERE (c.deleted_at IS NULL)
  GROUP BY c.id, c.workspace_id
UNION ALL
 SELECT 'project'::text AS scope_type,
    p.id AS scope_id,
    p.workspace_id,
    (count(t.id) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::integer AS completed,
    (count(t.id))::integer AS total,
        CASE
            WHEN (count(t.id) = 0) THEN 0
            ELSE (round((((count(t.id) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::numeric / (count(t.id))::numeric) * (100)::numeric)))::integer
        END AS percent
   FROM (((public.projects p
     LEFT JOIN public.cells c ON (((c.project_id = p.id) AND (c.workspace_id = p.workspace_id) AND (c.deleted_at IS NULL))))
     LEFT JOIN public.robots r ON (((r.cell_id = c.id) AND (r.workspace_id = p.workspace_id) AND (r.deleted_at IS NULL))))
     LEFT JOIN public.tasks t ON (((t.robot_id = r.id) AND (t.workspace_id = p.workspace_id) AND (t.deleted_at IS NULL))))
  WHERE (p.deleted_at IS NULL)
  GROUP BY p.id, p.workspace_id
UNION ALL
 SELECT 'workspace'::text AS scope_type,
    t.workspace_id AS scope_id,
    t.workspace_id,
    (count(*) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::integer AS completed,
    (count(*))::integer AS total,
        CASE
            WHEN (count(*) = 0) THEN 0
            ELSE (round((((count(*) FILTER (WHERE (t.status = 'Concluído'::public.task_status)))::numeric / (count(*))::numeric) * (100)::numeric)))::integer
        END AS percent
   FROM public.tasks t
  WHERE (t.deleted_at IS NULL)
  GROUP BY t.workspace_id;


--
-- Name: task_advances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_advances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    task_id uuid NOT NULL,
    by uuid,
    author_name_snapshot text NOT NULL,
    from_progress smallint NOT NULL,
    to_progress smallint NOT NULL,
    comment text,
    legacy boolean DEFAULT false NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    recorded_at_adjusted boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_ta_author_name CHECK (((length(btrim(author_name_snapshot)) >= 1) AND (length(btrim(author_name_snapshot)) <= 200))),
    CONSTRAINT chk_ta_author_null_only_legacy CHECK (((by IS NOT NULL) OR legacy)),
    CONSTRAINT chk_ta_comment_len CHECK (((comment IS NULL) OR (char_length(comment) <= 1000))),
    CONSTRAINT chk_ta_comment_required CHECK (((to_progress = 100) OR legacy OR ((comment IS NOT NULL) AND (btrim(comment) <> ''::text)))),
    CONSTRAINT chk_ta_from_range CHECK (((from_progress >= 0) AND (from_progress <= 100))),
    CONSTRAINT chk_ta_recorded_at CHECK ((recorded_at <= (created_at + '00:10:00'::interval))),
    CONSTRAINT chk_ta_to_range CHECK (((to_progress >= 0) AND (to_progress <= 100)))
);

ALTER TABLE ONLY public.task_advances FORCE ROW LEVEL SECURITY;


--
-- Name: task_assignees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_assignees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    task_id uuid NOT NULL,
    person_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.task_assignees FORCE ROW LEVEL SECURITY;


--
-- Name: task_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    cat text NOT NULL,
    "desc" text NOT NULL,
    weight numeric DEFAULT 1 NOT NULL,
    app_filters text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_task_templates_app_filters CHECK ((app_filters <@ ARRAY['Misto / Geral'::text, 'Solda Ponto'::text, 'Solda MIG'::text, 'Handling'::text, 'Sealing'::text, 'Outros'::text, 'Todas'::text])),
    CONSTRAINT chk_task_templates_cat CHECK (((length(btrim(cat)) >= 1) AND (length(btrim(cat)) <= 120))),
    CONSTRAINT chk_task_templates_desc CHECK (((length(btrim("desc")) >= 1) AND (length(btrim("desc")) <= 200))),
    CONSTRAINT chk_task_templates_weight CHECK ((weight > (0)::numeric))
);

ALTER TABLE ONLY public.task_templates FORCE ROW LEVEL SECURITY;


--
-- Name: user_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    description text,
    hierarchy_level integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying NOT NULL,
    phone character varying,
    name character varying NOT NULL,
    avatar_url text,
    user_type_id uuid,
    provider character varying,
    provider_uid character varying,
    last_login_at timestamp(6) without time zone,
    login_count integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    cpf_cnpj character varying,
    cep character varying,
    street character varying,
    number character varying,
    complement character varying,
    district character varying,
    city character varying,
    state character varying,
    credit_card_formal character varying,
    credit_card_number character varying,
    credit_card_expiration_month character varying,
    credit_card_expiration_year character varying,
    credit_card_token character varying,
    cardholder_name character varying,
    cardholder_email character varying,
    cardholder_cpf_cnpj character varying,
    cardholder_postal_code character varying,
    cardholder_address_number character varying,
    cardholder_address_complement character varying,
    customer_id character varying,
    subscription_id character varying,
    plan_id integer,
    credit_card_brand character varying,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    CONSTRAINT users_credential_present CHECK (((provider IS NOT NULL) OR ((encrypted_password)::text <> ''::text))),
    CONSTRAINT users_name_min_length CHECK ((char_length(btrim((name)::text)) >= 2))
);


--
-- Name: workspace_backups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_backups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    checksum text,
    counts jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    consumed_at timestamp with time zone,
    CONSTRAINT chk_wb_status CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text])))
);

ALTER TABLE ONLY public.workspace_backups FORCE ROW LEVEL SECURITY;


--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    owner_user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    realtime_seq bigint DEFAULT 0 NOT NULL
);

ALTER TABLE ONLY public.workspaces FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ATTACH PARTITION public.audit_logs_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: audit_logs_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ATTACH PARTITION public.audit_logs_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


--
-- Name: audit_logs_2026_09; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ATTACH PARTITION public.audit_logs_2026_09 FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');


--
-- Name: audit_logs_2026_10; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ATTACH PARTITION public.audit_logs_2026_10 FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');


--
-- Name: audit_logs_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ATTACH PARTITION public.audit_logs_default DEFAULT;


--
-- Name: jwt_denylist id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jwt_denylist ALTER COLUMN id SET DEFAULT nextval('public.jwt_denylist_id_seq'::regclass);


--
-- Name: action_text_rich_texts action_text_rich_texts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_text_rich_texts
    ADD CONSTRAINT action_text_rich_texts_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (ts, id);


--
-- Name: audit_logs_2026_07 audit_logs_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs_2026_07
    ADD CONSTRAINT audit_logs_2026_07_pkey PRIMARY KEY (ts, id);


--
-- Name: audit_logs_2026_08 audit_logs_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs_2026_08
    ADD CONSTRAINT audit_logs_2026_08_pkey PRIMARY KEY (ts, id);


--
-- Name: audit_logs_2026_09 audit_logs_2026_09_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs_2026_09
    ADD CONSTRAINT audit_logs_2026_09_pkey PRIMARY KEY (ts, id);


--
-- Name: audit_logs_2026_10 audit_logs_2026_10_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs_2026_10
    ADD CONSTRAINT audit_logs_2026_10_pkey PRIMARY KEY (ts, id);


--
-- Name: audit_logs_default audit_logs_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs_default
    ADD CONSTRAINT audit_logs_default_pkey PRIMARY KEY (ts, id);


--
-- Name: cells cells_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cells
    ADD CONSTRAINT cells_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: jwt_denylist jwt_denylist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jwt_denylist
    ADD CONSTRAINT jwt_denylist_pkey PRIMARY KEY (id);


--
-- Name: membership_revocations membership_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_revocations
    ADD CONSTRAINT membership_revocations_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: people people_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: robots robots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.robots
    ADD CONSTRAINT robots_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: task_advances task_advances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_advances
    ADD CONSTRAINT task_advances_pkey PRIMARY KEY (id);


--
-- Name: task_assignees task_assignees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_assignees
    ADD CONSTRAINT task_assignees_pkey PRIMARY KEY (id);


--
-- Name: task_templates task_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_templates
    ADD CONSTRAINT task_templates_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: cells uq_cells_id_workspace; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cells
    ADD CONSTRAINT uq_cells_id_workspace UNIQUE (id, workspace_id);


--
-- Name: cells uq_cells_position; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cells
    ADD CONSTRAINT uq_cells_position UNIQUE (project_id, "position") DEFERRABLE INITIALLY DEFERRED;


--
-- Name: projects uq_projects_id_workspace; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT uq_projects_id_workspace UNIQUE (id, workspace_id);


--
-- Name: projects uq_projects_position; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT uq_projects_position UNIQUE (workspace_id, "position") DEFERRABLE INITIALLY DEFERRED;


--
-- Name: robots uq_robots_id_workspace; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.robots
    ADD CONSTRAINT uq_robots_id_workspace UNIQUE (id, workspace_id);


--
-- Name: robots uq_robots_position; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.robots
    ADD CONSTRAINT uq_robots_position UNIQUE (cell_id, "position") DEFERRABLE INITIALLY DEFERRED;


--
-- Name: task_assignees uq_task_assignees_task_person; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_assignees
    ADD CONSTRAINT uq_task_assignees_task_person UNIQUE (task_id, person_id);


--
-- Name: task_templates uq_task_templates_id_workspace; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_templates
    ADD CONSTRAINT uq_task_templates_id_workspace UNIQUE (id, workspace_id);


--
-- Name: tasks uq_tasks_id_workspace; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT uq_tasks_id_workspace UNIQUE (id, workspace_id);


--
-- Name: user_types user_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_types
    ADD CONSTRAINT user_types_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: workspace_backups workspace_backups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_backups
    ADD CONSTRAINT workspace_backups_pkey PRIMARY KEY (id);


--
-- Name: workspaces workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);


--
-- Name: index_audit_logs_on_workspace_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_workspace_ts ON ONLY public.audit_logs USING btree (workspace_id, ts DESC);


--
-- Name: audit_logs_2026_07_workspace_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_2026_07_workspace_id_ts_idx ON public.audit_logs_2026_07 USING btree (workspace_id, ts DESC);


--
-- Name: audit_logs_2026_08_workspace_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_2026_08_workspace_id_ts_idx ON public.audit_logs_2026_08 USING btree (workspace_id, ts DESC);


--
-- Name: audit_logs_2026_09_workspace_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_2026_09_workspace_id_ts_idx ON public.audit_logs_2026_09 USING btree (workspace_id, ts DESC);


--
-- Name: audit_logs_2026_10_workspace_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_2026_10_workspace_id_ts_idx ON public.audit_logs_2026_10 USING btree (workspace_id, ts DESC);


--
-- Name: audit_logs_default_workspace_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_default_workspace_id_ts_idx ON public.audit_logs_default USING btree (workspace_id, ts DESC);


--
-- Name: idx_memberships_one_per_invitation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_memberships_one_per_invitation ON public.memberships USING btree (invitation_id) WHERE (invitation_id IS NOT NULL);


--
-- Name: idx_notifications_assign_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_notifications_assign_idempotency ON public.notifications USING btree (recipient_person_id, ctx_task_id, type, recorded_at) WHERE (type = 'assign'::public.notification_type);


--
-- Name: idx_notifications_center; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_center ON public.notifications USING btree (workspace_id, recipient_person_id, recorded_at DESC);


--
-- Name: idx_notifications_retention; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_retention ON public.notifications USING btree (workspace_id, read, recorded_at);


--
-- Name: idx_task_assignees_ws_person; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_assignees_ws_person ON public.task_assignees USING btree (workspace_id, person_id) INCLUDE (task_id);


--
-- Name: idx_tasks_open_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_open_ws ON public.tasks USING btree (workspace_id, id) WHERE (status = ANY (ARRAY['Pendente'::public.task_status, 'Em Andamento'::public.task_status]));


--
-- Name: idx_tasks_ws_robot_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_ws_robot_status ON public.tasks USING btree (workspace_id, robot_id, status) WHERE (deleted_at IS NULL);


--
-- Name: index_action_text_rich_texts_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_action_text_rich_texts_uniqueness ON public.action_text_rich_texts USING btree (record_type, record_id, name);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_variant_records_on_blob_id ON public.active_storage_variant_records USING btree (blob_id);


--
-- Name: index_active_storage_variants_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variants_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_cells_on_project_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cells_on_project_lower_name ON public.cells USING btree (project_id, lower(name)) WHERE (deleted_at IS NULL);


--
-- Name: index_cells_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cells_on_workspace_id ON public.cells USING btree (workspace_id);


--
-- Name: index_cells_on_workspace_id_live; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cells_on_workspace_id_live ON public.cells USING btree (workspace_id) WHERE (deleted_at IS NULL);


--
-- Name: index_invitations_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_token ON public.invitations USING btree (token);


--
-- Name: index_invitations_on_workspace_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_workspace_id_and_created_at ON public.invitations USING btree (workspace_id, created_at DESC);


--
-- Name: index_invitations_pending_unique_per_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_pending_unique_per_email ON public.invitations USING btree (workspace_id, email) WHERE (used_at IS NULL);


--
-- Name: index_jwt_denylist_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_jwt_denylist_on_jti ON public.jwt_denylist USING btree (jti);


--
-- Name: index_membership_revocations_on_workspace_and_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_membership_revocations_on_workspace_and_user ON public.membership_revocations USING btree (workspace_id, user_id);


--
-- Name: index_memberships_on_workspace_id_and_person_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_workspace_id_and_person_id ON public.memberships USING btree (workspace_id, person_id);


--
-- Name: index_memberships_on_workspace_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_workspace_id_and_user_id ON public.memberships USING btree (workspace_id, user_id);


--
-- Name: index_people_on_workspace_id_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_people_on_workspace_id_and_email ON public.people USING btree (workspace_id, email) WHERE (email IS NOT NULL);


--
-- Name: index_people_on_workspace_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_people_on_workspace_id_and_id ON public.people USING btree (workspace_id, id);


--
-- Name: index_people_on_workspace_id_and_normalized_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_people_on_workspace_id_and_normalized_name ON public.people USING btree (workspace_id, lower(btrim(name))) WHERE (archived_at IS NULL);


--
-- Name: index_people_on_workspace_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_people_on_workspace_id_and_user_id ON public.people USING btree (workspace_id, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: index_projects_on_workspace_id_live; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_workspace_id_live ON public.projects USING btree (workspace_id) WHERE (deleted_at IS NULL);


--
-- Name: index_projects_on_workspace_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_workspace_lower_name ON public.projects USING btree (workspace_id, lower(name)) WHERE (deleted_at IS NULL);


--
-- Name: index_robots_on_cell_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_robots_on_cell_lower_name ON public.robots USING btree (cell_id, lower(name)) WHERE (deleted_at IS NULL);


--
-- Name: index_robots_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_robots_on_workspace_id ON public.robots USING btree (workspace_id);


--
-- Name: index_robots_on_workspace_id_live; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_robots_on_workspace_id_live ON public.robots USING btree (workspace_id) WHERE (deleted_at IS NULL);


--
-- Name: index_task_advances_on_workspace_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_advances_on_workspace_task ON public.task_advances USING btree (workspace_id, task_id);


--
-- Name: index_task_advances_trail; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_advances_trail ON public.task_advances USING btree (task_id, recorded_at DESC, created_at DESC, id DESC);


--
-- Name: index_task_assignees_on_person_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_assignees_on_person_task ON public.task_assignees USING btree (person_id, task_id);


--
-- Name: index_task_assignees_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_assignees_on_workspace_id ON public.task_assignees USING btree (workspace_id);


--
-- Name: index_task_templates_on_workspace_cat_desc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_templates_on_workspace_cat_desc ON public.task_templates USING btree (workspace_id, cat, "desc");


--
-- Name: index_task_templates_on_workspace_lower_desc; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_task_templates_on_workspace_lower_desc ON public.task_templates USING btree (workspace_id, lower(btrim("desc")));


--
-- Name: index_tasks_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_deleted_at ON public.tasks USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);


--
-- Name: index_tasks_on_robot_lower_desc; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tasks_on_robot_lower_desc ON public.tasks USING btree (robot_id, lower(btrim("desc"))) WHERE (deleted_at IS NULL);


--
-- Name: index_tasks_on_robot_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_robot_position ON public.tasks USING btree (robot_id, "position");


--
-- Name: index_tasks_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_workspace_id ON public.tasks USING btree (workspace_id);


--
-- Name: index_user_types_on_hierarchy_level; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_types_on_hierarchy_level ON public.user_types USING btree (hierarchy_level);


--
-- Name: index_user_types_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_types_on_name ON public.user_types USING btree (name);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_email_and_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_email_and_phone ON public.users USING btree (email, phone);


--
-- Name: index_users_on_last_login_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_last_login_at ON public.users USING btree (last_login_at);


--
-- Name: index_users_on_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_phone ON public.users USING btree (phone) WHERE (phone IS NOT NULL);


--
-- Name: index_users_on_provider_and_provider_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_provider_and_provider_uid ON public.users USING btree (provider, provider_uid) WHERE ((provider IS NOT NULL) AND (provider_uid IS NOT NULL));


--
-- Name: index_users_on_user_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_user_type_id ON public.users USING btree (user_type_id);


--
-- Name: index_workspace_backups_on_workspace_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workspace_backups_on_workspace_created ON public.workspace_backups USING btree (workspace_id, created_at DESC);


--
-- Name: index_workspaces_on_owner_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_workspaces_on_owner_user_id ON public.workspaces USING btree (owner_user_id);


--
-- Name: audit_logs_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_logs_pkey ATTACH PARTITION public.audit_logs_2026_07_pkey;


--
-- Name: audit_logs_2026_07_workspace_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_audit_logs_on_workspace_ts ATTACH PARTITION public.audit_logs_2026_07_workspace_id_ts_idx;


--
-- Name: audit_logs_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_logs_pkey ATTACH PARTITION public.audit_logs_2026_08_pkey;


--
-- Name: audit_logs_2026_08_workspace_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_audit_logs_on_workspace_ts ATTACH PARTITION public.audit_logs_2026_08_workspace_id_ts_idx;


--
-- Name: audit_logs_2026_09_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_logs_pkey ATTACH PARTITION public.audit_logs_2026_09_pkey;


--
-- Name: audit_logs_2026_09_workspace_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_audit_logs_on_workspace_ts ATTACH PARTITION public.audit_logs_2026_09_workspace_id_ts_idx;


--
-- Name: audit_logs_2026_10_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_logs_pkey ATTACH PARTITION public.audit_logs_2026_10_pkey;


--
-- Name: audit_logs_2026_10_workspace_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_audit_logs_on_workspace_ts ATTACH PARTITION public.audit_logs_2026_10_workspace_id_ts_idx;


--
-- Name: audit_logs_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_logs_pkey ATTACH PARTITION public.audit_logs_default_pkey;


--
-- Name: audit_logs_default_workspace_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_audit_logs_on_workspace_ts ATTACH PARTITION public.audit_logs_default_workspace_id_ts_idx;


--
-- Name: memberships memberships_owner_is_not_member; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER memberships_owner_is_not_member BEFORE INSERT OR UPDATE ON public.memberships FOR EACH ROW EXECUTE FUNCTION public.memberships_owner_is_not_member();


--
-- Name: notifications notifications_before_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notifications_before_insert BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.notifications_no_insert_read();


--
-- Name: notifications notifications_before_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notifications_before_update BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.notifications_only_read_update();


--
-- Name: audit_logs trg_audit_logs_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_logs_immutable BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.audit_logs_forbid_mutation();


--
-- Name: people trg_people_forbid_archive_active_member; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_people_forbid_archive_active_member BEFORE UPDATE OF archived_at ON public.people FOR EACH ROW EXECUTE FUNCTION public.people_forbid_archive_active_member();


--
-- Name: task_advances trg_task_advances_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_task_advances_immutable BEFORE DELETE OR UPDATE ON public.task_advances FOR EACH ROW EXECUTE FUNCTION public.task_advances_forbid_mutation();


--
-- Name: workspaces workspaces_owner_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER workspaces_owner_immutable BEFORE UPDATE ON public.workspaces FOR EACH ROW EXECUTE FUNCTION public.workspaces_owner_immutable();


--
-- Name: cells cells_updated_by_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cells
    ADD CONSTRAINT cells_updated_by_person_id_fkey FOREIGN KEY (updated_by_person_id) REFERENCES public.people(id) ON DELETE SET NULL;


--
-- Name: cells cells_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cells
    ADD CONSTRAINT cells_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: audit_logs fk_audit_author; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs
    ADD CONSTRAINT fk_audit_author FOREIGN KEY (by_person_id) REFERENCES public.people(id) ON DELETE SET NULL;


--
-- Name: audit_logs fk_audit_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs
    ADD CONSTRAINT fk_audit_workspace FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;


--
-- Name: cells fk_cells_project_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cells
    ADD CONSTRAINT fk_cells_project_same_workspace FOREIGN KEY (project_id, workspace_id) REFERENCES public.projects(id, workspace_id) ON DELETE CASCADE;


--
-- Name: invitations fk_invitations_creator_in_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_invitations_creator_in_workspace FOREIGN KEY (workspace_id, created_by_person_id) REFERENCES public.people(workspace_id, id);


--
-- Name: memberships fk_memberships_invitation; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_invitation FOREIGN KEY (invitation_id) REFERENCES public.invitations(id) ON DELETE RESTRICT;


--
-- Name: memberships fk_memberships_person_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_person_same_workspace FOREIGN KEY (workspace_id, person_id) REFERENCES public.people(workspace_id, id);


--
-- Name: robots fk_robots_cell_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.robots
    ADD CONSTRAINT fk_robots_cell_same_workspace FOREIGN KEY (cell_id, workspace_id) REFERENCES public.cells(id, workspace_id) ON DELETE CASCADE;


--
-- Name: task_advances fk_ta_author_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_advances
    ADD CONSTRAINT fk_ta_author_same_workspace FOREIGN KEY (workspace_id, by) REFERENCES public.people(workspace_id, id) ON DELETE RESTRICT;


--
-- Name: task_advances fk_ta_task_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_advances
    ADD CONSTRAINT fk_ta_task_same_workspace FOREIGN KEY (task_id, workspace_id) REFERENCES public.tasks(id, workspace_id) ON DELETE RESTRICT;


--
-- Name: task_assignees fk_task_assignees_person_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_assignees
    ADD CONSTRAINT fk_task_assignees_person_same_workspace FOREIGN KEY (workspace_id, person_id) REFERENCES public.people(workspace_id, id) ON DELETE RESTRICT;


--
-- Name: task_assignees fk_task_assignees_task_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_assignees
    ADD CONSTRAINT fk_task_assignees_task_same_workspace FOREIGN KEY (task_id, workspace_id) REFERENCES public.tasks(id, workspace_id) ON DELETE CASCADE;


--
-- Name: tasks fk_tasks_robot_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_tasks_robot_same_workspace FOREIGN KEY (robot_id, workspace_id) REFERENCES public.robots(id, workspace_id) ON DELETE CASCADE;


--
-- Name: invitations invitations_used_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_used_by_user_id_fkey FOREIGN KEY (used_by_user_id) REFERENCES public.users(id);


--
-- Name: invitations invitations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: membership_revocations membership_revocations_removed_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_revocations
    ADD CONSTRAINT membership_revocations_removed_by_user_id_fkey FOREIGN KEY (removed_by_user_id) REFERENCES public.users(id);


--
-- Name: membership_revocations membership_revocations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_revocations
    ADD CONSTRAINT membership_revocations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: membership_revocations membership_revocations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_revocations
    ADD CONSTRAINT membership_revocations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: memberships memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: memberships memberships_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: notifications notifications_actor_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_actor_person_id_fkey FOREIGN KEY (actor_person_id) REFERENCES public.people(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_ctx_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_ctx_task_id_fkey FOREIGN KEY (ctx_task_id) REFERENCES public.tasks(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_recipient_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_recipient_person_id_fkey FOREIGN KEY (recipient_person_id) REFERENCES public.people(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: people people_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: people people_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: projects projects_updated_by_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_updated_by_person_id_fkey FOREIGN KEY (updated_by_person_id) REFERENCES public.people(id) ON DELETE SET NULL;


--
-- Name: projects projects_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: robots robots_updated_by_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.robots
    ADD CONSTRAINT robots_updated_by_person_id_fkey FOREIGN KEY (updated_by_person_id) REFERENCES public.people(id) ON DELETE SET NULL;


--
-- Name: robots robots_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.robots
    ADD CONSTRAINT robots_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: task_advances task_advances_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_advances
    ADD CONSTRAINT task_advances_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: task_assignees task_assignees_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_assignees
    ADD CONSTRAINT task_assignees_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: task_templates task_templates_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_templates
    ADD CONSTRAINT task_templates_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: tasks tasks_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: workspace_backups workspace_backups_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_backups
    ADD CONSTRAINT workspace_backups_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspaces workspaces_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id);


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs_2026_07; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs_2026_07 ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs_2026_08; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs_2026_08 ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs_2026_09; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs_2026_09 ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs_2026_10; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs_2026_10 ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs_default; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs_default ENABLE ROW LEVEL SECURITY;

--
-- Name: cells; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cells ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: membership_revocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.membership_revocations ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: people; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.people ENABLE ROW LEVEL SECURITY;

--
-- Name: projects; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations purge_expired; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY purge_expired ON public.invitations FOR DELETE USING (((current_setting('app.invitation_purge'::text, true) = 'on'::text) AND (used_at IS NULL) AND (expires_at < (now() - '30 days'::interval))));


--
-- Name: invitations purge_expired_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY purge_expired_delete ON public.invitations FOR DELETE USING (((current_setting('app.invitation_purge'::text, true) = 'on'::text) AND (used_at IS NULL) AND (expires_at < (now() - '30 days'::interval))));


--
-- Name: invitations purge_expired_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY purge_expired_select ON public.invitations FOR SELECT USING (((current_setting('app.invitation_purge'::text, true) = 'on'::text) AND (used_at IS NULL) AND (expires_at < (now() - '30 days'::interval))));


--
-- Name: robots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.robots ENABLE ROW LEVEL SECURITY;

--
-- Name: task_advances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_advances ENABLE ROW LEVEL SECURITY;

--
-- Name: task_assignees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_assignees ENABLE ROW LEVEL SECURITY;

--
-- Name: task_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: tasks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_07 tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs_2026_07 FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_08 tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs_2026_08 FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_09 tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs_2026_09 FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_10 tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs_2026_10 FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_default tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs_default FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: cells tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.cells USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: invitations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invitations USING (((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid) OR (token = NULLIF(current_setting('app.invitation_token'::text, true), ''::text)))) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: membership_revocations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.membership_revocations USING (((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid) OR (user_id = (NULLIF(current_setting('app.current_user_id'::text, true), ''::text))::uuid))) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: memberships tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.memberships USING (((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid) OR (user_id = (NULLIF(current_setting('app.current_user_id'::text, true), ''::text))::uuid))) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: notifications tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.notifications USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: people tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.people USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: projects tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.projects USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: robots tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.robots USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: task_advances tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.task_advances FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: task_assignees tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.task_assignees USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: task_templates tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.task_templates USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: tasks tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.tasks USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: workspace_backups tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.workspace_backups FOR SELECT USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: workspaces tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.workspaces USING (((id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid) OR (owner_user_id = (NULLIF(current_setting('app.current_user_id'::text, true), ''::text))::uuid) OR (EXISTS ( SELECT 1
   FROM public.memberships m
  WHERE ((m.workspace_id = workspaces.id) AND (m.user_id = (NULLIF(current_setting('app.current_user_id'::text, true), ''::text))::uuid)))))) WITH CHECK ((id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.audit_logs FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_07 tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.audit_logs_2026_07 FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_08 tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.audit_logs_2026_08 FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_09 tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.audit_logs_2026_09 FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_2026_10 tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.audit_logs_2026_10 FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: audit_logs_default tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.audit_logs_default FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: task_advances tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.task_advances FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: workspace_backups tenant_isolation_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_insert ON public.workspace_backups FOR INSERT WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: workspace_backups tenant_isolation_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_update ON public.workspace_backups FOR UPDATE USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: workspace_backups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspace_backups ENABLE ROW LEVEL SECURITY;

--
-- Name: workspaces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260724100003'),
('20260724100002'),
('20260724100001'),
('20260723160001'),
('20260723150001'),
('20260723140002'),
('20260723140001'),
('20260723130002'),
('20260723130001'),
('20260723120003'),
('20260723120002'),
('20260723120001'),
('20260722130002'),
('20260722130001'),
('20260722120002'),
('20260722120001'),
('20260721160005'),
('20260721160004'),
('20260721160003'),
('20260721160002'),
('20260721160001'),
('20260721150002'),
('20260721150001'),
('20260721140001'),
('20260721130005'),
('20260721130004'),
('20260721130003'),
('20260721130002'),
('20260721130001'),
('20260721120005'),
('20260721120004'),
('20260721120003'),
('20260721120002'),
('20260721120001'),
('20260720190002'),
('20260720190001'),
('20260720180006'),
('20260720180005'),
('20260720180004'),
('20260720180003'),
('20260720180002'),
('20260720180001'),
('20260720170117'),
('20251117180000'),
('20251117170500'),
('20251116170500'),
('20251114153000'),
('20241201000002'),
('20241201000001');

