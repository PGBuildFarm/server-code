#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";
#require "BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn,$dbuser,$dbpass);

die $DBI::errstr unless $db;

my $query = new CGI;
my $member = $query->param('nm'); $member =~ s/[^a-zA-Z0-9_ -]//g;
my $branch = $query->param('br'); $branch =~ s/[^a-zA-Z0-9_ -]//g;
my $hm = $query->param('hm');  $hm =~ s/[^a-zA-Z0-9_ -]//g;
$hm = '240' unless $hm =~ /^\d+$/;

my $latest_personality = $db->selectrow_arrayref(q{
            select os_version, compiler_version
            from personality
            where name = ?
            order by effective_date desc limit 1
	}, undef, $member);

# we don't really need to do this join, since we only want
# one row from buildsystems. but it means we only have to run one
# query. If it gets heavy we'll split it up and run two

my $statement = <<EOS;

  select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago,
      sysname, snapshot, b.status, stage,
      operating_system, os_version, compiler, compiler_version, architecture,
      owner_email
  from buildsystems s, 
       build_status b 
  where name = ?
        and branch = ?
        and s.status = 'approved'
        and name = sysname
  order by snapshot desc
  limit $hm

EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute($member,$branch);
while (my $row = $sth->fetchrow_hashref)
{
    $row->{owner_email} =~ s/\@/ [ a t ] /;
    if ($latest_personality)
    {
	$row->{os_version} = $latest_personality->[0];
	$row->{compiler_version} = $latest_personality->[1];
    }
    push(@$statrows,$row);
}

$sth->finish;

$db->disconnect;

my $template_opts = { INCLUDE_PATH => $template_dir, EVAL_PERL => 1 };
my $template = new Template($template_opts);

print "Content-Type: text/html\n\n";

$template->process('history.tt',
		   {statrows=>$statrows, 
		    branch=>$branch, 
		    member => $member,
		    hm => $hm
		    });

exit;
