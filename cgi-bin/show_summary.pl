#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use lib "$ENV{BFCONFDIR}/perl5";
use BFUtils;

use DBI;
use Template;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir
  $email_only);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn, $dbuser, $dbpass, { pg_expand_array => 0 })
  or die("$dsn,$dbuser,$dbpass,$!");

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

my $template_opts = { INCLUDE_PATH => $template_dir };
my $template = Template->new($template_opts);

print "Content-Type: text/html\n\n";

$template->process('summary.tt',
	{ summrows => $rows });

exit;






