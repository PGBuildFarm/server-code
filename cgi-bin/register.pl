#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use DBI;
use Template;
use CGI;
use Template;

use lib "$ENV{BFCONFDIR}/perl5";
use Captcha::reCAPTCHA::V2;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $notifyapp
  $captcha_invis_privkey $template_dir $default_host
  $register_from $skip_mail $skip_captcha);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $template_opts = { INCLUDE_PATH => $template_dir };
my $template      = Template->new($template_opts);
my $query         = CGI->new;

my $params = $query->Vars;

my ($os, $osv, $comp, $compv, $arch, $email, $owner, $response) =
  @{$params}{qw(os osv comp compv arch email owner g-recaptcha-response)};

my $ok = 1;

unless ($skip_captcha)
{
	if (defined($response))
	{
		my $captcha = Captcha::reCAPTCHA::V2->new;
		$ok = $captcha->verify($captcha_invis_privkey, $response,
			$ENV{REMOTE_ADDR});
	}
	else
	{
		$ok = undef;
	}
}

unless ($os
	&& $osv
	&& $comp
	&& $compv
	&& $arch
	&& $email
	&& $owner
	&& $ok)
{
	print "Content-Type: text/html\n\n";
	$template->process('register-incomplete.tt');
	exit;
}

my $secret    = "";
my $dummyname = "";    # we'll select an animal name when we approve it.
foreach (1 .. 8)
{
	# 8 random chars is enough for the dummy name
	$secret .= substr("0123456789abcdefghijklmnopqrstuvwxyz", int(rand(36)), 1);
	$dummyname .= substr("0123456789abcdef", int(rand(16)), 1);
}
foreach (9 .. 32)
{
	$secret .= substr("0123456789abcdef", int(rand(16)), 1);
}

my $db = DBI->connect($dsn, $dbuser, $dbpass);

my $statement = <<"EOS";

  insert into buildsystems
    (name, secret, operating_system, os_version, compiler, compiler_version,
     architecture, status, sys_owner, owner_email)
  values(?,?,?,?,?,?,?,'pending',?,?)

EOS

my $sth = $db->prepare($statement);
my $rv =
  $sth->execute($dummyname, $secret, $os, $osv, $comp, $compv, $arch, $owner,
	$email);
my $err = $db->errstr;

# everything looks OK, so tell them so
print "Content-type: text/html\n\n";
$template->process('register-ok.tt');

$sth->finish;
$db->disconnect;

exit if $skip_mail || ($owner eq 'adnoregister');

use Mail::Send;

my $msg = Mail::Send->new;

my $me = `id -un`;
chomp($me);
my $host = `hostname`;
chomp($host);
$host = $default_host unless ($host =~ m/[.]/ || !defined($default_host));

my $from_addr = "PG Build Farm <$me\@$host>";
$from_addr =~ tr /\r\n//d;

$from_addr = $register_from if $register_from;

$msg->set('From', $from_addr);

$msg->to(@$notifyapp);
$msg->set('Reply-To', @$notifyapp);
$msg->set('Auto-Submitted', 'auto-generated');
$msg->set('X-Auto-Response-Suppress', 'all');
$msg->subject('New Buildfarm Application');
my $fh = $msg->open("sendmail", "-f $from_addr");
print $fh "\n\nName: $dummyname\n",
  "OS: $os: $osv\n",
  "Arch: $arch\n",
  "Comp: $comp: $compv\n",
  "Owner: $owner <$email>\n";
$fh->close;

