-- STMNA Signal Pipeline — Database Schema
-- =========================================
-- PostgreSQL 15+  |  Database: stmna_signal
--
-- Setup:
--   createdb -U postgres stmna_signal
--   createuser -U postgres voice
--   psql -U postgres -d stmna_signal -f schema.sql
--
-- Tables:
--   pipeline_users    — registered senders (Signal, NextCloud, webhook)
--   pipeline_queue    — work queue: one row per content request
--   content_cache     — dedup cache: keyed by content URL/ID
--   content_variants  — per-content variants (summary, translation, etc.)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';
SET default_table_access_method = heap;

-- ---------------------------------------------------------------------------
-- pipeline_users
-- Registered senders. The pipeline resolves incoming Signal UUIDs or
-- NextCloud usernames to a user row to enforce access control.
-- ---------------------------------------------------------------------------

CREATE TABLE public.pipeline_users (
    id              integer NOT NULL,
    name            text NOT NULL,
    role            text DEFAULT 'user'::text NOT NULL,
    signal_uuid     text,           -- Signal UUID (nullable: not all users use Signal)
    email           text,
    nextcloud_user  text,           -- NextCloud username (nullable)
    created_at      timestamp without time zone DEFAULT now(),
    CONSTRAINT pipeline_users_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'user'::text])))
);

CREATE SEQUENCE public.pipeline_users_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE public.pipeline_users_id_seq OWNED BY public.pipeline_users.id;
ALTER TABLE ONLY public.pipeline_users ALTER COLUMN id SET DEFAULT nextval('public.pipeline_users_id_seq'::regclass);

ALTER TABLE ONLY public.pipeline_users
    ADD CONSTRAINT pipeline_users_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.pipeline_users
    ADD CONSTRAINT pipeline_users_signal_uuid_key UNIQUE (signal_uuid);
ALTER TABLE ONLY public.pipeline_users
    ADD CONSTRAINT pipeline_users_email_key UNIQUE (email);
ALTER TABLE ONLY public.pipeline_users
    ADD CONSTRAINT pipeline_users_nextcloud_user_key UNIQUE (nextcloud_user);


-- ---------------------------------------------------------------------------
-- pipeline_queue
-- One row per content request. Status lifecycle:
--   pending → processing → done | failed
-- Deferred delivery: scheduled_after + response_sent track send-later flow.
-- ---------------------------------------------------------------------------

CREATE TABLE public.pipeline_queue (
    id               integer NOT NULL,
    status           text DEFAULT 'pending'::text NOT NULL,
    url              text NOT NULL,
    content_type     text,                           -- 'youtube', 'web', 'translate-book', etc.
    flags            jsonb DEFAULT '{}'::jsonb,      -- arbitrary per-job options
    sender           integer,                        -- FK → pipeline_users.id
    source_channel   text DEFAULT 'signal'::text NOT NULL,  -- 'signal', 'nextcloud', 'webhook'
    message_text     text,                           -- raw incoming message (may contain JSON params)
    priority         text DEFAULT 'immediate'::text NOT NULL,
    scheduled_after  timestamp without time zone,   -- for deferred delivery
    created_at       timestamp without time zone DEFAULT now(),
    started_at       timestamp without time zone,
    completed_at     timestamp without time zone,
    error            text,
    response_text    text,                           -- reply to send back to sender
    response_sent    boolean DEFAULT false,
    CONSTRAINT pipeline_queue_status_check   CHECK ((status   = ANY (ARRAY['pending'::text, 'processing'::text, 'done'::text, 'failed'::text]))),
    CONSTRAINT pipeline_queue_priority_check CHECK ((priority = ANY (ARRAY['immediate'::text, 'scheduled'::text])))
);

CREATE SEQUENCE public.pipeline_queue_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE public.pipeline_queue_id_seq OWNED BY public.pipeline_queue.id;
ALTER TABLE ONLY public.pipeline_queue ALTER COLUMN id SET DEFAULT nextval('public.pipeline_queue_id_seq'::regclass);

