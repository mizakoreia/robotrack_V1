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
-- Name: membership_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.membership_role AS ENUM (
    'edit',
    'view'
);


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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
    email character varying,
    phone character varying,
    name character varying NOT NULL,
    avatar_url text,
    user_type_id uuid NOT NULL,
    provider character varying,
    provider_uid character varying,
    last_login_at timestamp(6) without time zone,
    login_count integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    jti character varying,
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
    credit_card_brand character varying
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
-- Name: jwt_denylist jwt_denylist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jwt_denylist
    ADD CONSTRAINT jwt_denylist_pkey PRIMARY KEY (id);


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
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


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
-- Name: index_jwt_denylist_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jwt_denylist_on_jti ON public.jwt_denylist USING btree (jti);


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

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email) WHERE (email IS NOT NULL);


--
-- Name: index_users_on_email_and_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_email_and_phone ON public.users USING btree (email, phone);


--
-- Name: index_users_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_jti ON public.users USING btree (jti);


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
-- Name: memberships fk_memberships_person_same_workspace; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_person_same_workspace FOREIGN KEY (workspace_id, person_id) REFERENCES public.people(workspace_id, id);


--
-- Name: users fk_rails_a2f1461231; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_a2f1461231 FOREIGN KEY (user_type_id) REFERENCES public.user_types(id);


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
-- Name: workspaces workspaces_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id);


--
-- Name: memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: people; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.people ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.memberships USING (((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid) OR (user_id = (NULLIF(current_setting('app.current_user_id'::text, true), ''::text))::uuid))) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


--
-- Name: people tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.people USING ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.current_workspace_id'::text, true), ''::text))::uuid));


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

