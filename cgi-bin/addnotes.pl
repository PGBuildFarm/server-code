#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use CGI;
use Digest::SHA qw(sha1_hex);
use MIME::Base64;
use DBI;
use DBD::Pg;
use Data::Dumper;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);

my $query = CGI->new;

my $sig = $query->path_info;
$sig =~ s!^/!!;

my $animal   = $query->param('animal');
my $sysnotes = $query->param('sysnotes');

my $content = "animal=$animal&sysnotes=$sysnotes";

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

unless ($animal && defined($sysnotes) && $sig)
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

# undo escape-proofing of base64 data and decode it
do { tr/$@/+=/; $_ = decode_base64($_); }
  for ($sysnotes);

my $set_notes = q{

    update buildsystems
    set sys_notes = nullif($2,''),
    sys_notes_ts = case
                      when coalesce($2,'') <> '' then now()
                      else null
                   end
    where name = $1
          and status = 'approved'

};

$sth = $db->prepare($set_notes);
my $rv = $sth->execute($animal, $sysnotes);
unless ($rv)
{
	print "Status: 460 old data fetch\nContent-Type: text/plain\n\n";
	print "error: ", $db->errstr, "\n";
	$db->disconnect;
	exit;
}

$sth->finish;

$db->disconnect;

print "Content-Type: text/plain\n\n";
print "request was on:\n$content\n";

