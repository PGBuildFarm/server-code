#!/usr/bin/perl

=comment

Copyright (c) 2003-2026, Andrew Dunstan

See accompanying License file for license details

A read-only JSON query API for the buildfarm database. Routing is by
PATH_INFO, with optional query-string parameters to narrow results:

  GET .../bfapi.pl/status[/<branch>[/<member>]]
        current dashboard status, one row per member+branch.
        query params: member (repeatable), owner, sortby=name|os|compiler

  GET .../bfapi.pl/history/<member>[/<branch>]
        recent run history for a member (from the recent-500 cache).
        query params: branch, limit (default 100, max 500)

  GET .../bfapi.pl/failures[/<branch>]
        recent failures across the farm.
        query params: member (repeatable), stage (repeatable),
                      branch (repeatable), max_days (default 10), skipok

  GET .../bfapi.pl/members[/<member>]
        buildfarm animal metadata.
        query params: sort_by=name|owner|os|compiler|arch

  GET .../bfapi.pl/build/<member>?snapshot=<ts>|latest[&branch=<branch>]
        full record for a single run, including the list of stages whose
        logs are available (fetch them via /log). 'latest' resolves to the
        most recent run in the last 30 days and requires a branch.

  GET .../bfapi.pl/log/<member>/<stage>?snapshot=<ts>|latest[&branch=<branch>]
        the captured log text for one stage of one run.
        query params: format=json|text (default json); for 'latest' a
        branch is required.

  GET .../bfapi.pl/commit/<gitref>
        all runs built at a given git commit (prefix match, >= 5 hex
        digits), newest first.
        query params: member, branch, limit (default 200, max 1000)

Branches may be given as either the internal name (HEAD) or the public
name (master); they are accepted interchangeably and reported as the
public name. Owner email addresses are obfuscated in output. The snapshot
timestamp is passed as a query parameter (it contains a space) in the
form 'YYYY-MM-DD HH:MM:SS', GMT.

=cut

use strict;
use warnings;

use lib "$ENV{BFCONFDIR}/perl5";
use BFUtils;

use DBI;
use CGI;
use JSON::PP;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $email_only);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

setup_die_handler();

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

# pre-declarations
sub send_json;
sub send_error;
sub clean_member;
sub clean_branch;
sub clean_stage;
sub clean_log_stage;
sub clean_snapshot;
sub clean_gitref;
sub obfuscate_email;
sub resolve_snapshot;
sub do_status;
sub do_history;
sub do_failures;
sub do_members;
sub do_build;
sub do_log;
sub do_commit;

my $json = JSON::PP->new->utf8->pretty->allow_nonref->canonical(1);

my $cgi = CGI->new;

# Split PATH_INFO into resource and positional arguments, dropping the
# empty element that leads a string beginning with '/'.
my $pathinfo = $cgi->path_info() || '';
my @path     = split m{/}, $pathinfo;
shift @path while @path && $path[0] eq '';
my $resource = shift @path // '';

my %dispatch = (
	status   => \&do_status,
	history  => \&do_history,
	failures => \&do_failures,
	members  => \&do_members,
	build    => \&do_build,
	log      => \&do_log,
	commit   => \&do_commit,
);

my $handler = $dispatch{$resource}
  or send_error(404,
		"unknown resource '$resource'; "
	  . "expected one of: "
	  . join(", ", sort keys %dispatch));

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $dbh = DBI->connect($dsn, $dbuser, $dbpass, { pg_expand_array => 0 })
  or send_error(500, "database connection failed");

my $rows = $handler->($dbh, $cgi, \@path);

$dbh->disconnect;

send_json($rows);

#---------------------------------------------------------------------------
# helpers
#---------------------------------------------------------------------------

sub send_json
{
	my ($data) = @_;
	print "Content-Type: application/json\n\n";
	print $json->encode($data);
	exit;
}

sub send_error
{
	my ($code, $msg) = @_;
	print "Status: $code\n";
	print "Content-Type: application/json\n\n";
	print $json->encode({ error => $msg });
	exit;
}

# Input sanitizers mirror the character classes used by the existing
# show_*.pl scripts. Each returns undef for an empty/undefined value so the
# SQL "(? ::text is null or col = ?)" idiom turns the filter off.
sub clean_member
{
	my ($val) = @_;
	return unless defined $val && $val ne '';
	$val =~ s/[^a-zA-Z0-9_ -]//g;
	return $val eq '' ? undef : $val;
}

sub clean_branch
{
	my ($val) = @_;
	return unless defined $val && $val ne '';
	$val =~ s{[^a-zA-Z0-9_/ -]}{}g;
	$val =~ s/^master$/HEAD/;
	return $val eq '' ? undef : $val;
}

