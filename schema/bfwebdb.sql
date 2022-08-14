--
-- PostgreSQL database dump
--

-- Dumped from database version 12.12 (Debian 12.12-1.pgdg100+1)
-- Dumped by pg_dump version 12.12 (Debian 12.12-1.pgdg100+1)

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
-- Name: build_status_log_parts; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA build_status_log_parts;


ALTER SCHEMA build_status_log_parts OWNER TO postgres;

--
-- Name: partman; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA partman;


ALTER SCHEMA partman OWNER TO postgres;

--
-- Name: plperl; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plperl WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plperl; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plperl IS 'PL/Perl procedural language';


--
-- Name: plperlu; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plperlu WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plperlu; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plperlu IS 'PL/PerlU untrusted procedural language';


--
-- Name: pageinspect; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pageinspect WITH SCHEMA public;


--
-- Name: EXTENSION pageinspect; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pageinspect IS 'inspect the contents of database pages at a low level';


--
-- Name: pg_freespacemap; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_freespacemap WITH SCHEMA public;


--
-- Name: EXTENSION pg_freespacemap; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_freespacemap IS 'examine the free space map (FSM)';


--
-- Name: pg_partman; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_partman WITH SCHEMA partman;


--
-- Name: EXTENSION pg_partman; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_partman IS 'Extension to manage partitioned tables by time or ID';


--
-- Name: postgres_fdw; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA public;


--
-- Name: EXTENSION postgres_fdw; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgres_fdw IS 'foreign-data wrapper for remote PostgreSQL servers';


--
-- Name: pending; Type: TYPE; Schema: public; Owner: pgbuildfarm
--

CREATE TYPE public.pending AS (
	name text,
	operating_system text,
	os_version text,
	compiler text,
	compiler_version text,
	architecture text,
	owner_email text,
	owner text,
	status_ts timestamp without time zone
);


ALTER TYPE public.pending OWNER TO pgbuildfarm;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: build_status_raw; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.build_status_raw (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    status integer,
    stage text,
    log bytea,
    conf_sum text,
    branch text,
    changed_this_run text,
    changed_since_success text,
    log_archive bytea,
    log_archive_filenames text[],
    build_flags text[],
    report_time timestamp with time zone DEFAULT ('now'::text)::timestamp(6) with time zone,
    scm text,
    scmurl text,
    frozen_conf bytea,
    git_head_ref text,
    run_secs integer
);


ALTER TABLE public.build_status_raw OWNER TO pgbuildfarm;

--
-- Name: build_status; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.build_status AS
 SELECT build_status_raw.sysname,
    build_status_raw.snapshot,
    build_status_raw.status,
    build_status_raw.stage,
    encode(build_status_raw.log, 'escape'::text) AS log,
    build_status_raw.conf_sum,
    build_status_raw.branch,
    build_status_raw.changed_this_run,
    build_status_raw.changed_since_success,
    build_status_raw.log_archive,
    build_status_raw.log_archive_filenames,
    build_status_raw.build_flags,
    build_status_raw.report_time,
    build_status_raw.scm,
    build_status_raw.scmurl,
    build_status_raw.frozen_conf,
    build_status_raw.git_head_ref,
    build_status_raw.run_secs
   FROM public.build_status_raw;


ALTER TABLE public.build_status OWNER TO pgbuildfarm;

--
-- Name: buildsystems; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.buildsystems (
    name text NOT NULL,
    secret text NOT NULL,
    operating_system text NOT NULL,
    os_version text NOT NULL,
    compiler text NOT NULL,
    compiler_version text NOT NULL,
    architecture text NOT NULL,
    status text NOT NULL,
    sys_owner text NOT NULL,
    owner_email text NOT NULL,
    status_ts timestamp without time zone DEFAULT (('now'::text)::timestamp(6) with time zone)::timestamp without time zone,
    no_alerts boolean DEFAULT false,
    sys_notes text,
    sys_notes_ts timestamp with time zone
);


ALTER TABLE public.buildsystems OWNER TO pgbuildfarm;

--
-- Name: personality; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.personality (
    name text NOT NULL,
    os_version text NOT NULL,
    compiler_version text NOT NULL,
    effective_date timestamp with time zone DEFAULT ('now'::text)::timestamp(6) with time zone NOT NULL
);


ALTER TABLE public.personality OWNER TO pgbuildfarm;

--
-- Name: allhist_summary; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.allhist_summary AS
 SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text)
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    COALESCE(b.os_version, s.os_version) AS os_version,
    s.compiler,
    COALESCE(b.compiler_version, s.compiler_version) AS compiler_version,
    s.architecture,
    s.sys_notes_ts,
    s.sys_notes
   FROM public.buildsystems s,
    ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            p.compiler_version,
            p.os_version
           FROM (public.build_status bs
             LEFT JOIN public.personality p ON (((p.name = bs.sysname) AND (p.effective_date <= bs.report_time))))
          ORDER BY bs.sysname, bs.branch, bs.report_time, (p.effective_date IS NULL), p.effective_date DESC) b
  WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE public.allhist_summary OWNER TO pgbuildfarm;

