#!/usr/bin/perl

=comment

Copyright (c) 2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use CGI;
use Digest::SHA qw(sha1_hex);
use MIME::Base64;
use DBI;
use DBD::Pg;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);

my $query = CGI->new;

my $sig = $query->path_info;
$sig =~ s!^/!!;

my $animal = $query->param('animal');
my $ts     = $query->param('ts');
my $op     = $query->param('op') || "";

# clean inputs
$ts =~ tr /0-9//cd;
$animal =~ tr /a-zA-Z0-9_ -//cd;
$op =~ tr /a-z//cd;

my $content = "animal=$animal&ts=$ts";
$content = "$content&op=$op" if $op;

$op ||= "disable";

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

unless ($animal
	&& $ts
	&& $sig)
{
	print
	  "Status: 490 bad parameters\nContent-Type: text/plain\n\n",
	  "bad parameters for request\n";
	exit;
}

my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my $gethost =
  "select secret from buildsystems where name = ? and status = 'approved'";
my $sth = $db->prepare($gethost);
$sth->execute($animal);
my ($secret) = $sth->fetchrow_array();
$sth->finish;

unless ($secret)
{
	print
	  "Status: 495 Unknown System\nContent-Type: text/plain\n\n",
	  "System $animal is unknown\n";
	$db->disconnect;
	exit;
}

my $calc_sig = sha1_hex($content, $secret);

if ($calc_sig ne $sig)
{
	print "Status: 450 sig mismatch\nContent-Type: text/plain\n\n";
	print "$sig mismatches $calc_sig on content:\n$content";
	$db->disconnect;
	exit;
}

if ($op eq 'disable')
{

	my $clear_sth = $db->prepare(
		q[

  DELETE FROM alerts
  WHERE sysname = ?
		      ]
	);


	my $rv = $clear_sth->execute($animal);
	unless ($rv)
	{
		print "Status: 470 clearing alerts\nContent-Type: text/plain\n\n";
		print "error: ", $db->errstr, "\n";
		$db->disconnect;
		exit;
	}

	my $disable_sth = $db->prepare(
		q[
       update buildsystems set no_alerts = true where name = ?
    ]
	);
	$rv = $disable_sth->execute($animal);
	unless ($rv)
	{
		print "Status: 470 disabling alerts\nContent-Type: text/plain\n\n";
		print "error: ", $db->errstr, "\n";
		$db->disconnect;
		exit;
	}

	print "Content-Type: text/plain\n\n";
	print "alerts cleared for $animal\n";
}
elsif ($op eq 'enable')
{
	my $enable_sth = $db->prepare(
		q[
       update buildsystems set no_alerts = false where name = ?
    ]
	);
	my $rv = $enable_sth->execute($animal);
	unless ($rv)
	{
		print "Status: 470 enabling alerts\nContent-Type: text/plain\n\n";
		print "error: ", $db->errstr, "\n";
		$db->disconnect;
		exit;
	}

	print "Content-Type: text/plain\n\n";
	print "alerts enabled for $animal\n";

}
else
{
	print "Status: 470 invalid op\nContent-Type: text/plain\n\n";
	print "invalid op: $op\n";

}

$db->disconnect;


