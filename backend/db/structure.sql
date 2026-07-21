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
-- Name: cells; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cells (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    project_id uuid NOT NULL,
    name text NOT NULL,
    "position" integer NOT NULL,
    progress_cache jsonb DEFAULT '{}'::jsonb NOT NULL,
    progress_cached_at timestamp with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    updated_by_person_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_cells_name CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 120)))
);

ALTER TABLE ONLY public.cells FORCE ROW LEVEL SECURITY;


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
    "position" integer NOT NULL,
    progress_cache jsonb DEFAULT '{}'::jsonb NOT NULL,
    progress_cached_at timestamp with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    updated_by_person_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_projects_name CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 120)))
);

ALTER TABLE ONLY public.projects FORCE ROW LEVEL SECURITY;


--
-- Name: robots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.robots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    cell_id uuid NOT NULL,
    name text NOT NULL,
    application text DEFAULT 'Misto / Geral'::text NOT NULL,
    "position" integer NOT NULL,
    progress_cache jsonb DEFAULT '{}'::jsonb NOT NULL,
    progress_cached_at timestamp with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    updated_by_person_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_robots_application CHECK ((application = ANY (ARRAY['Misto / Geral'::text, 'Solda Ponto'::text, 'Solda MIG'::text, 'Handling'::text, 'Sealing'::text, 'Outros'::text]))),
    CONSTRAINT chk_robots_name CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 120)))
);

ALTER TABLE ONLY public.robots FORCE ROW LEVEL SECURITY;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


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
-- Name: workspaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    owner_user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.workspaces FORCE ROW LEVEL SECURITY;


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
-- Name: workspaces workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);


--
-- Name: idx_memberships_one_per_invitation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_memberships_one_per_invitation ON public.memberships USING btree (invitation_id) WHERE (invitation_id IS NOT NULL);


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

CREATE UNIQUE INDEX index_cells_on_project_lower_name ON public.cells USING btree (project_id, lower(name));


--
-- Name: index_cells_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cells_on_workspace_id ON public.cells USING btree (workspace_id);


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

CREATE UNIQUE INDEX index_people_on_workspace_id_and_normalized_name ON public.people USING btree (workspace_id, lower(btrim(name)));


--
-- Name: index_people_on_workspace_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_people_on_workspace_id_and_user_id ON public.people USING btree (workspace_id, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: index_projects_on_workspace_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_workspace_lower_name ON public.projects USING btree (workspace_id, lower(name));


--
-- Name: index_robots_on_cell_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_robots_on_cell_lower_name ON public.robots USING btree (cell_id, lower(name));


--
-- Name: index_robots_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_robots_on_workspace_id ON public.robots USING btree (workspace_id);


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
-- Name: index_workspaces_on_owner_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_workspaces_on_owner_user_id ON public.workspaces USING btree (owner_user_id);


--
-- Name: memberships memberships_owner_is_not_member; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER memberships_owner_is_not_member BEFORE INSERT OR UPDATE ON public.memberships FOR EACH ROW EXECUTE FUNCTION public.memberships_owner_is_not_member();


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
-- Name: workspaces workspaces_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id);


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
-- Name: workspaces tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.workspaces USING (((id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid) OR (owner_user_id = (NULLIF(current_setting('app.current_user_id'::text, true), ''::text))::uuid) OR (EXISTS ( SELECT 1
   FROM public.memberships m
  WHERE ((m.workspace_id = workspaces.id) AND (m.user_id = (NULLIF(current_setting('app.current_user_id'::text, true), ''::text))::uuid)))))) WITH CHECK ((id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: workspaces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