sub clean_stage
{
	my ($val) = @_;
	return unless defined $val && $val ne '';
	$val =~ s/[^a-zA-Z0-9_ :-]//g;
	return $val eq '' ? undef : $val;
}

# A log stage name may contain a dot (e.g. the ".log" suffix, or module
# names); this matches the sanitizer in show_stage_log.pl.
sub clean_log_stage
{
	my ($val) = @_;
	return unless defined $val && $val ne '';
	$val =~ s/[^a-zA-Z0-9._ -]//g;
	return $val eq '' ? undef : $val;
}

# A snapshot is either the literal 'latest' or a 'YYYY-MM-DD HH:MM:SS'
# timestamp. Anything else is rejected (returns undef).
sub clean_snapshot
{
	my ($val) = @_;
	return unless defined $val && $val ne '';
	return 'latest' if lc $val eq 'latest';
	$val =~ s/[^0-9 :-]//g;
	return $val =~ /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/ ? $val : undef;
}

# A git ref is matched as a hex prefix; require enough digits to be
# meaningful so we never match the whole table on a stray short string.
sub clean_gitref
{
	my ($val) = @_;
	return unless defined $val && $val ne '';
	$val =~ s/[^0-9a-fA-F]//g;
	return length $val >= 5 ? $val : undef;
}

sub obfuscate_email
{
	my ($email) = @_;
	return $email unless defined $email;
	$email =~ s/\@/ [ a t ] /;
	return $email;
}

# Fetch the repeatable values of a query parameter, sanitized and with empty
# entries dropped. $cleaner is one of the clean_* subs above.
sub multi_param_clean
{
	my ($query, $name, $cleaner) = @_;
	my @vals =
		$CGI::VERSION < 4.08
	  ? $query->param($name)
	  : $query->multi_param($name);
	return grep { defined } map { $cleaner->($_) } @vals;
}

#---------------------------------------------------------------------------
# resource handlers
#---------------------------------------------------------------------------

sub do_status
{
	my ($db, $query, $path) = @_;

	my $branch = clean_branch($path->[0]);
	my $member = clean_member($path->[1])
	  // clean_member($query->param('member'));
	my $owner = $query->param('owner');
	$owner =~ s/[^a-zA-Z0-9_.@+-]//g if $owner;
	$owner = undef                   if defined $owner && $owner eq '';

	my %sort_clause = (
		name     => 'lower(b.sysname),',
		os       => 'lower(b.operating_system), b.os_version desc,',
		compiler => 'lower(b.compiler), b.compiler_version,',
	);
	my $sortby = $sort_clause{ $query->param('sortby') || '' } || '';

	my $statement = qq{
		select
			extract(epoch from (timezone('GMT', now())::timestamp(0)
				- b.snapshot))::int as when_ago_secs,
			b.sysname, b.snapshot, b.status, b.stage, b.branch,
			b.build_flags, b.operating_system, b.os_version,
			b.compiler, b.compiler_version, b.architecture,
			b.git_head_ref, b.report_time,
			l.log_archive_filenames
		from dashboard_mat b
			join buildsystems s on s.name = b.sysname
			join build_status_raw l
				on l.sysname = b.sysname and l.snapshot = b.snapshot
		where (? ::text is null or b.branch = ?)
			and (? ::text is null or b.sysname = ?)
			and (? ::text is null or s.owner_email = ?)
		order by b.branch = 'HEAD' desc, b.branch COLLATE "C" desc,
			$sortby b.report_time desc
	};

	my $sth = $db->prepare($statement);
	$sth->execute($branch, $branch, $member, $member, $owner, $owner);

	my $out = [];
	while (my $row = $sth->fetchrow_hashref)
	{
		$row->{build_flags} = [
			split /\s+/,
			normalize_build_flags($row->{branch}, $row->{build_flags})
		];
		$row->{branch} =~ s/^HEAD$/master/;
		my $files = $row->{log_archive_filenames};
		$files = '' unless defined $files;
		$files =~ s/[{}]//g;
		$row->{log_archive_filenames} = [ split /,/, $files ];
		push @$out, $row;
	}
	$sth->finish;
	return $out;
}