--
-- Name: allhist_summary(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.allhist_summary(ts timestamp without time zone) RETURNS SETOF public.allhist_summary
    LANGUAGE sql
    AS $_$

 SELECT b.sysname, b.snapshot, b.status, b.stage, b.branch, 
        CASE
            WHEN b.conf_sum ~ 'use_vpath'::text AND b.conf_sum !~ '''use_vpath'' => undef'::text THEN b.build_flags || 'vpath'::text
            ELSE b.build_flags
        END AS build_flags, s.operating_system, COALESCE(b.os_version, s.os_version) AS os_version, s.compiler, COALESCE(b.compiler_version, s.compiler_version) AS compiler_version, s.architecture, s.sys_notes_ts, s.sys_notes
   FROM buildsystems s, ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname, bs.snapshot, bs.status, bs.stage, bs.branch, bs.build_flags, bs.conf_sum, bs.report_time, p.compiler_version, p.os_version
           FROM build_status bs
      LEFT JOIN personality p ON p.name = bs.sysname AND p.effective_date <= bs.report_time
      WHERE bs.snapshot > $1
     ORDER BY bs.sysname, bs.branch, bs.report_time, p.effective_date IS NULL, p.effective_date DESC) b
  WHERE s.name = b.sysname AND s.status = 'approved'::text


$_$;


ALTER FUNCTION public.allhist_summary(ts timestamp without time zone) OWNER TO pgbuildfarm;

--
-- Name: approve(text, text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.approve(text, text) RETURNS text
    LANGUAGE sql
    AS $_$ update buildsystems set name = $2, status = 'approved' where name = $1 and status = 'pending'; select owner_email || ':' || name || ':' || secret from buildsystems where name = $2;$_$;


ALTER FUNCTION public.approve(text, text) OWNER TO pgbuildfarm;

--
-- Name: clock_skew(bytea); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.clock_skew(bytea) RETURNS integer
    LANGUAGE plperlu
    AS $_X$

      use Storable qw(thaw);
      my $sconf = thaw(decode_bytea($_[0]));
      return $sconf->{clock_skew};

$_X$;


ALTER FUNCTION public.clock_skew(bytea) OWNER TO postgres;

--
-- Name: pending(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.pending() RETURNS SETOF public.pending
    LANGUAGE sql
    AS $$select name,operating_system,os_version,compiler,compiler_version,architecture,owner_email, sys_owner, status_ts from buildsystems where status = 'pending' order by status_ts $$;


ALTER FUNCTION public.pending() OWNER TO pgbuildfarm;

--
-- Name: purge_build_status_recent_500(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.purge_build_status_recent_500() RETURNS void
    LANGUAGE plpgsql
    AS $$ begin delete from build_status_recent_500 b using (with x as (select sysname, snapshot, rank() over (partition by sysname, branch order by snapshot desc) as rank from build_status_recent_500) select * from x where rank > 500) o where o.sysname = b.sysname and o.snapshot = b.snapshot; end; $$;


ALTER FUNCTION public.purge_build_status_recent_500() OWNER TO pgbuildfarm;

--
-- Name: refresh_dashboard(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.refresh_dashboard() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
lock table dashboard_mat in share row exclusive mode;
delete from dashboard_mat;
insert into dashboard_mat select * from dashboard_mat_data;
update dashboard_last_modified set ts = current_timestamp;
end;
$$;


ALTER FUNCTION public.refresh_dashboard() OWNER TO pgbuildfarm;

--
-- Name: refresh_recent_failures(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.refresh_recent_failures() RETURNS void
    LANGUAGE plpgsql
    AS $$                                                                                                                                                                                                      
                                                                                                                                                                                                                   
begin                                                                                                                                                                                                              
   lock table nrecent_failures in share row exclusive mode;                                                                                                                                                        
   delete from nrecent_failures;                                                                                                                                                                                   
   insert into nrecent_failures                                                                                                                                                                                    
         select bs.sysname, bs.snapshot, bs.branch                                                                                                                                                                 
         from build_status bs                                                                                                                                                                                      
         where bs.stage <> 'OK'                                                                                                                                                                                    
         and bs.snapshot > now() - interval '90 days';                                                                                                                                                             
end;                                                                                                                                                                                                               
                                                                                                                                                                                                                   
$$;


ALTER FUNCTION public.refresh_recent_failures() OWNER TO pgbuildfarm;

--
-- Name: script_version(text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.script_version(text) RETURNS text
    LANGUAGE plperl
    AS $_$

   my $log = shift;
   if ($log =~ /'script_version' => '(REL_)?(\d+)(\.(\d+))?[.']/)
   {
	return sprintf("%0.3d%0.3d",$2,$4);
   }
   return '-1';

$_$;


ALTER FUNCTION public.script_version(text) OWNER TO pgbuildfarm;

--
-- Name: set_build_status_recent_500(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.set_build_status_recent_500() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

begin 

    insert into build_status_recent_500
       (sysname, snapshot, status, stage, branch, script_version,
     git_head_ref, run_secs)
    values (new.sysname, new.snapshot, new.status, new.stage, new.branch,
            script_version(new.conf_sum), new.git_head_ref, new.run_secs);
    return new;
end;

$$;


ALTER FUNCTION public.set_build_status_recent_500() OWNER TO pgbuildfarm;

--
-- Name: set_latest(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.set_latest() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

	begin
		update latest_snapshot 
			set snapshot = 
	(case when snapshot > NEW.snapshot then snapshot else NEW.snapshot end)
			where sysname = NEW.sysname and
				branch = NEW.branch;
		if not found then
			insert into latest_snapshot
				values(NEW.sysname, NEW.branch, NEW.snapshot);
		end if;
		return NEW;
	end;
$$;


ALTER FUNCTION public.set_latest() OWNER TO pgbuildfarm;

--
-- Name: set_local_error_terse(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_local_error_terse() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    AS $$ set local log_error_verbosity = terse $$;


ALTER FUNCTION public.set_local_error_terse() OWNER TO postgres;

--
-- Name: web_script_version(text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION public.web_script_version(text) RETURNS text
    LANGUAGE plperl
    AS $_$

   my $log = shift;
   if ($log =~ /'web_script_version' => '(REL_)?(\d+)(\.(\d+))?[.']/)
   {
	return sprintf("%0.3d%0.3d",$2,$4);
   }
   return '-1';

$_$;


ALTER FUNCTION public.web_script_version(text) OWNER TO pgbuildfarm;

--
-- Name: build_status_log_raw; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.build_status_log_raw (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
)
PARTITION BY LIST (((log_text IS NULL)));


ALTER TABLE public.build_status_log_raw OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
)
PARTITION BY RANGE (snapshot);
ALTER TABLE ONLY public.build_status_log_raw ATTACH PARTITION build_status_log_parts.build_status_log_notnull FOR VALUES IN (false);


ALTER TABLE build_status_log_parts.build_status_log_notnull OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_default; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_default (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_default DEFAULT;


ALTER TABLE build_status_log_parts.build_status_log_notnull_default OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w02; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w02 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w02 FOR VALUES FROM ('2022-01-10 00:00:00') TO ('2022-01-17 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w02 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w03; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w03 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w03 FOR VALUES FROM ('2022-01-17 00:00:00') TO ('2022-01-24 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w03 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w04; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w04 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w04 FOR VALUES FROM ('2022-01-24 00:00:00') TO ('2022-01-31 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w04 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w05; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w05 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w05 FOR VALUES FROM ('2022-01-31 00:00:00') TO ('2022-02-07 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w05 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w06; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w06 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w06 FOR VALUES FROM ('2022-02-07 00:00:00') TO ('2022-02-14 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w06 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w07; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w07 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w07 FOR VALUES FROM ('2022-02-14 00:00:00') TO ('2022-02-21 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w07 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w08; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w08 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w08 FOR VALUES FROM ('2022-02-21 00:00:00') TO ('2022-02-28 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w08 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w09; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w09 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w09 FOR VALUES FROM ('2022-02-28 00:00:00') TO ('2022-03-07 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w09 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w10; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w10 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w10 FOR VALUES FROM ('2022-03-07 00:00:00') TO ('2022-03-14 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w10 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w11; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w11 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w11 FOR VALUES FROM ('2022-03-14 00:00:00') TO ('2022-03-21 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w11 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w12; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w12 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w12 FOR VALUES FROM ('2022-03-21 00:00:00') TO ('2022-03-28 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w12 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w13; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w13 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w13 FOR VALUES FROM ('2022-03-28 00:00:00') TO ('2022-04-04 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w13 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w14; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w14 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w14 FOR VALUES FROM ('2022-04-04 00:00:00') TO ('2022-04-11 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w14 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w15; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w15 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w15 FOR VALUES FROM ('2022-04-11 00:00:00') TO ('2022-04-18 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w15 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w16; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w16 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w16 FOR VALUES FROM ('2022-04-18 00:00:00') TO ('2022-04-25 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w16 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w17; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w17 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w17 FOR VALUES FROM ('2022-04-25 00:00:00') TO ('2022-05-02 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w17 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w18; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w18 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w18 FOR VALUES FROM ('2022-05-02 00:00:00') TO ('2022-05-09 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w18 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w19; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w19 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w19 FOR VALUES FROM ('2022-05-09 00:00:00') TO ('2022-05-16 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w19 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w20; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w20 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w20 FOR VALUES FROM ('2022-05-16 00:00:00') TO ('2022-05-23 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w20 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w21; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w21 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w21 FOR VALUES FROM ('2022-05-23 00:00:00') TO ('2022-05-30 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w21 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w22; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w22 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w22 FOR VALUES FROM ('2022-05-30 00:00:00') TO ('2022-06-06 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w22 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w23; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w23 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w23 FOR VALUES FROM ('2022-06-06 00:00:00') TO ('2022-06-13 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w23 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w24; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w24 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w24 FOR VALUES FROM ('2022-06-13 00:00:00') TO ('2022-06-20 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w24 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w25; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w25 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w25 FOR VALUES FROM ('2022-06-20 00:00:00') TO ('2022-06-27 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w25 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w26; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w26 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w26 FOR VALUES FROM ('2022-06-27 00:00:00') TO ('2022-07-04 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w26 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w27; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w27 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w27 FOR VALUES FROM ('2022-07-04 00:00:00') TO ('2022-07-11 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w27 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w28; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w28 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w28 FOR VALUES FROM ('2022-07-11 00:00:00') TO ('2022-07-18 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w28 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w29; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w29 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w29 FOR VALUES FROM ('2022-07-18 00:00:00') TO ('2022-07-25 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w29 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w30; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w30 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w30 FOR VALUES FROM ('2022-07-25 00:00:00') TO ('2022-08-01 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w30 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w31; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w31 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w31 FOR VALUES FROM ('2022-08-01 00:00:00') TO ('2022-08-08 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w31 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w32; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w32 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w32 FOR VALUES FROM ('2022-08-08 00:00:00') TO ('2022-08-15 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w32 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w33; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w33 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w33 FOR VALUES FROM ('2022-08-15 00:00:00') TO ('2022-08-22 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w33 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w34; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w34 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w34 FOR VALUES FROM ('2022-08-22 00:00:00') TO ('2022-08-29 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w34 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w35; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w35 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w35 FOR VALUES FROM ('2022-08-29 00:00:00') TO ('2022-09-05 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w35 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w36; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w36 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w36 FOR VALUES FROM ('2022-09-05 00:00:00') TO ('2022-09-12 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w36 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w37; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w37 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w37 FOR VALUES FROM ('2022-09-12 00:00:00') TO ('2022-09-19 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w37 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull_p2022w38; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_notnull_p2022w38 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w38 FOR VALUES FROM ('2022-09-19 00:00:00') TO ('2022-09-26 00:00:00');


ALTER TABLE build_status_log_parts.build_status_log_notnull_p2022w38 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_null; Type: TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE TABLE build_status_log_parts.build_status_log_null (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);
ALTER TABLE ONLY public.build_status_log_raw ATTACH PARTITION build_status_log_parts.build_status_log_null FOR VALUES IN (true);


ALTER TABLE build_status_log_parts.build_status_log_null OWNER TO pgbuildfarm;

--
-- Name: template_build_status_log_parts_build_status_log_notnull; Type: TABLE; Schema: partman; Owner: pgbuildfarm
--

CREATE TABLE partman.template_build_status_log_parts_build_status_log_notnull (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text bytea,
    stage_duration interval
);


ALTER TABLE partman.template_build_status_log_parts_build_status_log_notnull OWNER TO pgbuildfarm;

--
-- Name: alerts; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.alerts (
    sysname text NOT NULL,
    branch text NOT NULL,
    first_alert timestamp without time zone,
    last_notification timestamp without time zone
);


ALTER TABLE public.alerts OWNER TO pgbuildfarm;

--
-- Name: build_status_export; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.build_status_export AS
 SELECT build_status.sysname AS name,
    build_status.snapshot,
    build_status.stage,
    build_status.branch,
    build_status.build_flags
   FROM public.build_status;


ALTER TABLE public.build_status_export OWNER TO pgbuildfarm;

--
-- Name: build_status_log; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.build_status_log AS
 SELECT build_status_log_raw.sysname,
    build_status_log_raw.snapshot,
    build_status_log_raw.branch,
    build_status_log_raw.log_stage,
    encode(build_status_log_raw.log_text, 'escape'::text) AS log_text,
    build_status_log_raw.stage_duration
   FROM public.build_status_log_raw;


ALTER TABLE public.build_status_log OWNER TO pgbuildfarm;

--
-- Name: build_status_recent_500; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.build_status_recent_500 (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    status integer,
    stage text,
    branch text,
    report_time timestamp with time zone DEFAULT ('now'::text)::timestamp(6) with time zone,
    script_version text,
    git_head_ref text,
    run_secs integer
);


ALTER TABLE public.build_status_recent_500 OWNER TO pgbuildfarm;

--
-- Name: buildsystems_export; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.buildsystems_export AS
 SELECT buildsystems.name,
    buildsystems.operating_system,
    buildsystems.os_version,
    buildsystems.compiler,
    buildsystems.compiler_version,
    buildsystems.architecture
   FROM public.buildsystems
  WHERE (buildsystems.status = 'approved'::text);


ALTER TABLE public.buildsystems_export OWNER TO pgbuildfarm;

--
-- Name: dashboard_last_modified; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.dashboard_last_modified (
    ts timestamp(0) with time zone,
    unq boolean DEFAULT true NOT NULL,
    CONSTRAINT unq CHECK ((unq = true))
);


ALTER TABLE public.dashboard_last_modified OWNER TO pgbuildfarm;

--
-- Name: dashboard_mat; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.dashboard_mat (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    status integer,
    stage text,
    branch text NOT NULL,
    build_flags text[],
    operating_system text,
    os_version text,
    compiler text,
    compiler_version text,
    architecture text,
    sys_notes_ts timestamp with time zone,
    sys_notes text,
    git_head_ref text
);


ALTER TABLE public.dashboard_mat OWNER TO pgbuildfarm;

--
-- Name: latest_snapshot; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.latest_snapshot (
    sysname text NOT NULL,
    branch text NOT NULL,
    snapshot timestamp without time zone NOT NULL
);


ALTER TABLE public.latest_snapshot OWNER TO pgbuildfarm;

--
-- Name: dashboard_mat_data; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.dashboard_mat_data AS
 SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text)
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    COALESCE(b.os_version, s.os_version) AS os_version,
    s.compiler,
    COALESCE(b.compiler_version, s.compiler_version) AS compiler_version,
    s.architecture,
    s.sys_notes_ts,
    s.sys_notes,
    b.git_head_ref
   FROM public.buildsystems s,
    ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            bs.git_head_ref,
            p.compiler_version,
            p.os_version
           FROM ((public.build_status bs
             JOIN public.latest_snapshot m USING (sysname, snapshot, branch))
             LEFT JOIN public.personality p ON (((p.name = bs.sysname) AND (p.effective_date <= bs.report_time))))
          WHERE (m.snapshot > (now() - '30 days'::interval))
          ORDER BY bs.sysname, bs.branch, bs.report_time, (p.effective_date IS NULL), p.effective_date DESC) b
  WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE public.dashboard_mat_data OWNER TO pgbuildfarm;

--
-- Name: failures; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.failures AS
 SELECT build_status.sysname,
    build_status.snapshot,
    build_status.stage,
    build_status.conf_sum,
    build_status.branch,
    build_status.changed_this_run,
    build_status.changed_since_success,
    build_status.log_archive_filenames,
    build_status.build_flags,
    build_status.report_time
   FROM public.build_status
  WHERE ((build_status.stage <> 'OK'::text) AND (build_status.stage !~~ 'CVS%'::text) AND (build_status.report_time IS NOT NULL));


ALTER TABLE public.failures OWNER TO pgbuildfarm;

--
-- Name: nrecent_failures; Type: TABLE; Schema: public; Owner: pgbuildfarm
--

CREATE TABLE public.nrecent_failures (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text
);


ALTER TABLE public.nrecent_failures OWNER TO pgbuildfarm;

--
-- Name: long_term_fails; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.long_term_fails AS
 WITH max_fail AS (
         SELECT nrecent_failures.sysname,
            nrecent_failures.branch,
            max(nrecent_failures.snapshot) AS snapshot
           FROM public.nrecent_failures
          WHERE (nrecent_failures.snapshot > (now() - '7 days'::interval))
          GROUP BY nrecent_failures.sysname, nrecent_failures.branch
        ), still_failing AS (
         SELECT m.sysname,
            m.branch,
            m.snapshot
           FROM max_fail m
          WHERE (NOT (EXISTS ( SELECT 1
                   FROM public.dashboard_mat d
                  WHERE ((d.sysname = m.sysname) AND (d.branch = m.branch) AND (d.stage = 'OK'::text)))))
        ), last_success AS (
         SELECT r.sysname,
            r.branch,
            max(r.snapshot) AS last_success
           FROM public.build_status_recent_500 r
          WHERE ((EXISTS ( SELECT 1
                   FROM still_failing s
                  WHERE ((r.sysname = s.sysname) AND (r.branch = s.branch)))) AND (r.stage = 'OK'::text))
          GROUP BY r.sysname, r.branch
        )
 SELECT bs.sys_owner,
    bs.owner_email,
    sf.sysname,
    sf.branch,
    sf.snapshot,
    age(l.last_success) AS age_since_last_success
   FROM ((still_failing sf
     JOIN public.buildsystems bs ON ((bs.name = sf.sysname)))
     LEFT JOIN last_success l ON (((l.sysname = sf.sysname) AND (l.branch = sf.branch))))
  WHERE ((l.last_success IS NULL) OR (l.last_success < (now() - '14 days'::interval)))
  ORDER BY sf.sysname, sf.branch;


ALTER TABLE public.long_term_fails OWNER TO pgbuildfarm;

--
-- Name: nrecent_failures_db_data; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.nrecent_failures_db_data AS
 SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text)
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    COALESCE(b.os_version, s.os_version) AS os_version,
    s.compiler,
    COALESCE(b.compiler_version, s.compiler_version) AS compiler_version,
    s.architecture,
    s.sys_notes_ts,
    s.sys_notes,
    b.git_head_ref
   FROM public.buildsystems s,
    ( SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            bs.git_head_ref,
            p.compiler_version,
            p.os_version
           FROM ((public.build_status bs
             JOIN public.nrecent_failures m USING (sysname, snapshot, branch))
             LEFT JOIN public.personality p ON (((p.name = bs.sysname) AND (p.effective_date <= bs.report_time))))
          WHERE (m.snapshot > (now() - '90 days'::interval))
          ORDER BY bs.sysname, bs.branch, bs.report_time, (p.effective_date IS NULL), p.effective_date DESC) b
  WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE public.nrecent_failures_db_data OWNER TO pgbuildfarm;

--
-- Name: nrecent_failures_db_data2; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.nrecent_failures_db_data2 AS
 SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text)
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    COALESCE(b.os_version, s.os_version) AS os_version,
    s.compiler,
    COALESCE(b.compiler_version, s.compiler_version) AS compiler_version,
    s.architecture,
    s.sys_notes_ts,
    s.sys_notes,
    b.git_head_ref
   FROM public.buildsystems s,
    ( SELECT bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            bs.git_head_ref,
            NULL::text AS compiler_version,
            NULL::text AS os_version
           FROM (public.build_status bs
             JOIN public.nrecent_failures m USING (sysname, snapshot, branch))
          WHERE (m.snapshot > (now() - '90 days'::interval))
          ORDER BY bs.sysname, bs.branch, bs.report_time) b
  WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE public.nrecent_failures_db_data2 OWNER TO pgbuildfarm;

--
-- Name: recent_failures; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.recent_failures AS
 SELECT build_status.sysname,
    build_status.snapshot,
    build_status.stage,
    build_status.conf_sum,
    build_status.branch,
    build_status.changed_this_run,
    build_status.changed_since_success,
    build_status.log_archive_filenames,
    build_status.build_flags,
    build_status.report_time,
    build_status.log
   FROM public.build_status
  WHERE ((build_status.stage <> 'OK'::text) AND (build_status.stage !~~ 'CVS%'::text) AND (build_status.report_time IS NOT NULL) AND ((build_status.snapshot + '3 mons'::interval) > ('now'::text)::timestamp(6) with time zone));


ALTER TABLE public.recent_failures OWNER TO pgbuildfarm;

--
-- Name: script_versions; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.script_versions AS
 SELECT b.sysname,
    b.snapshot,
    b.branch,
    (public.script_version(b.conf_sum))::numeric AS script_version,
    (public.web_script_version(b.conf_sum))::numeric AS web_script_version
   FROM (public.build_status b
     JOIN public.dashboard_mat d ON (((b.sysname = d.sysname) AND (b.snapshot = d.snapshot))));


ALTER TABLE public.script_versions OWNER TO pgbuildfarm;

--
-- Name: script_versions2; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW public.script_versions2 AS
 SELECT b.sysname,
    b.snapshot,
    b.branch,
    public.script_version(b.conf_sum) AS script_version,
    public.web_script_version(b.conf_sum) AS web_script_version
   FROM (public.build_status b
     JOIN public.dashboard_mat d ON (((b.sysname = d.sysname) AND (b.snapshot = d.snapshot))));


ALTER TABLE public.script_versions2 OWNER TO pgbuildfarm;

--
-- Name: build_status_log_notnull build_status_log_notnull_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull
    ADD CONSTRAINT build_status_log_notnull_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_default build_status_log_notnull_default_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_default
    ADD CONSTRAINT build_status_log_notnull_default_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w02 build_status_log_notnull_p2022w02_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w02
    ADD CONSTRAINT build_status_log_notnull_p2022w02_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w03 build_status_log_notnull_p2022w03_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w03
    ADD CONSTRAINT build_status_log_notnull_p2022w03_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w04 build_status_log_notnull_p2022w04_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w04
    ADD CONSTRAINT build_status_log_notnull_p2022w04_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w05 build_status_log_notnull_p2022w05_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w05
    ADD CONSTRAINT build_status_log_notnull_p2022w05_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w06 build_status_log_notnull_p2022w06_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w06
    ADD CONSTRAINT build_status_log_notnull_p2022w06_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w07 build_status_log_notnull_p2022w07_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w07
    ADD CONSTRAINT build_status_log_notnull_p2022w07_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w08 build_status_log_notnull_p2022w08_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w08
    ADD CONSTRAINT build_status_log_notnull_p2022w08_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w09 build_status_log_notnull_p2022w09_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w09
    ADD CONSTRAINT build_status_log_notnull_p2022w09_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w10 build_status_log_notnull_p2022w10_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w10
    ADD CONSTRAINT build_status_log_notnull_p2022w10_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w11 build_status_log_notnull_p2022w11_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w11
    ADD CONSTRAINT build_status_log_notnull_p2022w11_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w12 build_status_log_notnull_p2022w12_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w12
    ADD CONSTRAINT build_status_log_notnull_p2022w12_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w13 build_status_log_notnull_p2022w13_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w13
    ADD CONSTRAINT build_status_log_notnull_p2022w13_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w14 build_status_log_notnull_p2022w14_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w14
    ADD CONSTRAINT build_status_log_notnull_p2022w14_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w15 build_status_log_notnull_p2022w15_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w15
    ADD CONSTRAINT build_status_log_notnull_p2022w15_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w16 build_status_log_notnull_p2022w16_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w16
    ADD CONSTRAINT build_status_log_notnull_p2022w16_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w17 build_status_log_notnull_p2022w17_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w17
    ADD CONSTRAINT build_status_log_notnull_p2022w17_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w18 build_status_log_notnull_p2022w18_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w18
    ADD CONSTRAINT build_status_log_notnull_p2022w18_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w19 build_status_log_notnull_p2022w19_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w19
    ADD CONSTRAINT build_status_log_notnull_p2022w19_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w20 build_status_log_notnull_p2022w20_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w20
    ADD CONSTRAINT build_status_log_notnull_p2022w20_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w21 build_status_log_notnull_p2022w21_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w21
    ADD CONSTRAINT build_status_log_notnull_p2022w21_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w22 build_status_log_notnull_p2022w22_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w22
    ADD CONSTRAINT build_status_log_notnull_p2022w22_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w23 build_status_log_notnull_p2022w23_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w23
    ADD CONSTRAINT build_status_log_notnull_p2022w23_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w24 build_status_log_notnull_p2022w24_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w24
    ADD CONSTRAINT build_status_log_notnull_p2022w24_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w25 build_status_log_notnull_p2022w25_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w25
    ADD CONSTRAINT build_status_log_notnull_p2022w25_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w26 build_status_log_notnull_p2022w26_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w26
    ADD CONSTRAINT build_status_log_notnull_p2022w26_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w27 build_status_log_notnull_p2022w27_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w27
    ADD CONSTRAINT build_status_log_notnull_p2022w27_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w28 build_status_log_notnull_p2022w28_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w28
    ADD CONSTRAINT build_status_log_notnull_p2022w28_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w29 build_status_log_notnull_p2022w29_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w29
    ADD CONSTRAINT build_status_log_notnull_p2022w29_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w30 build_status_log_notnull_p2022w30_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w30
    ADD CONSTRAINT build_status_log_notnull_p2022w30_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w31 build_status_log_notnull_p2022w31_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w31
    ADD CONSTRAINT build_status_log_notnull_p2022w31_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w32 build_status_log_notnull_p2022w32_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w32
    ADD CONSTRAINT build_status_log_notnull_p2022w32_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w33 build_status_log_notnull_p2022w33_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w33
    ADD CONSTRAINT build_status_log_notnull_p2022w33_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w34 build_status_log_notnull_p2022w34_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w34
    ADD CONSTRAINT build_status_log_notnull_p2022w34_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w35 build_status_log_notnull_p2022w35_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w35
    ADD CONSTRAINT build_status_log_notnull_p2022w35_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w36 build_status_log_notnull_p2022w36_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w36
    ADD CONSTRAINT build_status_log_notnull_p2022w36_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w37 build_status_log_notnull_p2022w37_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w37
    ADD CONSTRAINT build_status_log_notnull_p2022w37_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_notnull_p2022w38 build_status_log_notnull_p2022w38_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w38
    ADD CONSTRAINT build_status_log_notnull_p2022w38_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_log_null build_status_log_null_pkey; Type: CONSTRAINT; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log_parts.build_status_log_null
    ADD CONSTRAINT build_status_log_null_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (sysname, branch);


--
-- Name: build_status_raw build_status_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.build_status_raw
    ADD CONSTRAINT build_status_pkey PRIMARY KEY (sysname, snapshot);


--
-- Name: build_status_recent_500 build_status_recent_500_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.build_status_recent_500
    ADD CONSTRAINT build_status_recent_500_pkey PRIMARY KEY (sysname, snapshot);


--
-- Name: buildsystems buildsystems_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.buildsystems
    ADD CONSTRAINT buildsystems_pkey PRIMARY KEY (name);


--
-- Name: dashboard_last_modified dashboard_last_modified_unq_key; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.dashboard_last_modified
    ADD CONSTRAINT dashboard_last_modified_unq_key UNIQUE (unq);


--
-- Name: dashboard_mat dashboard_mat_pk; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.dashboard_mat
    ADD CONSTRAINT dashboard_mat_pk PRIMARY KEY (branch, sysname, snapshot);

ALTER TABLE public.dashboard_mat CLUSTER ON dashboard_mat_pk;


--
-- Name: latest_snapshot latest_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.latest_snapshot
    ADD CONSTRAINT latest_snapshot_pkey PRIMARY KEY (sysname, branch);


--
-- Name: nrecent_failures nrecent_failures_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.nrecent_failures
    ADD CONSTRAINT nrecent_failures_pkey PRIMARY KEY (sysname, snapshot);


--
-- Name: personality personality_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.personality
    ADD CONSTRAINT personality_pkey PRIMARY KEY (name, effective_date);


--
-- Name: build_status_log_stage_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_stage_idx ON ONLY public.build_status_log_raw USING btree (log_stage);


--
-- Name: build_status_log_notnull_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_log_stage_idx ON ONLY build_status_log_parts.build_status_log_notnull USING btree (log_stage);


--
-- Name: build_status_log_notnull_default_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_default_log_stage_idx ON build_status_log_parts.build_status_log_notnull_default USING btree (log_stage);


--
-- Name: build_status_log_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_snapshot_idx ON ONLY public.build_status_log_raw USING btree (snapshot);


--
-- Name: build_status_log_notnull_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_snapshot_idx ON ONLY build_status_log_parts.build_status_log_notnull USING btree (snapshot);


--
-- Name: build_status_log_notnull_default_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_default_snapshot_idx ON build_status_log_parts.build_status_log_notnull_default USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w02_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w02_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w02 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w02_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w02_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w02 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w03_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w03_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w03 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w03_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w03_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w03 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w04_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w04_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w04 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w04_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w04_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w04 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w05_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w05_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w05 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w05_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w05_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w05 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w06_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w06_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w06 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w06_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w06_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w06 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w07_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w07_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w07 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w07_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w07_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w07 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w08_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w08_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w08 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w08_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w08_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w08 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w09_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w09_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w09 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w09_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w09_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w09 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w10_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w10_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w10 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w10_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w10_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w10 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w11_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w11_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w11 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w11_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w11_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w11 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w12_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w12_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w12 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w12_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w12_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w12 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w13_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w13_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w13 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w13_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w13_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w13 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w14_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w14_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w14 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w14_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w14_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w14 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w15_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w15_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w15 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w15_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w15_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w15 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w16_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w16_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w16 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w16_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w16_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w16 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w17_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w17_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w17 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w17_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w17_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w17 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w18_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w18_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w18 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w18_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w18_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w18 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w19_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w19_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w19 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w19_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w19_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w19 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w20_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w20_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w20 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w20_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w20_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w20 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w21_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w21_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w21 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w21_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w21_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w21 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w22_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w22_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w22 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w22_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w22_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w22 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w23_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w23_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w23 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w23_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w23_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w23 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w24_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w24_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w24 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w24_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w24_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w24 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w25_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w25_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w25 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w25_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w25_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w25 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w26_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w26_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w26 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w26_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w26_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w26 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w27_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w27_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w27 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w27_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w27_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w27 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w28_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w28_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w28 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w28_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w28_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w28 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w29_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w29_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w29 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w29_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w29_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w29 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w30_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w30_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w30 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w30_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w30_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w30 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w31_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w31_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w31 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w31_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w31_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w31 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w32_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w32_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w32 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w32_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w32_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w32 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w33_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w33_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w33 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w33_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w33_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w33 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w34_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w34_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w34 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w34_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w34_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w34 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w35_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w35_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w35 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w35_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w35_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w35 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w36_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w36_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w36 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w36_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w36_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w36 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w37_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w37_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w37 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w37_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w37_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w37 USING btree (snapshot);


--
-- Name: build_status_log_notnull_p2022w38_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w38_log_stage_idx ON build_status_log_parts.build_status_log_notnull_p2022w38 USING btree (log_stage);


--
-- Name: build_status_log_notnull_p2022w38_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_notnull_p2022w38_snapshot_idx ON build_status_log_parts.build_status_log_notnull_p2022w38 USING btree (snapshot);


--
-- Name: build_status_log_null_log_stage_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_null_log_stage_idx ON build_status_log_parts.build_status_log_null USING btree (log_stage);


--
-- Name: build_status_log_null_snapshot_idx; Type: INDEX; Schema: build_status_log_parts; Owner: pgbuildfarm
--

CREATE INDEX build_status_log_null_snapshot_idx ON build_status_log_parts.build_status_log_null USING btree (snapshot);


--
-- Name: bs_branch_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bs_branch_snapshot_idx ON public.build_status_raw USING btree (branch, snapshot);


--
-- Name: bs_status_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bs_status_idx ON public.buildsystems USING btree (status);


--
-- Name: bs_sysname_branch_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bs_sysname_branch_idx ON public.build_status_raw USING btree (sysname, branch);


--
-- Name: bs_sysname_branch_report_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bs_sysname_branch_report_idx ON public.build_status_raw USING btree (sysname, branch, report_time);


--
-- Name: bs_sysname_branch_snap_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bs_sysname_branch_snap_idx ON public.build_status_raw USING btree (sysname, branch, snapshot DESC);


--
-- Name: bsr500_branch_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bsr500_branch_snapshot_idx ON public.build_status_recent_500 USING btree (branch, snapshot);


--
-- Name: bsr500_sysname_branch_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bsr500_sysname_branch_idx ON public.build_status_recent_500 USING btree (sysname, branch);


--
-- Name: bsr500_sysname_branch_report_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bsr500_sysname_branch_report_idx ON public.build_status_recent_500 USING btree (sysname, branch, report_time);


--
-- Name: bsr500_sysname_branch_snap_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm
--

CREATE INDEX bsr500_sysname_branch_snap_idx ON public.build_status_recent_500 USING btree (sysname, branch, snapshot DESC);


--
-- Name: build_status_log_notnull_default_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_default_log_stage_idx;


--
-- Name: build_status_log_notnull_default_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_default_pkey;


--
-- Name: build_status_log_notnull_default_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_default_snapshot_idx;


--
-- Name: build_status_log_notnull_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX public.build_status_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w02_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w02_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w02_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w02_pkey;


--
-- Name: build_status_log_notnull_p2022w02_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w02_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w03_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w03_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w03_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w03_pkey;


--
-- Name: build_status_log_notnull_p2022w03_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w03_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w04_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w04_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w04_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w04_pkey;


--
-- Name: build_status_log_notnull_p2022w04_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w04_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w05_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w05_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w05_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w05_pkey;


--
-- Name: build_status_log_notnull_p2022w05_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w05_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w06_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w06_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w06_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w06_pkey;


--
-- Name: build_status_log_notnull_p2022w06_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w06_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w07_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w07_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w07_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w07_pkey;


--
-- Name: build_status_log_notnull_p2022w07_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w07_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w08_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w08_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w08_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w08_pkey;


--
-- Name: build_status_log_notnull_p2022w08_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w08_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w09_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w09_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w09_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w09_pkey;


--
-- Name: build_status_log_notnull_p2022w09_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w09_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w10_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w10_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w10_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w10_pkey;


--
-- Name: build_status_log_notnull_p2022w10_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w10_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w11_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w11_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w11_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w11_pkey;


--
-- Name: build_status_log_notnull_p2022w11_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w11_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w12_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w12_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w12_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w12_pkey;


--
-- Name: build_status_log_notnull_p2022w12_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w12_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w13_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w13_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w13_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w13_pkey;


--
-- Name: build_status_log_notnull_p2022w13_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w13_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w14_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w14_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w14_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w14_pkey;


--
-- Name: build_status_log_notnull_p2022w14_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w14_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w15_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w15_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w15_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w15_pkey;


--
-- Name: build_status_log_notnull_p2022w15_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w15_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w16_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w16_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w16_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w16_pkey;


--
-- Name: build_status_log_notnull_p2022w16_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w16_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w17_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w17_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w17_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w17_pkey;


--
-- Name: build_status_log_notnull_p2022w17_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w17_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w18_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w18_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w18_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w18_pkey;


--
-- Name: build_status_log_notnull_p2022w18_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w18_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w19_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w19_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w19_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w19_pkey;


--
-- Name: build_status_log_notnull_p2022w19_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w19_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w20_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w20_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w20_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w20_pkey;


--
-- Name: build_status_log_notnull_p2022w20_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w20_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w21_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w21_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w21_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w21_pkey;


--
-- Name: build_status_log_notnull_p2022w21_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w21_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w22_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w22_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w22_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w22_pkey;


--
-- Name: build_status_log_notnull_p2022w22_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w22_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w23_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w23_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w23_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w23_pkey;


--
-- Name: build_status_log_notnull_p2022w23_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w23_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w24_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w24_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w24_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w24_pkey;


--
-- Name: build_status_log_notnull_p2022w24_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w24_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w25_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w25_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w25_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w25_pkey;


--
-- Name: build_status_log_notnull_p2022w25_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w25_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w26_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w26_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w26_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w26_pkey;


--
-- Name: build_status_log_notnull_p2022w26_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w26_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w27_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w27_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w27_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w27_pkey;


--
-- Name: build_status_log_notnull_p2022w27_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w27_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w28_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w28_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w28_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w28_pkey;


--
-- Name: build_status_log_notnull_p2022w28_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w28_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w29_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w29_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w29_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w29_pkey;


--
-- Name: build_status_log_notnull_p2022w29_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w29_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w30_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w30_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w30_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w30_pkey;


--
-- Name: build_status_log_notnull_p2022w30_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w30_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w31_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w31_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w31_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w31_pkey;


--
-- Name: build_status_log_notnull_p2022w31_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w31_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w32_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w32_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w32_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w32_pkey;


--
-- Name: build_status_log_notnull_p2022w32_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w32_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w33_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w33_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w33_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w33_pkey;


--
-- Name: build_status_log_notnull_p2022w33_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w33_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w34_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w34_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w34_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w34_pkey;


--
-- Name: build_status_log_notnull_p2022w34_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w34_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w35_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w35_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w35_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w35_pkey;


--
-- Name: build_status_log_notnull_p2022w35_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w35_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w36_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w36_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w36_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w36_pkey;


--
-- Name: build_status_log_notnull_p2022w36_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w36_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w37_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w37_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w37_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w37_pkey;


--
-- Name: build_status_log_notnull_p2022w37_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w37_snapshot_idx;


--
-- Name: build_status_log_notnull_p2022w38_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w38_log_stage_idx;


--
-- Name: build_status_log_notnull_p2022w38_pkey; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_pkey ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w38_pkey;


--
-- Name: build_status_log_notnull_p2022w38_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX build_status_log_parts.build_status_log_notnull_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_p2022w38_snapshot_idx;


--
-- Name: build_status_log_notnull_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX public.build_status_log_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_notnull_snapshot_idx;


--
-- Name: build_status_log_null_log_stage_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX public.build_status_log_stage_idx ATTACH PARTITION build_status_log_parts.build_status_log_null_log_stage_idx;


--
-- Name: build_status_log_null_snapshot_idx; Type: INDEX ATTACH; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER INDEX public.build_status_log_snapshot_idx ATTACH PARTITION build_status_log_parts.build_status_log_null_snapshot_idx;


--
-- Name: build_status_raw set_build_status_recent_500; Type: TRIGGER; Schema: public; Owner: pgbuildfarm
--

CREATE TRIGGER set_build_status_recent_500 AFTER INSERT ON public.build_status_raw FOR EACH ROW EXECUTE FUNCTION public.set_build_status_recent_500();


--
-- Name: build_status_raw set_latest_snapshot; Type: TRIGGER; Schema: public; Owner: pgbuildfarm
--

CREATE TRIGGER set_latest_snapshot AFTER INSERT ON public.build_status_raw FOR EACH ROW EXECUTE FUNCTION public.set_latest();


--
-- Name: build_status_raw bs_fk; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.build_status_raw
    ADD CONSTRAINT bs_fk FOREIGN KEY (sysname) REFERENCES public.buildsystems(name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: build_status_log_raw build_status_log_sysname_fkey; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE public.build_status_log_raw
    ADD CONSTRAINT build_status_log_sysname_fkey FOREIGN KEY (sysname, snapshot) REFERENCES public.build_status_raw(sysname, snapshot) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: personality personality_build_systems_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY public.personality
    ADD CONSTRAINT personality_build_systems_name_fk FOREIGN KEY (name) REFERENCES public.buildsystems(name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: pub_bfarchive; Type: PUBLICATION; Schema: -; Owner: pgbuildfarm
--

CREATE PUBLICATION pub_bfarchive WITH (publish = 'insert, update');


ALTER PUBLICATION pub_bfarchive OWNER TO pgbuildfarm;

--
-- Name: pub_bfarchive build_status_log_notnull_p2022w02; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w02;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w03; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w03;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w04; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w04;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w05; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w05;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w06; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w06;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w07; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w07;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w08; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w08;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w09; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w09;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w10; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w10;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w11; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w11;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w12; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w12;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w13; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w13;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w14; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w14;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w15; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w15;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w16; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w16;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w17; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w17;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w18; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w18;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w19; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w19;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w20; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w20;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w21; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w21;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w22; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w22;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w23; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w23;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w24; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w24;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w25; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w25;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w26; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w26;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w27; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w27;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w28; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w28;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w29; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w29;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w30; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w30;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w31; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w31;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w32; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w32;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w33; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w33;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w34; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w34;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w35; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w35;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w36; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w36;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w37; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w37;


--
-- Name: pub_bfarchive build_status_log_notnull_p2022w38; Type: PUBLICATION TABLE; Schema: build_status_log_parts; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY build_status_log_parts.build_status_log_notnull_p2022w38;


--
-- Name: pub_bfarchive build_status_raw; Type: PUBLICATION TABLE; Schema: public; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY public.build_status_raw;


--
-- Name: pub_bfarchive buildsystems; Type: PUBLICATION TABLE; Schema: public; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY public.buildsystems;


--
-- Name: pub_bfarchive personality; Type: PUBLICATION TABLE; Schema: public; Owner: pgbuildfarm
--

ALTER PUBLICATION pub_bfarchive ADD TABLE ONLY public.personality;


--
-- Name: SCHEMA build_status_log_parts; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA build_status_log_parts TO pgbuildfarm;
GRANT USAGE ON SCHEMA build_status_log_parts TO bfarchive;


--
-- Name: SCHEMA partman; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA partman TO pgbuildfarm;


--
-- Name: FUNCTION apply_cluster(p_parent_schema text, p_parent_tablename text, p_child_schema text, p_child_tablename text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.apply_cluster(p_parent_schema text, p_parent_tablename text, p_child_schema text, p_child_tablename text) TO pgbuildfarm;


--
-- Name: FUNCTION apply_foreign_keys(p_parent_table text, p_child_table text, p_job_id bigint, p_debug boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.apply_foreign_keys(p_parent_table text, p_child_table text, p_job_id bigint, p_debug boolean) TO pgbuildfarm;


--
-- Name: FUNCTION apply_privileges(p_parent_schema text, p_parent_tablename text, p_child_schema text, p_child_tablename text, p_job_id bigint); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.apply_privileges(p_parent_schema text, p_parent_tablename text, p_child_schema text, p_child_tablename text, p_job_id bigint) TO pgbuildfarm;


--
-- Name: FUNCTION apply_publications(p_parent_table text, p_child_schema text, p_child_tablename text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.apply_publications(p_parent_table text, p_child_schema text, p_child_tablename text) TO pgbuildfarm;


--
-- Name: FUNCTION autovacuum_off(p_parent_schema text, p_parent_tablename text, p_source_schema text, p_source_tablename text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.autovacuum_off(p_parent_schema text, p_parent_tablename text, p_source_schema text, p_source_tablename text) TO pgbuildfarm;


--
-- Name: FUNCTION autovacuum_reset(p_parent_schema text, p_parent_tablename text, p_source_schema text, p_source_tablename text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.autovacuum_reset(p_parent_schema text, p_parent_tablename text, p_source_schema text, p_source_tablename text) TO pgbuildfarm;


--
-- Name: FUNCTION check_automatic_maintenance_value(p_automatic_maintenance text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.check_automatic_maintenance_value(p_automatic_maintenance text) TO pgbuildfarm;


--
-- Name: FUNCTION check_control_type(p_parent_schema text, p_parent_tablename text, p_control text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.check_control_type(p_parent_schema text, p_parent_tablename text, p_control text) TO pgbuildfarm;


--
-- Name: FUNCTION check_default(p_exact_count boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.check_default(p_exact_count boolean) TO pgbuildfarm;


--
-- Name: FUNCTION check_epoch_type(p_type text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.check_epoch_type(p_type text) TO pgbuildfarm;


--
-- Name: FUNCTION check_name_length(p_object_name text, p_suffix text, p_table_partition boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.check_name_length(p_object_name text, p_suffix text, p_table_partition boolean) TO pgbuildfarm;


--
-- Name: FUNCTION check_partition_type(p_type text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.check_partition_type(p_type text) TO pgbuildfarm;


--
-- Name: FUNCTION check_subpartition_limits(p_parent_table text, p_type text, OUT sub_min text, OUT sub_max text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.check_subpartition_limits(p_parent_table text, p_type text, OUT sub_min text, OUT sub_max text) TO pgbuildfarm;


--
-- Name: FUNCTION create_function_id(p_parent_table text, p_job_id bigint); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.create_function_id(p_parent_table text, p_job_id bigint) TO pgbuildfarm;


--
-- Name: FUNCTION create_function_time(p_parent_table text, p_job_id bigint); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.create_function_time(p_parent_table text, p_job_id bigint) TO pgbuildfarm;


--
-- Name: FUNCTION create_trigger(p_parent_table text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.create_trigger(p_parent_table text) TO pgbuildfarm;


--
-- Name: FUNCTION drop_constraints(p_parent_table text, p_child_table text, p_debug boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.drop_constraints(p_parent_table text, p_child_table text, p_debug boolean) TO pgbuildfarm;


--
-- Name: FUNCTION drop_partition_column(p_parent_table text, p_column text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.drop_partition_column(p_parent_table text, p_column text) TO pgbuildfarm;


--
-- Name: FUNCTION drop_partition_id(p_parent_table text, p_retention bigint, p_keep_table boolean, p_keep_index boolean, p_retention_schema text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.drop_partition_id(p_parent_table text, p_retention bigint, p_keep_table boolean, p_keep_index boolean, p_retention_schema text) TO pgbuildfarm;


--
-- Name: FUNCTION inherit_template_properties(p_parent_table text, p_child_schema text, p_child_tablename text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.inherit_template_properties(p_parent_table text, p_child_schema text, p_child_tablename text) TO pgbuildfarm;


--
-- Name: PROCEDURE reapply_constraints_proc(p_parent_table text, p_drop_constraints boolean, p_apply_constraints boolean, p_wait integer, p_dryrun boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON PROCEDURE partman.reapply_constraints_proc(p_parent_table text, p_drop_constraints boolean, p_apply_constraints boolean, p_wait integer, p_dryrun boolean) TO pgbuildfarm;


--
-- Name: FUNCTION reapply_privileges(p_parent_table text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.reapply_privileges(p_parent_table text) TO pgbuildfarm;


--
-- Name: FUNCTION show_partition_info(p_child_table text, p_partition_interval text, p_parent_table text, OUT child_start_time timestamp with time zone, OUT child_end_time timestamp with time zone, OUT child_start_id bigint, OUT child_end_id bigint, OUT suffix text); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.show_partition_info(p_child_table text, p_partition_interval text, p_parent_table text, OUT child_start_time timestamp with time zone, OUT child_end_time timestamp with time zone, OUT child_start_id bigint, OUT child_end_id bigint, OUT suffix text) TO pgbuildfarm;


--
-- Name: FUNCTION show_partition_name(p_parent_table text, p_value text, OUT partition_schema text, OUT partition_table text, OUT suffix_timestamp timestamp with time zone, OUT suffix_id bigint, OUT table_exists boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.show_partition_name(p_parent_table text, p_value text, OUT partition_schema text, OUT partition_table text, OUT suffix_timestamp timestamp with time zone, OUT suffix_id bigint, OUT table_exists boolean) TO pgbuildfarm;


--
-- Name: FUNCTION show_partitions(p_parent_table text, p_order text, p_include_default boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.show_partitions(p_parent_table text, p_order text, p_include_default boolean) TO pgbuildfarm;


--
-- Name: FUNCTION stop_sub_partition(p_parent_table text, p_jobmon boolean); Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON FUNCTION partman.stop_sub_partition(p_parent_table text, p_jobmon boolean) TO pgbuildfarm;


--
-- Name: TABLE build_status_raw; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.build_status_raw TO reader;
GRANT SELECT,INSERT ON TABLE public.build_status_raw TO pgbfweb;


--
-- Name: TABLE build_status; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT ON TABLE public.build_status TO pgbfweb;
GRANT SELECT ON TABLE public.build_status TO rssfeed;
GRANT SELECT ON TABLE public.build_status TO reader;


--
-- Name: TABLE buildsystems; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.buildsystems TO pgbfweb;
GRANT SELECT ON TABLE public.buildsystems TO rssfeed;
GRANT SELECT ON TABLE public.buildsystems TO reader;


--
-- Name: TABLE personality; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT ON TABLE public.personality TO pgbfweb;
GRANT SELECT ON TABLE public.personality TO rssfeed;
GRANT SELECT ON TABLE public.personality TO reader;


--
-- Name: TABLE allhist_summary; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.allhist_summary TO rssfeed;
GRANT SELECT ON TABLE public.allhist_summary TO reader;


--
-- Name: TABLE build_status_log_raw; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.build_status_log_raw TO reader;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.build_status_log_raw TO pgbfweb;


--
-- Name: TABLE build_status_log_notnull; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_default; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_default TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w02; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w02 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w03; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w03 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w04; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w04 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w05; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w05 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w06; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w06 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w07; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w07 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w08; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w08 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w09; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w09 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w10; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w10 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w11; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w11 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w12; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w12 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w13; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w13 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w14; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w14 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w15; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w15 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w16; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w16 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w17; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w17 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w18; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w18 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w19; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w19 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w20; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w20 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w21; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w21 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w22; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w22 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w23; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w23 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w24; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w24 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w25; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w25 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w26; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w26 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w27; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w27 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w28; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w28 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w29; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w29 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w30; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w30 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w31; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w31 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w32; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w32 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w33; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w33 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w34; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w34 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w35; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w35 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w36; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w36 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w37; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w37 TO bfarchive;


--
-- Name: TABLE build_status_log_notnull_p2022w38; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_notnull_p2022w38 TO bfarchive;


--
-- Name: TABLE build_status_log_null; Type: ACL; Schema: build_status_log_parts; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE build_status_log_parts.build_status_log_null TO bfarchive;


--
-- Name: TABLE custom_time_partitions; Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON TABLE partman.custom_time_partitions TO pgbuildfarm;


--
-- Name: TABLE part_config; Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON TABLE partman.part_config TO pgbuildfarm;


--
-- Name: TABLE part_config_sub; Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON TABLE partman.part_config_sub TO pgbuildfarm;


--
-- Name: TABLE table_privs; Type: ACL; Schema: partman; Owner: postgres
--

GRANT ALL ON TABLE partman.table_privs TO pgbuildfarm;


--
-- Name: TABLE template_build_status_log_parts_build_status_log_notnull; Type: ACL; Schema: partman; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE partman.template_build_status_log_parts_build_status_log_notnull TO bfarchive;


--
-- Name: TABLE alerts; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.alerts TO reader;
GRANT SELECT,DELETE ON TABLE public.alerts TO pgbfweb;


--
-- Name: TABLE build_status_export; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.build_status_export TO reader;


--
-- Name: TABLE build_status_log; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.build_status_log TO pgbfweb;
GRANT SELECT ON TABLE public.build_status_log TO rssfeed;
GRANT SELECT ON TABLE public.build_status_log TO reader;


--
-- Name: TABLE build_status_recent_500; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT ON TABLE public.build_status_recent_500 TO pgbfweb;
GRANT SELECT ON TABLE public.build_status_recent_500 TO reader;


--
-- Name: TABLE buildsystems_export; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.buildsystems_export TO reader;


--
-- Name: TABLE dashboard_last_modified; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.dashboard_last_modified TO reader;
GRANT SELECT,UPDATE ON TABLE public.dashboard_last_modified TO pgbfweb;


--
-- Name: TABLE dashboard_mat; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT,DELETE ON TABLE public.dashboard_mat TO pgbfweb;
GRANT SELECT ON TABLE public.dashboard_mat TO reader;


--
-- Name: TABLE latest_snapshot; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.latest_snapshot TO pgbfweb;
GRANT SELECT ON TABLE public.latest_snapshot TO reader;


--
-- Name: TABLE dashboard_mat_data; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.dashboard_mat_data TO pgbfweb;
GRANT SELECT ON TABLE public.dashboard_mat_data TO reader;


--
-- Name: TABLE failures; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.failures TO reader;


--
-- Name: TABLE nrecent_failures; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT,INSERT,DELETE ON TABLE public.nrecent_failures TO pgbfweb;
GRANT SELECT ON TABLE public.nrecent_failures TO reader;


--
-- Name: TABLE long_term_fails; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.long_term_fails TO reader;


--
-- Name: TABLE nrecent_failures_db_data; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.nrecent_failures_db_data TO reader;
GRANT SELECT ON TABLE public.nrecent_failures_db_data TO pgbfweb;


--
-- Name: TABLE nrecent_failures_db_data2; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.nrecent_failures_db_data2 TO reader;
GRANT SELECT ON TABLE public.nrecent_failures_db_data2 TO pgbfweb;


--
-- Name: TABLE recent_failures; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.recent_failures TO reader;


--
-- Name: TABLE script_versions; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.script_versions TO reader;


--
-- Name: TABLE script_versions2; Type: ACL; Schema: public; Owner: pgbuildfarm
--

GRANT SELECT ON TABLE public.script_versions2 TO reader;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: pgbuildfarm
--

ALTER DEFAULT PRIVILEGES FOR ROLE pgbuildfarm IN SCHEMA public GRANT SELECT ON TABLES  TO reader;


--
-- PostgreSQL database dump complete
--

