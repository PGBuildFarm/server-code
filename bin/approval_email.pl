#!/usr/bin/perl

=comment

Copyright (c) 2003-2026, Andrew Dunstan

See accompanying License file for license details

Given the name of an already-approved buildfarm animal, fetch its secret
(set at registration -- see register.pl -- and never regenerated here) via
psql.

By default, whether the secret is encrypted is decided by the active
livery's encrypt_secrets setting in BuildFarmWeb.pl (on for the security
livery, off for the plain build farm) -- --encrypt/--no-encrypt overrides
that.

When encrypting, a random key is generated and a block containing both the
animal name and the secret is PGP-encrypted as one armored message via the
real gpg CLI. The ready-to-send email body (armored message plus decrypt
instructions, but NOT the key) goes to stdout, and the key itself goes to
stderr, so the two can be handled/sent separately -- e.g.

    bin/approval_email.pl gharial > email.txt

leaves the key on the terminal and the body in email.txt. The recipient
decrypts with the standard gpg CLI, no database access needed:

    gpg --batch --passphrase 'THE_KEY' -d message.asc

When not encrypting, the animal name and secret are included in the email
body in the clear and nothing is printed to stderr.

With --send (-s), the email body is mailed directly to the animal owner's
registered address instead of being printed to stdout; an encryption key
(if any) is still only ever printed to stderr, never mailed, so it must
still be delivered to the owner through a separate channel.

=cut

use strict;
use warnings;

use Crypt::URandom qw(urandom);
use File::Temp qw(tempfile);
use Getopt::Long;
use Mail::Send;

BEGIN
{
	$ENV{BFConfDir} ||= $ENV{BFCONFDIR};
	$ENV{BFCONFDIR} ||= $ENV{BFConfDir};
}
use lib "$ENV{BFConfDir}/perl5";
use BFUtils;

use vars qw($dbhost $dbname $dbport_bin
  $default_host $register_from $skip_mail);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;

my $lv = livery();

my $send    = 0;
my $encrypt = $lv->{encrypt_secrets};
GetOptions(
	'send|s'   => \$send,
	'encrypt!' => \$encrypt,
  )
  or die "usage: $0 [--send] [--[no-]encrypt] animal_name\n";

my $name = shift @ARGV
  or die "usage: $0 [--send] [--[no-]encrypt] animal_name\n";

$ENV{PGDATABASE} = $dbname;
$ENV{PGHOST}      = $dbhost      if $dbhost;
$ENV{PGPORT}      = $dbport_bin  if $dbport_bin;

# fetch via psql rather than DBI; the animal name is passed as a bound
# psql variable (:'name'), not interpolated into the SQL text, and the
# whole command is run without a shell, so $name can't reach either the
# SQL parser or the OS shell unescaped. -f (not -c) is required for psql
# to actually perform :'name' substitution.
my ($q_fh, $q_name) = tempfile(UNLINK => 1);
print $q_fh
  q{select secret, sys_owner, owner_email, operating_system, os_version,
           compiler, compiler_version, architecture
      from buildsystems where name = :'name';};
close $q_fh;

my @cmd = (
	'psql', '-X', '-A', '-t', '-F', "\t",
	'-v', "name=$name",
	'-f', $q_name);

open(my $fh, '-|', @cmd) or die "can't run psql: $!";
my $line = <$fh>;
close($fh) or die "psql failed: $?";

die "no such animal: $name\n" unless defined $line;
chomp $line;
my (
	$secret, $owner, $owner_email,
	$os, $osv, $comp, $compv, $arch
) = split(/\t/, $line, 8);
die "no such animal: $name\n"
  unless defined $secret && defined $owner && defined $owner_email;

my $secret_section;

if ($encrypt)
{
	my $key = unpack("h*", urandom(32));

	my ($pt_fh, $pt_name) = tempfile(UNLINK => 1);
	chmod 0600, $pt_name;
	print $pt_fh "Animal name: $name\nSecret: $secret\n";
	close $pt_fh;

	my ($pf_fh, $pf_name) = tempfile(UNLINK => 1);
	chmod 0600, $pf_name;
	print $pf_fh $key;
	close $pf_fh;

	my (undef, $ct_name) = tempfile(UNLINK => 1);

	system(
		'gpg', '--batch', '--yes', '--symmetric', '--armor',
		'--pinentry-mode',   'loopback',
		'--passphrase-file', $pf_name,
		'-o', $ct_name, $pt_name) == 0
	  or die "gpg encryption failed: $?";

	open(my $ct_fh, '<', $ct_name) or die "can't read $ct_name: $!";
	my $armored = do { local $/; <$ct_fh> };
	close $ct_fh;

	print STDERR "Key: $key\n";

	$secret_section = <<"SECTION";
Attached below is a PGP-encrypted message containing your animal's name
and secret.

Save everything from the "BEGIN PGP MESSAGE" line through the "END PGP
MESSAGE" line (inclusive) into a file, e.g. message.asc, then decrypt it
with:

    gpg --batch --passphrase 'YOUR_KEY' -d message.asc

(substitute YOUR_KEY for the key sent to you separately.)

$armored
SECTION
}
else
{
	$secret_section = <<"SECTION";
Animal name: $name
Secret:      $secret
SECTION
}

my $body = <<"EMAIL";
Hi $owner,

Your $lv->{brand} application has been approved, for the following system
(included here in case you have more than one application pending):

    OS:         $os $osv
    Compiler:   $comp $compv
    Arch:       $arch

$secret_section
Thanks,
The $lv->{brand} Team
EMAIL

if (!$send)
{
	print $body;
	exit;
}

exit if $skip_mail;

my $me = `id -un`;
chomp $me;
my $host = `hostname`;
chomp($host);
$host = $default_host unless ($host =~ m/[.]/ || !defined($default_host));

my $from_addr = "$lv->{mail_from} <$me\@$host>";
$from_addr =~ tr /\r\n//d;

$from_addr = $register_from if $register_from;

my $msg = Mail::Send->new;
$msg->set('From', $from_addr);
$msg->to($owner_email);
$msg->set('Auto-Submitted',           'auto-generated');
$msg->set('X-Auto-Response-Suppress', 'all');
$msg->subject("$lv->{mail_tag} application approved");
my $mfh = $msg->open("sendmail", "-f $from_addr");
print $mfh $body;
$mfh->close;

print STDERR "Email sent to $owner_email\n";