sub do_history
{
	my ($db, $query, $path) = @_;

	my $member = clean_member($path->[0]);
	send_error(400, "history requires a member name") unless defined $member;

	my $branch = clean_branch($path->[1])
	  // clean_branch($query->param('branch'));

	my $limit = $query->param('limit');
	$limit = ($limit && $limit =~ /^\d+$/) ? $limit + 0 : 100;
	$limit = 500 if $limit > 500;

	my $statement = q{
		with x as (
			select *
			from build_status_recent_500
			where sysname = ?
				and (? ::text is null or branch = ?)
		)
		select
			extract(epoch from ((now() at time zone 'GMT')::timestamp(0)
				- snapshot))::int as when_ago_secs,
			sysname, snapshot, status, stage, branch,
			coalesce(script_version, '') as script_version,
			git_head_ref, run_secs
		from x
		order by snapshot desc
		limit ?
	};

	my $sth = $db->prepare($statement);
	$sth->execute($member, $branch, $branch, $limit);

	my $out = [];
	while (my $row = $sth->fetchrow_hashref)
	{
		$row->{script_version} =~ s/^(\d{3})0(\d{2})/$1.$2/;
		$row->{script_version} =~ s/^0+//;
		$row->{branch}         =~ s/^HEAD$/master/ if defined $row->{branch};
		push @$out, $row;
	}
	$sth->finish;
	return $out;
}

