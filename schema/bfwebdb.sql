--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: plperl; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: pgbuildfarm
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plperl;


ALTER PROCEDURAL LANGUAGE plperl OWNER TO pgbuildfarm;

--
-- Name: plperlu; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: pgbuildfarm
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plperlu;


ALTER PROCEDURAL LANGUAGE plperlu OWNER TO pgbuildfarm;

--
-- Name: plpgsql; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: pgbuildfarm
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plpgsql;


ALTER PROCEDURAL LANGUAGE plpgsql OWNER TO pgbuildfarm;

SET search_path = public, pg_catalog;

--
-- Name: pending; Type: TYPE; Schema: public; Owner: pgbuildfarm
--

CREATE TYPE pending AS (
	name text,
	operating_system text,
	os_version text,
	compiler text,
	compiler_version text,
	architecture text,
	owner_email text
);


ALTER TYPE public.pending OWNER TO pgbuildfarm;

--
-- Name: pending2; Type: TYPE; Schema: public; Owner: pgbuildfarm
--

CREATE TYPE pending2 AS (
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


ALTER TYPE public.pending2 OWNER TO pgbuildfarm;

--
-- Name: approve(text, text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION approve(text, text) RETURNS void
    LANGUAGE sql
    AS $_$update buildsystems set name = $2, status ='approved' where name = $1 and status = 'pending'$_$;


ALTER FUNCTION public.approve(text, text) OWNER TO pgbuildfarm;

--
-- Name: approve2(text, text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION approve2(text, text) RETURNS text
    LANGUAGE sql
    AS $_$ update buildsystems set name = $2, status = 'approved' where name = $1 and status = 'pending'; select owner_email || ':' || name || ':' || secret from buildsystems where name = $2;$_$;


ALTER FUNCTION public.approve2(text, text) OWNER TO pgbuildfarm;

--
-- Name: pending(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION pending() RETURNS SETOF pending2
    LANGUAGE sql
    AS $$select name,operating_system,os_version,compiler,compiler_version,architecture,owner_email, sys_owner, status_ts from buildsystems where status = 'pending' order by status_ts $$;


ALTER FUNCTION public.pending() OWNER TO pgbuildfarm;

--
-- Name: plperl_call_handler(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION plperl_call_handler() RETURNS language_handler
    LANGUAGE c
    AS '$libdir/plperl', 'plperl_call_handler';


ALTER FUNCTION public.plperl_call_handler() OWNER TO pgbuildfarm;

--
-- Name: plpgsql_call_handler(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION plpgsql_call_handler() RETURNS language_handler
    LANGUAGE c
    AS '$libdir/plpgsql', 'plpgsql_call_handler';


ALTER FUNCTION public.plpgsql_call_handler() OWNER TO pgbuildfarm;

--
-- Name: pregex(text, text, text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION pregex(text, text, text) RETURNS text
    LANGUAGE plperl
    AS $_$ my $source = shift; my $pattern = shift; my $repl = shift; my $regex = qr($pattern)i; $source =~ s/$regex/$repl/g; return $source; $_$;


ALTER FUNCTION public.pregex(text, text, text) OWNER TO pgbuildfarm;

--
-- Name: prevstat(text, text, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION prevstat(text, text, timestamp without time zone) RETURNS text
    LANGUAGE sql
    AS $_$
   select coalesce((select distinct on (snapshot) stage
                  from build_status
                  where sysname = $1 and branch = $2 and snapshot < $3
                  order by snapshot desc
                  limit 1), 'NEW') as prev_status
$_$;


ALTER FUNCTION public.prevstat(text, text, timestamp without time zone) OWNER TO pgbuildfarm;

--
-- Name: script_version(text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION script_version(text) RETURNS text
    LANGUAGE plperl
    AS $_$

   my $log = shift;
   if ($log =~ /'script_version' => '(REL_)?(\d+)\.(\d+)'/)
   {
	return sprintf("%.03d%.03d",$2,$3);
   }
   return '-1';

$_$;


ALTER FUNCTION public.script_version(text) OWNER TO pgbuildfarm;

--
-- Name: set_latest(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION set_latest() RETURNS trigger
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
-- Name: set_local_error_terse(); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION set_local_error_terse() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    AS $$ set local log_error_verbosity = terse $$;


ALTER FUNCTION public.set_local_error_terse() OWNER TO pgbuildfarm;

--
-- Name: target(text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION target(t text) RETURNS text
    LANGUAGE plperl
    AS $_$ my $log = shift; $log =~ s/.*(Target:[^\n]*).*/$1/s; return $log; $_$;


ALTER FUNCTION public.target(t text) OWNER TO pgbuildfarm;

--
-- Name: transitions(text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION transitions(text, text, text, text, text, text) RETURNS integer
    LANGUAGE plperl
    AS $_$

my ($os,$osv,$comp,$compv,$arch,$owner) = @_;
# count transitions to and from upper case
my $trans = 1;
my $counttrans = 0;
foreach (split "" ,"$os$osv$comp$compv$arch$owner")
{
	if (/[A-Z]/)
	{
		next if $trans;
		$trans = 1;
		$counttrans++;
	}
	else
	{
		next unless $trans;
		$trans = 0;
		$counttrans++;
	}
}

return $counttrans;

$_$;


ALTER FUNCTION public.transitions(text, text, text, text, text, text) OWNER TO pgbuildfarm;

--
-- Name: web_script_version(text); Type: FUNCTION; Schema: public; Owner: pgbuildfarm
--

CREATE FUNCTION web_script_version(text) RETURNS text
    LANGUAGE plperl
    AS $_$

   my $log = shift;
   if ($log =~ /'web_script_version' => '(REL_)?(\d+)\.(\d+)'/)
   {
	return sprintf("%0.3d%0.3d",$2,$3);
   }
   return '-1';

$_$;


ALTER FUNCTION public.web_script_version(text) OWNER TO pgbuildfarm;

SET default_tablespace = '';

SET default_with_oids = true;

--
-- Name: alerts; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE alerts (
    sysname text NOT NULL,
    branch text NOT NULL,
    first_alert timestamp without time zone,
    last_notification timestamp without time zone
);


ALTER TABLE public.alerts OWNER TO pgbuildfarm;

--
-- Name: build_status; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE build_status (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    status integer,
    stage text,
    log text,
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
    git_head_ref text
);


ALTER TABLE public.build_status OWNER TO pgbuildfarm;

--
-- Name: build_status_export; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW build_status_export AS
    SELECT build_status.sysname AS name, build_status.snapshot, build_status.stage, build_status.branch, build_status.build_flags FROM build_status;


ALTER TABLE public.build_status_export OWNER TO pgbuildfarm;

--
-- Name: build_status_log; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE build_status_log (
    sysname text NOT NULL,
    snapshot timestamp without time zone NOT NULL,
    branch text NOT NULL,
    log_stage text NOT NULL,
    log_text text,
    stage_duration interval
);


ALTER TABLE public.build_status_log OWNER TO pgbuildfarm;

--
-- Name: buildsystems; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE buildsystems (
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
-- Name: buildsystems_export; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW buildsystems_export AS
    SELECT buildsystems.name, buildsystems.operating_system, buildsystems.os_version, buildsystems.compiler, buildsystems.compiler_version, buildsystems.architecture FROM buildsystems WHERE (buildsystems.status = 'approved'::text);


ALTER TABLE public.buildsystems_export OWNER TO pgbuildfarm;

--
-- Name: dashboard_mat; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE dashboard_mat (
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
    sys_notes text
);


ALTER TABLE public.dashboard_mat OWNER TO pgbuildfarm;

--
-- Name: latest_snapshot; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE latest_snapshot (
    sysname text NOT NULL,
    branch text NOT NULL,
    snapshot timestamp without time zone NOT NULL
);


ALTER TABLE public.latest_snapshot OWNER TO pgbuildfarm;

--
-- Name: personality; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE personality (
    name text NOT NULL,
    os_version text NOT NULL,
    compiler_version text NOT NULL,
    effective_date timestamp with time zone DEFAULT ('now'::text)::timestamp(6) with time zone NOT NULL
);


ALTER TABLE public.personality OWNER TO pgbuildfarm;

--
-- Name: dashboard_mat_data; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW dashboard_mat_data AS
    SELECT b.sysname, b.snapshot, b.status, b.stage, b.branch, CASE WHEN ((b.conf_sum ~ 'use_vpath'::text) AND (b.conf_sum !~ '''use_vpath'' => undef'::text)) THEN (b.build_flags || 'vpath'::text) ELSE b.build_flags END AS build_flags, s.operating_system, COALESCE(b.os_version, s.os_version) AS os_version, s.compiler, COALESCE(b.compiler_version, s.compiler_version) AS compiler_version, s.architecture, s.sys_notes_ts, s.sys_notes FROM buildsystems s, (SELECT DISTINCT ON (bs.sysname, bs.branch, bs.report_time) bs.sysname, bs.snapshot, bs.status, bs.stage, bs.branch, bs.build_flags, bs.conf_sum, bs.report_time, p.compiler_version, p.os_version FROM ((build_status bs NATURAL JOIN latest_snapshot m) LEFT JOIN personality p ON (((p.name = bs.sysname) AND (p.effective_date <= bs.report_time)))) WHERE (m.snapshot > (now() - '30 days'::interval)) ORDER BY bs.sysname, bs.branch, bs.report_time, (p.effective_date IS NULL), p.effective_date DESC) b WHERE ((s.name = b.sysname) AND (s.status = 'approved'::text));


ALTER TABLE public.dashboard_mat_data OWNER TO pgbuildfarm;

--
-- Name: failures; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW failures AS
    SELECT build_status.sysname, build_status.snapshot, build_status.stage, build_status.conf_sum, build_status.branch, build_status.changed_this_run, build_status.changed_since_success, build_status.log_archive_filenames, build_status.build_flags, build_status.report_time FROM build_status WHERE (((build_status.stage <> 'OK'::text) AND (build_status.stage !~~ 'CVS%'::text)) AND (build_status.report_time IS NOT NULL));


ALTER TABLE public.failures OWNER TO pgbuildfarm;

--
-- Name: list_subscriptions; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE list_subscriptions (
    addr text
);


ALTER TABLE public.list_subscriptions OWNER TO pgbuildfarm;

--
-- Name: penguin_save; Type: TABLE; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE TABLE penguin_save (
    branch text,
    snapshot timestamp without time zone,
    stage text
);


ALTER TABLE public.penguin_save OWNER TO pgbuildfarm;

--
-- Name: recent_failures; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW recent_failures AS
    SELECT build_status.sysname, build_status.snapshot, build_status.stage, build_status.conf_sum, build_status.branch, build_status.changed_this_run, build_status.changed_since_success, build_status.log_archive_filenames, build_status.build_flags, build_status.report_time, build_status.log FROM build_status WHERE ((((build_status.stage <> 'OK'::text) AND (build_status.stage !~~ 'CVS%'::text)) AND (build_status.report_time IS NOT NULL)) AND ((build_status.snapshot + '3 mons'::interval) > ('now'::text)::timestamp(6) with time zone));


ALTER TABLE public.recent_failures OWNER TO pgbuildfarm;

--
-- Name: script_versions; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW script_versions AS
    SELECT b.sysname, b.snapshot, b.branch, (script_version(b.conf_sum))::numeric AS script_version, (web_script_version(b.conf_sum))::numeric AS web_script_version FROM (build_status b JOIN dashboard_mat d ON (((b.sysname = d.sysname) AND (b.snapshot = d.snapshot))));


ALTER TABLE public.script_versions OWNER TO pgbuildfarm;

--
-- Name: script_versions2; Type: VIEW; Schema: public; Owner: pgbuildfarm
--

CREATE VIEW script_versions2 AS
    SELECT b.sysname, b.snapshot, b.branch, script_version(b.conf_sum) AS script_version, web_script_version(b.conf_sum) AS web_script_version FROM (build_status b JOIN dashboard_mat d ON (((b.sysname = d.sysname) AND (b.snapshot = d.snapshot))));


ALTER TABLE public.script_versions2 OWNER TO pgbuildfarm;

--
-- Name: alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (sysname, branch);


--
-- Name: build_status_log_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY build_status_log
    ADD CONSTRAINT build_status_log_pkey PRIMARY KEY (sysname, snapshot, log_stage);


--
-- Name: build_status_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY build_status
    ADD CONSTRAINT build_status_pkey PRIMARY KEY (sysname, snapshot);


--
-- Name: buildsystems_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY buildsystems
    ADD CONSTRAINT buildsystems_pkey PRIMARY KEY (name);


--
-- Name: dashboard_mat_pk; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY dashboard_mat
    ADD CONSTRAINT dashboard_mat_pk PRIMARY KEY (branch, sysname, snapshot);

ALTER TABLE dashboard_mat CLUSTER ON dashboard_mat_pk;


--
-- Name: latest_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY latest_snapshot
    ADD CONSTRAINT latest_snapshot_pkey PRIMARY KEY (sysname, branch);


--
-- Name: personality_pkey; Type: CONSTRAINT; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

ALTER TABLE ONLY personality
    ADD CONSTRAINT personality_pkey PRIMARY KEY (name, effective_date);


--
-- Name: bs_branch_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_branch_snapshot_idx ON build_status USING btree (branch, snapshot);


--
-- Name: bs_status_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_status_idx ON buildsystems USING btree (status);


--
-- Name: bs_sysname_branch_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_sysname_branch_idx ON build_status USING btree (sysname, branch);


--
-- Name: bs_sysname_branch_report_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX bs_sysname_branch_report_idx ON build_status USING btree (sysname, branch, report_time);


--
-- Name: build_status_log_snapshot_idx; Type: INDEX; Schema: public; Owner: pgbuildfarm; Tablespace: 
--

CREATE INDEX build_status_log_snapshot_idx ON build_status_log USING btree (snapshot);


--
-- Name: set_latest_snapshot; Type: TRIGGER; Schema: public; Owner: pgbuildfarm
--

CREATE TRIGGER set_latest_snapshot AFTER INSERT ON build_status FOR EACH ROW EXECUTE PROCEDURE set_latest();


--
-- Name: bs_fk; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status
    ADD CONSTRAINT bs_fk FOREIGN KEY (sysname) REFERENCES buildsystems(name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: build_status_log_sysname_fkey; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY build_status_log
    ADD CONSTRAINT build_status_log_sysname_fkey FOREIGN KEY (sysname, snapshot) REFERENCES build_status(sysname, snapshot) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: personality_build_systems_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: pgbuildfarm
--

ALTER TABLE ONLY personality
    ADD CONSTRAINT personality_build_systems_name_fk FOREIGN KEY (name) REFERENCES buildsystems(name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO pgbuildfarm;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: build_status; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE build_status FROM PUBLIC;
REVOKE ALL ON TABLE build_status FROM pgbuildfarm;
GRANT ALL ON TABLE build_status TO pgbuildfarm;
GRANT SELECT,INSERT ON TABLE build_status TO pgbfweb;
GRANT SELECT ON TABLE build_status TO rssfeed;


--
-- Name: build_status_log; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE build_status_log FROM PUBLIC;
REVOKE ALL ON TABLE build_status_log FROM pgbuildfarm;
GRANT ALL ON TABLE build_status_log TO pgbuildfarm;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE build_status_log TO pgbfweb;
GRANT SELECT ON TABLE build_status_log TO rssfeed;


--
-- Name: buildsystems; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE buildsystems FROM PUBLIC;
REVOKE ALL ON TABLE buildsystems FROM pgbuildfarm;
GRANT ALL ON TABLE buildsystems TO pgbuildfarm;
GRANT SELECT,INSERT,UPDATE ON TABLE buildsystems TO pgbfweb;
GRANT SELECT ON TABLE buildsystems TO rssfeed;


--
-- Name: dashboard_mat; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE dashboard_mat FROM PUBLIC;
REVOKE ALL ON TABLE dashboard_mat FROM pgbuildfarm;
GRANT ALL ON TABLE dashboard_mat TO pgbuildfarm;
GRANT SELECT,INSERT,DELETE ON TABLE dashboard_mat TO pgbfweb;


--
-- Name: latest_snapshot; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE latest_snapshot FROM PUBLIC;
REVOKE ALL ON TABLE latest_snapshot FROM pgbuildfarm;
GRANT ALL ON TABLE latest_snapshot TO pgbuildfarm;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE latest_snapshot TO pgbfweb;


--
-- Name: personality; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE personality FROM PUBLIC;
REVOKE ALL ON TABLE personality FROM pgbuildfarm;
GRANT ALL ON TABLE personality TO pgbuildfarm;
GRANT SELECT,INSERT ON TABLE personality TO pgbfweb;
GRANT SELECT ON TABLE personality TO rssfeed;


--
-- Name: dashboard_mat_data; Type: ACL; Schema: public; Owner: pgbuildfarm
--

REVOKE ALL ON TABLE dashboard_mat_data FROM PUBLIC;
REVOKE ALL ON TABLE dashboard_mat_data FROM pgbuildfarm;
GRANT ALL ON TABLE dashboard_mat_data TO pgbuildfarm;
GRANT SELECT ON TABLE dashboard_mat_data TO pgbfweb;


--
-- PostgreSQL database dump complete
--