ALTER TABLE ONLY public.pipeline_queue
    ADD CONSTRAINT pipeline_queue_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.pipeline_queue
    ADD CONSTRAINT pipeline_queue_sender_fkey FOREIGN KEY (sender) REFERENCES public.pipeline_users(id);

-- Fast lookup for the worker polling for pending jobs
CREATE INDEX idx_queue_pending ON public.pipeline_queue USING btree (created_at)
    WHERE (status = 'pending'::text);


-- ---------------------------------------------------------------------------
-- content_cache
-- Dedup cache keyed by content_key (format: "<type>:<host><path>").
-- Prevents reprocessing the same URL within the TTL window.
-- Cleanup workflow purges rows past expires_at daily.
-- ---------------------------------------------------------------------------

CREATE TABLE public.content_cache (
    id               integer NOT NULL,
    content_key      text NOT NULL,                  -- e.g. "youtube:dQw4w9WgXcQ", "web:example.com/article"
    content_type     text,
    title            text,
    source_url       text,
    transcript_path  text,                           -- path to raw whisper transcript (optional)
    vault_path       text,                           -- path in Obsidian vault where note was written
    processed_at     timestamp without time zone DEFAULT now(),
    processed_by     integer,                        -- FK → pipeline_users.id
    expires_at       timestamp without time zone     -- NULL = never expires
);

CREATE SEQUENCE public.content_cache_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE public.content_cache_id_seq OWNED BY public.content_cache.id;
ALTER TABLE ONLY public.content_cache ALTER COLUMN id SET DEFAULT nextval('public.content_cache_id_seq'::regclass);

ALTER TABLE ONLY public.content_cache
    ADD CONSTRAINT content_cache_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.content_cache
    ADD CONSTRAINT content_cache_content_key_key UNIQUE (content_key);
ALTER TABLE ONLY public.content_cache
    ADD CONSTRAINT content_cache_processed_by_fkey FOREIGN KEY (processed_by) REFERENCES public.pipeline_users(id);

CREATE INDEX idx_cache_key     ON public.content_cache USING btree (content_key);
CREATE INDEX idx_cache_expires ON public.content_cache USING btree (expires_at)
    WHERE (expires_at IS NOT NULL);


-- ---------------------------------------------------------------------------
-- content_variants
-- Optional per-content variants stored alongside the main cache entry.
-- Used for storing alternate outputs: translations, shorter summaries, etc.
-- Keyed by (content_key, variant_type) — composite unique.
-- ---------------------------------------------------------------------------

CREATE TABLE public.content_variants (
    id           integer NOT NULL,
    content_key  text NOT NULL,                      -- FK → content_cache.content_key
    variant_type text NOT NULL,                      -- e.g. 'translation-fr', 'summary-short'
    result       text,
    model_used   text,
    created_at   timestamp without time zone DEFAULT now(),
    expires_at   timestamp without time zone
);

CREATE SEQUENCE public.content_variants_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE public.content_variants_id_seq OWNED BY public.content_variants.id;
ALTER TABLE ONLY public.content_variants ALTER COLUMN id SET DEFAULT nextval('public.content_variants_id_seq'::regclass);

ALTER TABLE ONLY public.content_variants
    ADD CONSTRAINT content_variants_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.content_variants
    ADD CONSTRAINT content_variants_content_key_variant_type_key UNIQUE (content_key, variant_type);
ALTER TABLE ONLY public.content_variants
    ADD CONSTRAINT content_variants_content_key_fkey FOREIGN KEY (content_key)
        REFERENCES public.content_cache(content_key) ON DELETE CASCADE;

CREATE INDEX idx_variants_expires ON public.content_variants USING btree (expires_at)
    WHERE (expires_at IS NOT NULL);


-- ---------------------------------------------------------------------------
-- Grants (adjust to match your PostgreSQL user)
-- ---------------------------------------------------------------------------

GRANT ALL ON ALL TABLES    IN SCHEMA public TO voice;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO voice;
