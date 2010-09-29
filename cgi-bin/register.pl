#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;
use Template;
use Captcha::reCAPTCHA;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $notifyapp $captcha_pubkey $captcha_privkey);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";
#require "BuildFarmWeb.pl";

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $header = <<EOS;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
	<title>PostgreSQL BuildFarm Application</title>
	<link rel="icon" type="image/png" href="/elephant-icon.png" />
	<link rel="stylesheet" rev="stylesheet" href="/inc/pgbf.css" charset="utf-8" />
	<style type="text/css"><!--
	li#register a { color:rgb(17,45,137); background: url(/inc/b/r.png) no-repeat 100% -20px; } 
	li#register { background: url(/inc/b/l.png) no-repeat 0% -20px; }
	--></style>
</head>
<body class="application">
<div id="wrapper">
<div id="banner">
<a href="/index.html"><img src="/inc/pgbuildfarm-banner.png" alt="PostgreSQL BuildFarm" width="800" height="73" /></a>
<div id="nav">
<ul>
    <li id="home"><a href="/index.html" title="PostgreSQL BuildFarm Home">Home</a></li>
    <li id="status"><a href="/cgi-bin/show_status.pl" title="Current results">Status</a></li>
    <li id="members"><a href="/cgi-bin/show_members.pl" title="Platforms tested">Members</a></li>
    <li id="register"><a href="/cgi-bin/register-form.pl" title="Join PostgreSQL BuildFarm">Register</a></li>
    <li id="pgfoundry"><a href="http://pgfoundry.org/projects/pgbuildfarm/">PGFoundry</a></li>
    <li id="postgresql.org"><a href="http://www.postgresql.org">PostgreSQL.org</a></li>
</ul>
</div><!-- nav -->
</div><!-- banner -->
<div id="main">
EOS

my $footer = <<EOS;
</div><!-- main -->
<hr />
<p style="text-align: center;">
Hosting for the PostgreSQL Buildfarm is generously 
provided by: 
<a href="http://www.commandprompt.com">CommandPrompt, 
The PostgreSQL Company</a>
</p>
</div><!-- wrapper -->
</body>
</html>
EOS

my $query = new CGI;

my $params = $query->Vars;

my ($os, $osv, $comp, $compv, $arch, $email, $owner, $challenge, $response ) = @{$params}{
	qw(os osv comp compv arch email owner recaptcha_challenge_field recaptcha_response_field)};

my $captcha = Captcha::reCAPTCHA->new;
my $captcha_ok = $captcha->check_answer
    (
     $captcha_privkey, 
     $ENV{'REMOTE_ADDR'},
     $challenge, $response
     );


unless ($os && $osv && $comp && $compv && $arch && $email && $owner && $captcha_ok->{is_valid})
{
	print "Content-Type: text/html\n\n",
	$header,
	"<p>You need to complete all the form items. <a href=\"/cgi-bin/register-form.pl\">Please try again.</a></p>\n",
	$footer;
	exit;
}

# some idiot has a script that tries to talk to me
# this should catch and dispose of him
if ((grep {/rgergerger|\@pgbuildfarm\.org|Content-Type:|http:|mailto:|href=|None|Unknown/} $os,$osv,$comp,$compv,$arch,$email,$owner)
    || ($email =~ /john.*\@aol.com/) )
{
    print 
	"Status: 403 Forbidden - go away idiot\n",
	"Content-Type: text/plain\n\n";
    exit;    
}

# count transitions to and from upper case
my $trans = 1;
my $counttrans = 0;
foreach (split "" ,"$os$osv$comp$compv$arch$owner")
{
	if (/[A-Z]/)
	{
		next if $trans;
		$trans = 1;
		$counttrans++;
	}
	else
	{
		next unless $trans;
		$trans = 0;
		$counttrans++;
	}
}

# reject junk with too many transitions into/outof upper case
if ($counttrans > 20)
{
    print 
	"Status: 403 Forbidden - go away idiot\n",
	"Content-Type: text/plain\n\n";
    exit;   
}



my $secret = "";
my $dummyname=""; # we'll select an animal name when we approve it.
foreach (1..8)
{
	# 8 random chars is enough for the dummy name
	$secret .= substr("0123456789abcdefghijklmnopqrstuvwxyz",int(rand(36)),1);
	$dummyname .= substr("0123456789abcdef",int(rand(16)),1);
}
foreach (9..32)
{
	$secret .= substr("0123456789abcdef",int(rand(16)),1);
}

my $db = DBI->connect($dsn,$dbuser,$dbpass);

my $statement = <<EOS;

  insert into buildsystems 
    (name, secret, operating_system, os_version, compiler, compiler_version,
     architecture, status, sys_owner, owner_email)
  values(?,?,?,?,?,?,?,'pending',?,?)

EOS
;

my $sth=$db->prepare($statement);
my $rv=$sth->execute($dummyname,$secret,$os,$osv,$comp,$compv,
			  $arch,$owner,$email);
my $err=$db->errstr;
print "Content-type: text/html\n\n";
print $header
    , "<h1>PostgreSQL BuildFarm Application received</h1>\n"
    , "<p>Thank you. You should hear from us shortly.</p>"
    , $footer;


$sth->finish;
$db->disconnect;


use Mail::Send;

my $msg = new Mail::Send;

my $me = `id -un`;

my $host = `hostname`;

$msg->set('From',"PG Build Farm <$me\@$host>");

$msg->to(@$notifyapp);
$msg->subject('New Buildfarm Application');
my $fh = $msg->open;
print $fh "\n\nName: $dummyname\n",
    "OS: $os: $osv\n",
    "Arch: $arch\n",
    "Comp: $comp: $compv\n",
    "Owner: $owner <$email>\n";
$fh->close;






