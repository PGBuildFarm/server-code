#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut 

use strict;
use DBI;
use CGI;

my $query = new CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $dbh = DBI->connect($dsn,$dbuser,$dbpass) or die("$dsn,$dbuser,$dbpass,$!");

my %words;

my $sql = q{
    with snaps as (
    select sysname, max(snapshot) as snapshot 
    from build_status_log 
    where branch = 'HEAD' and 
        log_stage = 'typedefs.log' and 
        snapshot > current_date::timestamp - interval '30 days' 
    group by sysname
    )
    select snaps.sysname, snaps.snapshot , length(regexp_replace(log_text,'.','g')) as lines_found 
    from build_status_log l
       join snaps
          on snaps.sysname = l.sysname and snaps.snapshot = l.snapshot
    where log_stage = 'typedefs.log'  and log_text !~ $$\Wstring\W$$
};
my $builds = $dbh->selectall_arrayref($sql, { Slice => {} });


if ($query->param('show_list'))
{
    print "Content-Type: text/html\n\n",
    "<head><title>Typedefs URLs</title></head>\n",
    "<body><h1>Typdefs URLs</h1>\n",
    "<table border='1'><tr><th>member</th><th>lines</th></tr>\n";

    foreach my $build (@$builds)
    {
	print "<tr><td><a href='http://www.pgbuildfarm.org/cgi-bin/show_stage_log.pl?nm=$build->{sysname}\&amp;dt=$build->{snapshot}\&amp;stg=typedefs'>$build->{sysname}</a></td><td>$build->{lines_found}</td></tr>\n";
    }
    print "</table></body></html>\n";
    exit;
}

$sql = q{
   select log_text
   from build_status_log
   where sysname = ?
     and snapshot = ?
     and log_stage = 'typedefs.log'
     and branch = 'HEAD'
 };

my $sth = $dbh->prepare($sql);

foreach my $build (@$builds)
{
    $sth->execute($build->{sysname},$build->{snapshot});
    my @row = $sth->fetchrow;
    my @typedefs = split(/\s+/,$row[0]);
    @words{@typedefs} = 1 x @typedefs;
}

print "Content-Type: text/plain\n\n",
    join("\n",sort keys %words),
    "\n";
