#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;
use Template;
use Captcha::reCAPTCHA;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $notifyapp $captcha_pubkey $captcha_privkey $template_dir);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $template_opts = { INCLUDE_PATH => $template_dir};
my $template = new Template($template_opts);
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
    print "Content-Type: text/html\n\n";
    $template->process('register-incomplete.tt');
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

# everything looks OK, so tell them so
print "Content-type: text/html\n\n";
$template->process('register-ok.tt');

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






