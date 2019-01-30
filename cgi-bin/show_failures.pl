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
my@stages;
if ($CGI::VERSION < 4.08)
{
    @members = grep {$_ ne "" } $query->param('member');
    @branches = grep {$_ ne "" } $query->param('branch');
    @stages = grep {$_ ne "" } $query->param('stage');
}
else
{
    @members = grep {$_ ne "" } $query->multi_param('member');
    @branches = grep {$_ ne "" } $query->multi_param('branch');
    @stages = grep {$_ ne "" } $query->multi_param('stage');
}
do { s/[^a-zA-Z0-9_ -]//g; } foreach @branches;
do { s/[^a-zA-Z0-9_ -]//g; } foreach @members;
do { s/[^a-zA-Z0-9_ :-]//g; } foreach @stages;
my $qmdays = $query->param('max_days');
my $max_days =  $qmdays ? $qmdays + 0 : 10;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $sort_clause = "";
my $presort_clause = "";
my $sortby = $query->param('sortby') || 'nosort';
if ($sortby eq 'name')
{
    $sort_clause = 'lower(b.sysname),';
}
elsif ($sortby eq 'namenobranch')
{
    $presort_clause = "lower(b.sysname), b.snapshot desc,";
}

my $db = DBI->connect($dsn,$dbuser,$dbpass,{pg_expand_array => 0})
  or die("$dsn,$dbuser,$dbpass,$!");

# If the dashboard hasn't been updated then the failures can't have been either
# so we use the same test for both. That saves keeping a separate update date
# for failures.

my $ifmodsince = $query->http('If-Modified-Since') || 'Thu, 01 Jan 1970 00:00:00 GMT';

my ($lastmod, $lastmodhead, $nomodsince) =
  $db->selectrow_array("select ts at time zone 'UTC',
                        to_char(ts,'Dy, DD Mon YYYY HH24:MI:SS GMT'),
                        ts <= to_timestamp('$ifmodsince','Dy, DD Mon YYYY HH24:MI:SS GMT')
                        from dashboard_last_modified");

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
unshift(@$all_branches,'HEAD');

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

};

my $all_stages = $db->selectcol_arrayref($get_all_stages);

my $statement =<<"EOS";


  select timezone('GMT'::text,
	now())::timestamp(0) without time zone - b.snapshot AS when_ago,
	b.*,
	d.stage as current_stage
  from nrecent_failures_db_data b
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

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute($max_days);
while (my $row = $sth->fetchrow_hashref)
{
    next if (@members && !grep {$_ eq $row->{sysname} } @members);
    next if (@stages && !grep {$_ eq $row->{stage} } @stages);
    next if (@branches && !grep {$_ eq $row->{branch} } @branches);
    $row->{build_flags}  =~ s/^\{(.*)\}$/$1/;
    $row->{build_flags}  =~ s/,/ /g;

    # enable-integer-datetimes is now the default
    if ($row->{branch} eq 'HEAD' || $row->{branch} gt 'REL8_3_STABLE')
    {
        $row->{build_flags} .= " --enable-integer-datetimes "
          unless ($row->{build_flags} =~ /--(en|dis)able-integer-datetimes/);
    }

    # enable-thread-safety is now the default
    if ($row->{branch} eq 'HEAD' || $row->{branch} gt 'REL8_5_STABLE')
    {
        $row->{build_flags} .= " --enable-thread-safety "
          unless ($row->{build_flags} =~ /--(en|dis)able-thread-safety/);
    }
    $row->{build_flags}  =~ s/--((enable|with)-)?//g;
    $row->{build_flags} =~ s/libxml/xml/;
	$row->{build_flags} =~ s/tap_tests/tap-tests/;
    $row->{build_flags}  =~ s/\S+=\S+//g;
    push(@$statrows,$row);
}
$sth->finish;

$db->disconnect;

my $template_opts = { INCLUDE_PATH => $template_dir };
my $template = Template->new($template_opts);

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
        statrows=>$statrows,
		lastmodhead => $lastmodhead,
        sortby => $sortby,
        max_days => $max_days,
        all_branches => $all_branches,
        all_members => $all_members,
        all_stages => $all_stages,
        qmembers=> \@members,
        qbranches => \@branches,
        qstages => \@stages
    }
);

exit;

