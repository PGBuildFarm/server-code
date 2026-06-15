#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

BEGIN
{
	$ENV{BFConfDir} ||= $ENV{BFCONFDIR};
	$ENV{BFCONFDIR} ||= $ENV{BFConfDir};
}
use lib "$ENV{BFConfDir}/perl5";
use BFUtils;

use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir
  $ignore_branches_of_interest $email_only);

setup_die_handler();

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

my $query = CGI->new;
my @members;
if ($CGI::VERSION < 4.08)
{
	@members = $query->param('member');
}
else
{
	@members = $query->multi_param('member');
}

do { s/[^a-zA-Z0-9_ -]//g; }
  foreach @members;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $sort_clause = "";
my $sortby      = $query->param('sortby') || 'nosort';
if ($sortby eq 'name')
{
	$sort_clause = 'lower(sysname),';
}
elsif ($sortby eq 'os')
{
	$sort_clause = 'lower(s.operating_system), s.os_version desc,';
}
elsif ($sortby eq 'compiler')
{
	$sort_clause = "lower(s.compiler), s.compiler_version,";
}

my $owner = $query->param('owner');

my $db = DBI->connect($dsn, $dbuser, $dbpass, { pg_expand_array => 0 })
  or die "database connection failed: $DBI::errstr";

my $ifmodsince =
  $query->http('If-Modified-Since') || 'Thu, 01 Jan 1970 00:00:00 GMT';

my ($lastmod, $lastmodhead, $nomodsince) = $db->selectrow_array(
	"select ts at time zone 'UTC',
                        to_char(ts,'Dy, DD Mon YYYY HH24:MI:SS GMT'),
                        ts <= to_timestamp(? ,'Dy, DD Mon YYYY HH24:MI:SS GMT')
                        from dashboard_last_modified",
	undef, $ifmodsince
);

if ($lastmod && $nomodsince)
{
	print "Status: 304 Not Modified\n\n";
	exit;
}

my @branches_of_interest;
if (!$ignore_branches_of_interest)
{
	my $brhandle;
	open($brhandle, "<", "../htdocs/branches_of_interest.txt")
	  || die "opening branches_of_interest.txt: $!";
	@branches_of_interest = <$brhandle>;
	close($brhandle);
	open($brhandle, "<", "../htdocs/old_branches_of_interest.txt")
	  || die "opening old_branches_of_interest.txt: $!";
	my @old_branches_of_interest = <$brhandle>;
	close($brhandle);
	push(@branches_of_interest, @old_branches_of_interest);
	chomp(@branches_of_interest);
}

my $statement = qq[


  select timezone('GMT'::text, now())::timestamp(0) without time zone
     - b.snapshot AS when_ago,
     b.*
  from dashboard_mat b
        join buildsystems s
           on s.name = b.sysname
              and case
                     when \$1 ::text is null
                       then true
                     else
                       s.owner_email = \$1
                  end
  order by branch = 'HEAD' desc,
        branch COLLATE "C" desc, $sort_clause
       report_time desc
]
  ;

my $statrows = [];
my $sth      = $db->prepare($statement);
$sth->bind_param(1, $owner);
$sth->execute();
while (my $row = $sth->fetchrow_hashref)
{
	next if (@members && !grep { $_ eq $row->{sysname} } @members);
	next
	  if (@branches_of_interest
		&& !(grep { $_ eq $row->{branch} } @branches_of_interest));

	$row->{build_flags} =
	  normalize_build_flags($row->{branch}, $row->{build_flags});
	$row->{branch} =~ s/^HEAD$/master/;
	push(@$statrows, $row);
}
$sth->finish;

$db->disconnect;

my $template_opts =
  { INCLUDE_PATH => $template_dir, VARIABLES => { livery => livery() } };
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

$template->process('status.tt',
	{ statrows => $statrows, lastmodhead => $lastmodhead });

exit;

