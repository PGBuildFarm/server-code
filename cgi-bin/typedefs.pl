#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut 

use strict;
use DBI;
use CGI;
use Data::Dumper;


my $query = new CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my %params=$query->Vars;
my $show_list = $params{show_list};
$show_list = 1 if exists $params{keywords} && $params{keywords} =~ /show_list/;
my $branch = $query->param('branch'); $branch =~ s/[^a-zA-Z0-9_ -]//g if $branch;

if (!$branch || $branch eq 'master')
{
    $branch='HEAD';
}
elsif ($branch eq 'ALL')
{
    $branch = undef;
}
    

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $dbh = DBI->connect($dsn,$dbuser,$dbpass) or die("$dsn,$dbuser,$dbpass,$!");

my %words;

my $sql = q{
    with snaps as (
    select sysname, branch, max(snapshot) as snapshot 
    from build_status_log 
    where log_stage = 'typedefs.log' and 
        snapshot > current_date::timestamp - interval '30 days' 
    group by sysname, branch
    )
    select snaps.sysname, snaps.branch, snaps.snapshot , length(regexp_replace(log_text,'.','g')) as lines_found 
    from build_status_log l
       join snaps
          on snaps.sysname = l.sysname and snaps.snapshot = l.snapshot
    where log_stage = 'typedefs.log'  and log_text !~ $$\Wstring\W$$
    order by sysname, branch
};
my $builds = $dbh->selectall_arrayref($sql, { Slice => {} });
my %branches;
foreach my $build (@$builds) { $branches{$build->{branch}} = 1; }


if (defined $show_list)
{
    print "Content-Type: text/html\n\n",
    "<head><title>Typedefs URLs</title></head>\n",
    "<body><h1>Typdefs URLs</h1>\n",
    "<table border='1'><tr><th>Branch List</th></tr>\n";

    print "<tr><td><a href='/cgi-bin/typedefs.pl?branch=ALL'>ALL</a></td></tr>\n";
    foreach my $br (sort keys %branches) 
    {
	print "<tr><td><a href='/cgi-bin/typedefs.pl?branch=$br'>$br</a></td></tr>\n";
    }
    print "</table>\n",

#    "<pre>",Dumper(\%params),"</pre>",
    "<table border='1'><tr><th>member</th><th>Branch</th><th>lines</th></tr>\n";

    foreach my $build (@$builds)
    {
	print "<tr><td><a href='http://www.pgbuildfarm.org/cgi-bin/show_stage_log.pl?nm=$build->{sysname}\&amp;dt=$build->{snapshot}\&amp;stg=typedefs'>$build->{sysname}</a></td>
                   <td>$build->{branch}</td><td>$build->{lines_found}</td></tr>\n";
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
     and branch = ?
 };

my $sth = $dbh->prepare($sql);

foreach my $build (@$builds)
{
    next if $branch && $build->{branch} ne $branch;
    $sth->execute($build->{sysname},$build->{snapshot}, $build->{branch});
    my @row = $sth->fetchrow;
    my @typedefs = split(/\s+/,$row[0]);
    @words{@typedefs} = 1 x @typedefs;
}

print "Content-Type: text/plain\n\n",
#  Dumper(\%params),
    join("\n",sort keys %words),
    "\n";
