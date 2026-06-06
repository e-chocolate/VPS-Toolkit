--
-- PostgreSQL database dump
--

\restrict Mu5YOypS0SqEw5273FQ9rmihvsg4fj1BG8MAY4qi4ExPnFBl6V3Bm4vD5lm5E7a

-- Dumped from database version 18.3 (Ubuntu 18.3-1.pgdg24.04+1)
-- Dumped by pg_dump version 18.3 (Ubuntu 18.3-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ssha512(text, text); Type: FUNCTION; Schema: public; Owner: mailsys
--

CREATE FUNCTION public.ssha512(text, text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT 
  encode(decode(
  concat(
    encode(sha512(CONCAT($1, encode(decode($2, 'hex'), 'escape'))::bytea), 'hex') ,
    $2
  ), 'hex'),'base64')
$_$;


ALTER FUNCTION public.ssha512(text, text) OWNER TO mailsys;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: virtual_aliases; Type: TABLE; Schema: public; Owner: mailsys
--

CREATE TABLE public.virtual_aliases (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    source character varying(100) NOT NULL,
    destination character varying(100) NOT NULL
);


ALTER TABLE public.virtual_aliases OWNER TO mailsys;

--
-- Name: virtual_aliases_id_seq; Type: SEQUENCE; Schema: public; Owner: mailsys
--

CREATE SEQUENCE public.virtual_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.virtual_aliases_id_seq OWNER TO mailsys;

--
-- Name: virtual_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mailsys
--

ALTER SEQUENCE public.virtual_aliases_id_seq OWNED BY public.virtual_aliases.id;


--
-- Name: virtual_domains; Type: TABLE; Schema: public; Owner: mailsys
--

CREATE TABLE public.virtual_domains (
    id bigint NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE public.virtual_domains OWNER TO mailsys;

--
-- Name: virtual_domains_id_seq; Type: SEQUENCE; Schema: public; Owner: mailsys
--

CREATE SEQUENCE public.virtual_domains_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.virtual_domains_id_seq OWNER TO mailsys;

--
-- Name: virtual_domains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mailsys
--

ALTER SEQUENCE public.virtual_domains_id_seq OWNED BY public.virtual_domains.id;


--
-- Name: virtual_users; Type: TABLE; Schema: public; Owner: mailsys
--

CREATE TABLE public.virtual_users (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    password character varying(100) NOT NULL,
    salt character varying(100) NOT NULL,
    email character varying(100) NOT NULL
);


ALTER TABLE public.virtual_users OWNER TO mailsys;

--
-- Name: virtual_users_id_seq; Type: SEQUENCE; Schema: public; Owner: mailsys
--

CREATE SEQUENCE public.virtual_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.virtual_users_id_seq OWNER TO mailsys;

--
-- Name: virtual_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mailsys
--

ALTER SEQUENCE public.virtual_users_id_seq OWNED BY public.virtual_users.id;


--
-- Name: virtual_aliases id; Type: DEFAULT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_aliases ALTER COLUMN id SET DEFAULT nextval('public.virtual_aliases_id_seq'::regclass);


--
-- Name: virtual_domains id; Type: DEFAULT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_domains ALTER COLUMN id SET DEFAULT nextval('public.virtual_domains_id_seq'::regclass);


--
-- Name: virtual_users id; Type: DEFAULT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_users ALTER COLUMN id SET DEFAULT nextval('public.virtual_users_id_seq'::regclass);


--
-- Name: virtual_aliases idx_16392_PRIMARY; Type: CONSTRAINT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_aliases
    ADD CONSTRAINT "idx_16392_PRIMARY" PRIMARY KEY (id);


--
-- Name: virtual_domains idx_16401_PRIMARY; Type: CONSTRAINT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_domains
    ADD CONSTRAINT "idx_16401_PRIMARY" PRIMARY KEY (id);


--
-- Name: virtual_users idx_16408_PRIMARY; Type: CONSTRAINT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_users
    ADD CONSTRAINT "idx_16408_PRIMARY" PRIMARY KEY (id);


--
-- Name: idx_16392_domain_id; Type: INDEX; Schema: public; Owner: mailsys
--

CREATE INDEX idx_16392_domain_id ON public.virtual_aliases USING btree (domain_id);


--
-- Name: idx_16408_domain_id; Type: INDEX; Schema: public; Owner: mailsys
--

CREATE INDEX idx_16408_domain_id ON public.virtual_users USING btree (domain_id);


--
-- Name: idx_16408_email; Type: INDEX; Schema: public; Owner: mailsys
--

CREATE UNIQUE INDEX idx_16408_email ON public.virtual_users USING btree (email);


--
-- Name: virtual_aliases virtual_aliases_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_aliases
    ADD CONSTRAINT virtual_aliases_ibfk_1 FOREIGN KEY (domain_id) REFERENCES public.virtual_domains(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: virtual_users virtual_users_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: mailsys
--

ALTER TABLE ONLY public.virtual_users
    ADD CONSTRAINT virtual_users_ibfk_1 FOREIGN KEY (domain_id) REFERENCES public.virtual_domains(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO mailsys;


--
-- PostgreSQL database dump complete
--

\unrestrict Mu5YOypS0SqEw5273FQ9rmihvsg4fj1BG8MAY4qi4ExPnFBl6V3Bm4vD5lm5E7a

