#!/usr/bin/perl

use strict;


use vars qw($dbhost $dbname $dbuser $dbpass $dbport);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

use lib "/home/community/pgbuildfarm/lib/lib/perl5/site_perl";

use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to('PGBuildFarm')->handle;

exit;

package PGBuildFarm;

use DBI;

sub get_status

{
    my $class = shift;
    my @members = @_;

    my $dsn="dbi:Pg:dbname=$::dbname";
    $dsn .= ";host=$::dbhost" if $::dbhost;
    $dsn .= ";port=$::dbport" if $::dbport;

    my $db = DBI->connect($dsn,$::dbuser,$::dbpass) or 
	die("$dsn,$::dbuser,$::dbpass,$!");

    # there is possibly some redundancy in this query, but it makes
    # a lot of the processing simpler.

    my $statement =<<EOS;


    select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago,
      	sysname, snapshot, b.status, stage, branch, build_flags,
      	operating_system, coalesce(b.os_version,s.os_version) as os_version,
      	compiler, 
        coalesce(b.compiler_version, s.compiler_version) as compiler_version, 
	architecture 
    from buildsystems s, 
        (
	select distinct on (bs.sysname, bs.branch, bs.report_time) 
               sysname, snapshot, status, stage, branch, build_flags,
               report_time ,compiler_version, os_version
        from build_status bs
             left join 
             personality p
             on (p.name = bs.sysname and p.effective_date <= bs.report_time)
        order by bs.sysname, bs.branch, bs.report_time, 
                 p.effective_date is null, p.effective_date desc
        ) as b
	natural join 
       	(select sysname, branch, max(snapshot) as snapshot
        from build_status
        group by sysname, branch
    	having max(snapshot) > now() - '30 days'::interval
       	) m
    where name = sysname
        and s.status = 'approved'
    order by branch = 'HEAD' desc, 
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
	$row->{build_flags}  =~ s/^\{(.*)\}$/$1/;
	$row->{build_flags}  =~ s/,/ /g;
	$row->{build_flags}  =~ s/--((enable|with)-)?//g;
	$row->{build_flags}  =~ s/\S+=\S+//g;
	push(@$statrows,$row);
    }
    $sth->finish;


    $db->disconnect;

    return $statrows;

}

1;





