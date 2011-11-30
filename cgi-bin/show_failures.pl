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

my $query = new CGI;
my @members = $query->param('member');
map { s/[^a-zA-Z0-9_ -]//g; } @members;
my $max_days =  $query->param('max_days') + 0 || 10;

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
	$presort_clause = "lower(b.sysname), b.snapshot desc,"
}

my $db = DBI->connect($dsn,$dbuser,$dbpass,{pg_expand_array => 0}) 
    or die("$dsn,$dbuser,$dbpass,$!");

my $statement =<<EOS;


  select timezone('GMT'::text, 
	now())::timestamp(0) without time zone - b.snapshot AS when_ago, 
	b.*,
	d.stage as current_stage
  from nrecent_failures_db_data b
	left join  dashboard_mat d
		on (d.sysname = b.sysname and d.branch = b.branch)
  where (now()::timestamp(0) without time zone - b.snapshot) < (? * interval '1 day')
  order by $presort_clause 
        b.branch = 'HEAD' desc,
        b.branch desc, 
        $sort_clause 
        b.snapshot desc

EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute($max_days);
while (my $row = $sth->fetchrow_hashref)
{
    next if (@members && ! grep {$_ eq $row->{sysname} } @members);
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
    $row->{build_flags}  =~ s/\S+=\S+//g;
    push(@$statrows,$row);
}
$sth->finish;


$db->disconnect;


my $template_opts = { INCLUDE_PATH => $template_dir };
my $template = new Template($template_opts);

print "Content-Type: text/html\n\n";

$template->process('fstatus.tt',
		{statrows=>$statrows, 
		 sortby => $sortby,
		 max_days => $max_days,
		 members=> \@members} );

exit;

