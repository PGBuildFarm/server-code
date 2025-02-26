#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use lib "$ENV{BFCONFDIR}/perl5";
use BFUtils;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $email_only);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to('PGBuildFarm')->handle;

exit;

## no critic (ControlStructures::ProhibitUnreachableCode)

package PGBuildFarm;

use DBI;

sub get_status

{
	my $class   = shift;
	my @members = @_;

	my $dsn = "dbi:Pg:dbname=$::dbname";
	$dsn .= ";host=$::dbhost" if $::dbhost;
	$dsn .= ";port=$::dbport" if $::dbport;

	my $db = DBI->connect($dsn, $::dbuser, $::dbpass)
	  or die("$dsn,$::dbuser,$::dbpass,$!");

	# there is possibly some redundancy in this query, but it makes
	# a lot of the processing simpler.

	my $statement = <<"EOS";


    select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago,
       dsh.*
    from dashboard_mat dsh
    order by branch = 'HEAD' desc,
        branch COLLATE "C" desc,
        snapshot desc



EOS

	my $statrows = [];
	my $sth      = $db->prepare($statement);
	$sth->execute;
	while (my $row = $sth->fetchrow_hashref)
	{
		next if (@members && !grep { $_ eq $row->{sysname} } @members);
		if ($row->{build_flags})
		{
			$row->{build_flags} =~ s/^\{(.*)\}$/$1/;
			$row->{build_flags} =~ s/,/ /g;
			$row->{build_flags} =~ s/--((enable|with)-)?//g;
			$row->{build_flags} =~ s/\S+=\S+//g;
		}
		push(@$statrows, $row);
	}
	$sth->finish;

	$db->disconnect;

	return $statrows;

}

1;