sub do_failures
{
	my ($db, $query, $path) = @_;

	my @members  = multi_param_clean($query, 'member', \&clean_member);
	my @stages   = multi_param_clean($query, 'stage',  \&clean_stage);
	my @branches = multi_param_clean($query, 'branch', \&clean_branch);
	my $pbranch  = clean_branch($path->[0]);
	push @branches, $pbranch if defined $pbranch;

	my $qmdays   = $query->param('max_days');
	my $max_days = ($qmdays && $qmdays =~ /^\d+$/) ? $qmdays + 0 : 10;
	my $skipok   = $query->param('skipok');

	# This mirrors the query in show_failures.pl: the most recent failures
	# (per nrecent_failures) within the requested window, joined back to the
	# system metadata and to the current dashboard stage.
	my $statement = q{
		with db_data as (
			select b.sysname, b.snapshot, b.status, b.stage, b.branch,
				case
					when b.conf_sum ~ 'use_vpath'
						and b.conf_sum !~ '''use_vpath'' => undef'
					then b.build_flags || 'vpath'
					else b.build_flags
				end as build_flags,
				s.operating_system, s.compiler, s.os_version,
				s.compiler_version, b.git_head_ref, b.report_time
			from buildsystems s,
				( select bs.sysname, bs.snapshot, bs.status, bs.stage,
						bs.branch, bs.build_flags, bs.conf_sum,
						bs.report_time, bs.git_head_ref
					from build_status bs
						join nrecent_failures m
							using (sysname, snapshot, branch)
					where m.snapshot > (now() - '90 days'::interval) ) b
			where s.name = b.sysname and s.status = 'approved'
		)
		select
			extract(epoch from (timezone('GMT', now())::timestamp(0)
				- b.snapshot))::int as when_ago_secs,
			b.*, d.stage as current_stage
		from db_data b
			left join dashboard_mat d
				on (d.sysname = b.sysname and d.branch = b.branch)
		where (now()::timestamp(0) without time zone - b.snapshot)
			< (? * interval '1 day')
		order by b.branch = 'HEAD' desc, b.branch COLLATE "C" desc,
			b.snapshot desc
	};

	my $fetch_personality = $db->prepare(
		q{
		select os_version, compiler_version
		from personality
		where name = ? and effective_date <= ?
		order by effective_date desc
		limit 1
	}
	);

	my $sth = $db->prepare($statement);
	$sth->execute($max_days);

	my $out = [];
	while (my $row = $sth->fetchrow_hashref)
	{
		next if (@members  && !grep { $_ eq $row->{sysname} } @members);
		next if (@stages   && !grep { $_ eq $row->{stage} } @stages);
		next if (@branches && !grep { $_ eq $row->{branch} } @branches);
		next
		  if $skipok
		  && defined $row->{current_stage}
		  && $row->{current_stage} eq 'OK';

		$row->{build_flags} = [
			split /\s+/,
			normalize_build_flags($row->{branch}, $row->{build_flags})
		];

		# personality at report time overrides the current system metadata
		$fetch_personality->execute($row->{sysname}, $row->{report_time});
		my @personality = $fetch_personality->fetchrow_array();
		if (@personality)
		{
			$row->{os_version}       = $personality[0];
			$row->{compiler_version} = $personality[1];
		}

		$row->{branch} =~ s/^HEAD$/master/;
		push @$out, $row;
	}
	$sth->finish;
	return $out;
}

sub do_members
{
	my ($db, $query, $path) = @_;

	my $member = clean_member($path->[0]);

	my %sort_ok = (
		name     => 'lower(name)',
		owner    => 'lower(owner_email)',
		os       => 'lower(operating_system), os_version',
		compiler => 'lower(compiler), compiler_version',
		arch     => 'lower(architecture)',
	);
	my $sort_by = $query->param('sort_by') || '';
	$sort_by = $sort_ok{$sort_by} || $sort_ok{name};

	my $statement = qq{
		select name, operating_system, os_version, compiler,
			compiler_version, owner_email,
			sys_notes_ts::date as sys_notes_date, sys_notes,
			architecture as arch, status,
			status_ts::date as status_date,
			array(
				select case when branch = 'HEAD' then 'master' else branch end
					|| ':' || extract(days from now() - l.snapshot)
				from latest_snapshot l
				where l.sysname = s.name
				order by branch <> 'HEAD', branch COLLATE "C" desc
			) as branches,
			array(
				select compiler_version || E'\t' || os_version
					|| E'\t' || effective_date
				from personality p
				where p.name = s.name
				order by effective_date
			) as personalities
		from buildsystems s
		where status not in ('pending', 'declined')
			and (? ::text is null or name = ?)
		order by $sort_by
	};

	my $sth = $db->prepare($statement);
	$sth->execute($member, $member);

	my $out = [];
	while (my $row = $sth->fetchrow_hashref)
	{
		$row->{branches} =~ s/^\{(.*)\}$/$1/;
		$row->{branches} = [ split /,/, $row->{branches} ];

		my $personalities = $row->{personalities};
		$personalities =~ s/^\{(.*)\}$/$1/;
		$row->{personalities} = [];
		foreach my $personality (split /,/, $personalities)
		{
			$personality =~ s/^"(.*)"$/$1/;
			$personality =~ s/\\(.)/$1/g;
			my ($compiler_version, $os_version, $effective_date) =
			  split /\t/, $personality;
			$effective_date =~ s/ .*// if defined $effective_date;
			push @{ $row->{personalities} },
			  {
				compiler_version => $compiler_version,
				os_version       => $os_version,
				effective_date   => $effective_date,
			  };
		}

		$row->{owner_email} = obfuscate_email($row->{owner_email});
		push @$out, $row;
	}
	$sth->finish;
	return $out;
}

# Resolve a snapshot value to a concrete timestamp. 'latest' becomes the most
# recent snapshot for the member+branch within the last 30 days (branch is
# required in that case). A concrete timestamp is returned unchanged. Returns
# undef if it cannot be resolved.
sub resolve_snapshot
{
	my ($db, $member, $branch, $snapshot) = @_;
	return $snapshot unless $snapshot eq 'latest';
	return           unless defined $branch;
	my ($ts) = $db->selectrow_array(
		q{
			select max(snapshot)
			from build_status_raw
			where sysname = ? and branch = ?
				and snapshot > now() - interval '30 days'
		}, undef, $member, $branch
	);
	return $ts;
}

sub do_build
{
	my ($db, $query, $path) = @_;

	my $member = clean_member($path->[0]);
	send_error(400, "build requires a member name") unless defined $member;

	my $branch   = clean_branch($query->param('branch'));
	my $snapshot = clean_snapshot($query->param('snapshot'));
	send_error(400, "build requires a valid snapshot (or 'latest')")
	  unless defined $snapshot;

	if ($snapshot eq 'latest')
	{
		send_error(400, "snapshot=latest requires a branch")
		  unless defined $branch;
		$snapshot = resolve_snapshot($db, $member, $branch, 'latest');
		send_error(404, "no recent run found") unless defined $snapshot;
	}

	my $statement = q{
		select b.status, b.stage, b.branch, b.conf_sum, b.scm, b.scmurl,
			b.git_head_ref, b.changed_this_run, b.changed_since_success,
			b.log_archive_filenames, b.build_flags, b.report_time, b.run_secs,
			extract(epoch from (timezone('GMT', now())::timestamp(0)
				- b.snapshot))::int as when_ago_secs,
			s.operating_system, s.os_version, s.compiler,
			s.compiler_version, s.architecture, s.owner_email
		from build_status_raw b
			left join buildsystems s on s.name = b.sysname
		where b.sysname = ? and b.snapshot = ?
	};
	my $row = $db->selectrow_hashref($statement, undef, $member, $snapshot);
	send_error(404, "no such build") unless $row;

	$row->{sysname}     = $member;
	$row->{snapshot}    = $snapshot;
	$row->{build_flags} = [
		split /\s+/, normalize_build_flags($row->{branch}, $row->{build_flags})
	];
	my $files = $row->{log_archive_filenames};
	$files = '' unless defined $files;
	$files =~ s/[{}]//g;
	$row->{log_archive_filenames} = [ split /,/, $files ];
	$row->{owner_email}           = obfuscate_email($row->{owner_email});

	# personality as of report time overrides the current system metadata
	my $personality = $db->selectrow_arrayref(
		q{
			select os_version, compiler_version
			from personality
			where name = ? and effective_date <= ?
			order by effective_date desc
			limit 1
		}, undef, $member, $row->{report_time}
	);
	if ($personality)
	{
		$row->{os_version}       = $personality->[0];
		$row->{compiler_version} = $personality->[1];
	}

	# the stages whose logs are available for this run (reported without the
	# '.log' suffix); read from the raw table to avoid decoding the log text
	my $stages = $db->selectall_arrayref(
		q{
			select log_stage,
				extract(epoch from stage_duration)::int as duration_secs
			from build_status_log_raw
			where sysname = ? and snapshot = ?
			order by log_stage
		}, { Slice => {} }, $member, $snapshot
	);
	for my $st (@$stages)
	{
		($st->{stage} = $st->{log_stage}) =~ s/\.log$//;
		delete $st->{log_stage};
	}
	$row->{stages} = $stages;

	$row->{branch} =~ s/^HEAD$/master/ if defined $row->{branch};
	return $row;
}

sub do_log
{
	my ($db, $query, $path) = @_;

	my $member = clean_member($path->[0]);
	my $stage  = clean_log_stage($path->[1]);
	send_error(400, "log requires a member and a stage")
	  unless defined $member && defined $stage;

	my $branch   = clean_branch($query->param('branch'));
	my $snapshot = clean_snapshot($query->param('snapshot'));
	send_error(400, "log requires a valid snapshot (or 'latest')")
	  unless defined $snapshot;

	my $format = lc($query->param('format') || 'json');

	if ($snapshot eq 'latest')
	{
		send_error(400, "snapshot=latest requires a branch")
		  unless defined $branch;

		# resolve against the stage's own log presence, as show_stage_log.pl does
		my ($ts) = $db->selectrow_array(
			q{
				select max(snapshot)
				from build_status_log_raw
				where sysname = ? and branch = ? and log_stage = ? || '.log'
					and snapshot > now() - interval '30 days'
			}, undef, $member, $branch, $stage
		);
		send_error(404, "no recent log found") unless defined $ts;
		$snapshot = $ts;
	}

	my $row = $db->selectrow_hashref(
		q{
			select branch, log_text
			from build_status_log
			where sysname = ? and snapshot = ? and log_stage = ? || '.log'
		}, undef, $member, $snapshot, $stage
	);
	send_error(404, "no such log") unless $row;

	(my $pubbranch = $row->{branch} // '') =~ s/^HEAD$/master/;

	if ($format eq 'text')
	{
		print "Content-Type: text/plain; charset=utf-8\n\n";
		print $row->{log_text} if defined $row->{log_text};
		exit;
	}

	return {
		sysname  => $member,
		snapshot => $snapshot,
		branch   => $pubbranch,
		stage    => $stage,
		log_text => $row->{log_text},
	};
}

sub do_commit
{
	my ($db, $query, $path) = @_;

	my $gitref = clean_gitref($path->[0]);
	send_error(400, "commit requires a git ref of at least 5 hex digits")
	  unless defined $gitref;

	my $member = clean_member($query->param('member'));
	my $branch = clean_branch($query->param('branch'));

	my $limit = $query->param('limit');
	$limit = ($limit && $limit =~ /^\d+$/) ? $limit + 0 : 200;
	$limit = 1000 if $limit > 1000;

	# git_head_ref has a text_pattern_ops index, so the prefix LIKE is an
	# index range scan (the parameter is folded into the custom plan).
	my $statement = q{
		select
			extract(epoch from (timezone('GMT', now())::timestamp(0)
				- snapshot))::int as when_ago_secs,
			sysname, snapshot, status, stage, branch,
			git_head_ref, report_time, run_secs
		from build_status_raw
		where git_head_ref like ? || '%'
			and (? ::text is null or branch = ?)
			and (? ::text is null or sysname = ?)
		order by snapshot desc
		limit ?
	};

	my $sth = $db->prepare($statement);
	$sth->execute($gitref, $branch, $branch, $member, $member, $limit);

	my $out = [];
	while (my $row = $sth->fetchrow_hashref)
	{
		$row->{branch} =~ s/^HEAD$/master/ if defined $row->{branch};
		push @$out, $row;
	}
	$sth->finish;
	return $out;
}
