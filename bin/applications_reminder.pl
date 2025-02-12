#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut 

use strict;
use warnings;

use DBI;
use DBD::Pg;
use Mail::Send;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport_bin
  $default_host $reminders_from $notifyapp);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

# don't use configged dbuser/dbpass

$dbuser = "";
$dbpass = "";

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport_bin" if $dbport_bin;

my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my $rows = $db->selectall_arrayref("SELECT * FROM pending()", { Slice => {} });

$db->disconnect;

exit unless $rows && @$rows;

my $me = `id -un`;
chomp $me;
my $host = `hostname`;
chomp($host);
$host = $default_host unless ($host =~ m/[.]/ || !defined($default_host));

my $from_addr = "PG Build Farm <$me\@$host>";
$from_addr =~ tr /\r\n//d;

$from_addr = $reminders_from if $reminders_from;

my $msg = Mail::Send->new;
$msg->set('From', $from_addr);
$msg->to(@$notifyapp);
$msg->set('Reply-To',                 @$notifyapp);
$msg->set('Auto-Submitted',           'auto-generated');
$msg->set('X-Auto-Response-Suppress', 'all');
$msg->subject("PGBuildfarm pending applications reminder");
my $fh = $msg->open("sendmail", "-f $from_addr");

print $fh "\nOutstanding buildfarm application(s) still pending: \n\n";
foreach my $row (@$rows)
{
	printf $fh
	  "%s(%s) - %s(%s) on %s\n - compiler: %s v%s\n - pending since: %s\n\n",
	  $row->{'owner'},
	  $row->{'owner_email'},
	  $row->{'operating_system'},
	  $row->{'os_version'},
	  $row->{'architecture'},
	  $row->{'compiler'},
	  $row->{'compiler_version'},
	  $row->{'status_ts'};
}
$fh->close;


