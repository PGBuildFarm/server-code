#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut 

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

my $systemdata = q{
    select operating_system, os_version, compiler, compiler_version, architecture,
      owner_email, sys_notes_ts::date AS sys_notes_date, sys_notes
    from buildsystems b
    where b.status = 'approved'
        and name = ?
};

my $statement = qq{
   with x as 
   (  select * 
      from build_status_recent_500
      where sysname = ? 
         and branch = ?
   ) 
   select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago, 
            sysname, snapshot, status, stage 
   from x 
   order by snapshot desc  
   limit $hm
}
;

my $sth = $db->prepare($systemdata);
$sth->execute($member);
my $sysrow = $sth->fetchrow_hashref;
my $statrows=[];
$sth=$db->prepare($statement);
$sth->execute($member,$branch);
while (my $row = $sth->fetchrow_hashref)
{
    last unless $sysrow;
    while (my($k,$v) = each %$sysrow) { $row->{$k} = $v; }
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
