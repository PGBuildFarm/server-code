#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

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

#require "BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my $query  = CGI->new;
my $member = $query->param('nm');
$member =~ s/[^a-zA-Z0-9_ -]//g if $member;
my $branch = $query->param('br');
$branch =~ s{[^a-zA-Z0-9_/ -]}{}g if $branch;
$branch =~ s/^master$/HEAD/ if $branch;
my $hm = $query->param('hm');
if ($hm)
{
	$hm =~ s/[^a-zA-Z0-9_ -]//g;
	$hm = '240' unless $hm =~ /^\d+$/;
}
else
{
	$hm = '99999';
}

my $latest_personality = $db->selectrow_arrayref(
	q{
            select os_version, compiler_version
            from personality
            where name = ?
            order by effective_date desc limit 1
	}, undef, $member
);

my $systemdata = q{
    select operating_system, os_version, compiler, compiler_version,
      architecture, owner_email, sys_notes_ts::date AS sys_notes_date,
      sys_notes
    from buildsystems b
    where true -- and b.status = 'approved'
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
            sysname, snapshot, status, stage,
            coalesce(script_version,'') as script_version,
            git_head_ref,
            run_secs * interval '1 second' as run_time
   from x
   order by snapshot desc
   limit $hm
}
  ;

my $other_branches_query = q{
            select branch from (
                select distinct branch
                from build_status_recent_500
                where sysname = ?
                      and branch <> ?
                      and snapshot > now() at time zone 'GMT'
                                     - interval '30 days'
                 ) q
                 order by branch <> 'HEAD', branch COLLATE "C" desc
};

my $other_branches =
  $db->selectcol_arrayref($other_branches_query, undef, $member, $branch);

my $sth = $db->prepare($systemdata);
$sth->execute($member);
my $sysrow   = $sth->fetchrow_hashref;
my $statrows = [];
$sth = $db->prepare($statement);
$sth->execute($member, $branch);
while (my $row = $sth->fetchrow_hashref)
{
	last unless $sysrow;
	while (my ($k, $v) = each %$sysrow) { $row->{$k} = $v; }
	$row->{owner_email} =~ s/\@/ [ a t ] /;
	if ($latest_personality)
	{
		$row->{os_version}       = $latest_personality->[0];
		$row->{compiler_version} = $latest_personality->[1];
	}
	$row->{script_version} =~ s/^(\d{3})0(\d{2})/$1.$2/;
	$row->{script_version} =~ s/^0+//;
	push(@$statrows, $row);
}

$sth->finish;

$db->disconnect;

$branch =~ s/^HEAD$/master/;
s/^HEAD$/master/ foreach @$other_branches;

my $template_opts = { INCLUDE_PATH => $template_dir, EVAL_PERL => 1 };
my $template = Template->new($template_opts);

print "Content-Type: text/html\n\n";

$template->process(
	'history.tt',
	{
		statrows       => $statrows,
		branch         => $branch,
		member         => $member,
		hm             => $hm,
		other_branches => $other_branches,
	}
);

exit;
