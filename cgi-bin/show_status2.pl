#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $query = new CGI;
my @members = $query->param('member');

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn,$dbuser,$dbpass) or die("$dsn,$dbuser,$dbpass,$!");

# there is possibly some redundancy in this query, but it makes
# a lot of the processing simpler.

my $statement = <<EOS;

  select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago,
      sysname, snapshot, b.status, stage, branch,
      operating_system, os_version, compiler, compiler_version, architecture 
  from buildsystems s, 
       build_status b natural join 
       (select sysname, branch, max(snapshot) as snapshot
        from build_status
        group by sysname, branch
	having max(snapshot) > now() - '30 days'::interval
       ) m
  where name = sysname
        and s.status = 'approved'
  order by case when branch = 'HEAD' then 0 else 1 end, 
        branch desc, 
        snapshot desc

EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute;
while (my $row = $sth->fetchrow_hashref)
{
    next if (@members && ! grep {$_ eq $row->{sysname} } @members);
    push(@$statrows,$row);
}
$sth->finish;


$db->disconnect;

my $template = new Template({INCLUDE_PATH=>"/home/community/pgbuildfarm/templates"});

print "Content-Type: text/html\n\n";

$template->process("dyn/status.tt",{statrows=>$statrows});

