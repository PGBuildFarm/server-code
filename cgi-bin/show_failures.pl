#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $query = CGI->new;
my @members;
my @branches;
my @stages;
if ($CGI::VERSION < 4.08)
{
	@members  = grep { $_ ne "" } $query->param('member');
	@branches = grep { $_ ne "" } $query->param('branch');
	@stages   = grep { $_ ne "" } $query->param('stage');
}
else
{
	@members  = grep { $_ ne "" } $query->multi_param('member');
	@branches = grep { $_ ne "" } $query->multi_param('branch');
	@stages   = grep { $_ ne "" } $query->multi_param('stage');
}
do { s{[^a-zA-Z0-9_/ -]}{}g; }
  foreach @branches;
do { s/[^a-zA-Z0-9_ -]//g; }
  foreach @members;
do { s/[^a-zA-Z0-9_ :-]//g; }
  foreach @stages;
my $qmdays   = $query->param('max_days');
my $max_days = $qmdays ? $qmdays + 0 : 10;
my $skipok = $query->param('skipok');

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $sort_clause    = "";
my $presort_clause = "";
my $sortby         = $query->param('sortby') || 'nosort';
if ($sortby eq 'name')
{
	$sort_clause = 'lower(b.sysname),';
}
elsif ($sortby eq 'namenobranch')
{
	$presort_clause = "lower(b.sysname), b.snapshot desc,";
}

my $db = DBI->connect($dsn, $dbuser, $dbpass, { pg_expand_array => 0 })
  or die("$dsn,$dbuser,$dbpass,$!");

# If the dashboard hasn't been updated then the failures can't have been either
# so we use the same test for both. That saves keeping a separate update date
# for failures.

my $ifmodsince =
  $query->http('If-Modified-Since') || 'Thu, 01 Jan 1970 00:00:00 GMT';

my ($lastmod, $lastmodhead, $nomodsince) = $db->selectrow_array(
	"select ts at time zone 'UTC',
                        to_char(ts,'Dy, DD Mon YYYY HH24:MI:SS GMT'),
                        ts <= to_timestamp(?,'Dy, DD Mon YYYY HH24:MI:SS GMT')
                        from dashboard_last_modified",
	undef, $ifmodsince
);

if ($lastmod && $nomodsince)
{
	print "Status: 304 Not Modified\n\n";
	exit;
}

my $get_all_branches = qq{

  select distinct branch COLLATE "C"
  from nrecent_failures
  where branch <> 'HEAD'
  order by branch COLLATE "C" desc

};

my $all_branches = $db->selectcol_arrayref($get_all_branches);
unshift(@$all_branches, 'HEAD');

my $get_all_members = qq{

  select distinct sysname
  from nrecent_failures
  order by sysname

};

my $all_members = $db->selectcol_arrayref($get_all_members);

my $get_all_stages = qq{

  select distinct stage
  from build_status
    join nrecent_failures using (sysname,snapshot,branch)
  order by 1

};

my $all_stages = $db->selectcol_arrayref($get_all_stages);

my $pstmt = <<'EOS';

    select os_version, compiler_version
    from personality
    where name = ? and effective_date <= ?
    order by effective_date desc
    limit 1

EOS

my $fetch_personality = $db->prepare($pstmt);



my $statement = <<"EOS";

  with db_data as (

  SELECT b.sysname,
    b.snapshot,
    b.status,
    b.stage,
    b.branch,
        CASE
            WHEN b.conf_sum ~ 'use_vpath'::text AND b.conf_sum !~ '''use_vpath'' => undef'::text THEN b.build_flags || 'vpath'::text
            ELSE b.build_flags
        END AS build_flags,
    s.operating_system,
    s.compiler,
    s.os_version,
    s.compiler_version,
    s.sys_notes_ts,
    s.sys_notes,
    b.git_head_ref,
    b.report_time
   FROM buildsystems s,
    ( SELECT bs.sysname,
            bs.snapshot,
            bs.status,
            bs.stage,
            bs.branch,
            bs.build_flags,
            bs.conf_sum,
            bs.report_time,
            bs.git_head_ref
           FROM build_status bs
             JOIN nrecent_failures m USING (sysname, snapshot, branch)
          WHERE m.snapshot > (now() - '90 days'::interval)
          ORDER BY bs.sysname, bs.branch, bs.report_time  ) b
  WHERE s.name = b.sysname AND s.status = 'approved'::text

  )
  select timezone('GMT'::text,
	now())::timestamp(0) without time zone - b.snapshot AS when_ago,
	b.*,
	d.stage as current_stage
  from db_data b
	left join  dashboard_mat d
		on (d.sysname = b.sysname and d.branch = b.branch)
  where (now()::timestamp(0) without time zone - b.snapshot)
         < (? * interval '1 day')
  order by $presort_clause
        b.branch = 'HEAD' desc,
        b.branch COLLATE "C" desc,
        $sort_clause
        b.snapshot desc

EOS



my $statrows = [];
my $sth      = $db->prepare($statement);
$sth->execute($max_days);
while (my $row = $sth->fetchrow_hashref)
{
	next if (@members  && !grep { $_ eq $row->{sysname} } @members);
	next if (@stages   && !grep { $_ eq $row->{stage} } @stages);
	next if (@branches && !grep { $_ eq $row->{branch} } @branches);
	next if $skipok && $row->{current_stage} eq 'OK';
	$row->{build_flags} =~ s/^\{(.*)\}$/$1/ if $row->{build_flags};
	$row->{build_flags} =~ s/,/ /g          if $row->{build_flags};

	# enable-integer-datetimes is now the default
	if ($row->{branch} eq 'HEAD' || $row->{branch} gt 'REL8_3_STABLE')
	{
		$row->{build_flags} .= " --enable-integer-datetimes "
		  unless ($row->{build_flags}
			&& $row->{build_flags} =~ /--(en|dis)able-integer-datetimes/);
	}

	# enable-thread-safety is now the default
	if ($row->{branch} eq 'HEAD' || $row->{branch} gt 'REL8_5_STABLE')
	{
		$row->{build_flags} .= " --enable-thread-safety "
		  unless ($row->{build_flags}
			&& $row->{build_flags} =~ /--(en|dis)able-thread-safety/);
	}
	$row->{build_flags} =~ s/--((enable|with)-)?//g;
	$row->{build_flags} =~ s/libxml/xml/;
	$row->{build_flags} =~ s/tap_tests/tap-tests/;
	$row->{build_flags} =~ s/\S+=\S+//g;

	$fetch_personality->execute($row->{sysname},$row->{report_time});
	my @personality = $fetch_personality->fetchrow_array();
	if (@personality)
	{
		$row->{os_version} = $personality[0];
		$row->{compiler_version} = $personality[1];
	}

	push(@$statrows, $row);
}
$sth->finish;

$db->disconnect;

my $template_opts = { INCLUDE_PATH => $template_dir };
my $template      = Template->new($template_opts);

if ($lastmodhead)
{
	$lastmodhead = "Last-Modified: $lastmodhead\n";
}
else
{
	$lastmodhead = "";
}

print "Content-Type: text/html\n$lastmodhead\n";


$template->process(
	'fstatus.tt',
	{
		statrows     => $statrows,
		lastmodhead  => $lastmodhead,
		sortby       => $sortby,
		max_days     => $max_days,
		all_branches => $all_branches,
		all_members  => $all_members,
		all_stages   => $all_stages,
		qmembers     => \@members,
		qbranches    => \@branches,
		qstages      => \@stages
	}
);

exit;

