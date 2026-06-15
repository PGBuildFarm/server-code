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

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir
  $email_only);

setup_die_handler();

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn, $dbuser, $dbpass, { pg_expand_array => 0 })
  or die "database connection failed: $DBI::errstr";

my $query = q(

select g.branch,
       g.git_commit_ref,
       g.git_commit_ts at time zone 'UTC' as git_commit_ts,
       g.git_commit_header,
       count(*) as builds,
       count(*) filter (where stage = 'OK') as successes
from branch_git_tip g
     join build_status_recent_500 s
        on g.branch = s.branch
           and g.git_commit_ref = substr(s.git_head_ref,1,11)
where snapshot > now() - interval '90 days'
group by g.branch, g.git_commit_ref, g.git_commit_ts, g.git_commit_header
order by g.branch = 'HEAD' desc,
         g.branch COLLATE "C" desc;
  );

my $rows = [];
my $sth  = $db->prepare($query);
$sth->execute();
while (my $row = $sth->fetchrow_hashref)
{
	$row->{branch} =~ s/HEAD/master/;
	push(@$rows, $row);
}
$sth->finish;
$db->disconnect;

my $template_opts =
  { INCLUDE_PATH => $template_dir, VARIABLES => { livery => livery() } };
my $template = Template->new($template_opts);

print "Content-Type: text/html\n\n";

$template->process('summary.tt',
	{ summrows => $rows });

exit;






