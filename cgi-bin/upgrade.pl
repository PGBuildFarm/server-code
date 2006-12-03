#!/usr/bin/perl

use strict;

use CGI;
use Digest::SHA1  qw(sha1_hex);
use MIME::Base64;
use DBI;
use DBD::Pg;
use Data::Dumper;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);

my $query = new CGI;

my $sig = $query->path_info;
$sig =~ s!^/!!;

my $animal = $query->param('animal');
my $ts = $query->param('ts');
my $os_version = $query->param('new_os');
my $compiler_version = $query->param('new_compiler');

my $content = "animal=$animal\&ts=$ts";
$content .= "\&new_os=$os_version" if $os_version;
$content .= "\&new_compiler=$compiler_version" if $compiler_version;

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

unless ($animal && $ts && ($os_version || $compiler_version) && $sig)
{
	print 
	    "Status: 490 bad parameters\nContent-Type: text/plain\n\n",
	    "bad parameters for request\n";
	exit;
	
}


my $db = DBI->connect($dsn,$dbuser,$dbpass);

die $DBI::errstr unless $db;

my $gethost=
    "select secret from buildsystems where name = ? and status = 'approved'";
my $sth = $db->prepare($gethost);
$sth->execute($animal);
my ($secret)=$sth->fetchrow_array();
$sth->finish;


unless ($secret)
{
	print 
	    "Status: 495 Unknown System\nContent-Type: text/plain\n\n",
	    "System $animal is unknown\n";
	$db->disconnect;
	exit;
	
}




my $calc_sig = sha1_hex($content,$secret);

if ($calc_sig ne $sig)
{

	print "Status: 450 sig mismatch\nContent-Type: text/plain\n\n";
	print "$sig mismatches $calc_sig on content:\n$content";
	$db->disconnect;
	exit;
}

# undo escape-proofing of base64 data and decode it
map {tr/$@/+=/; $_ = decode_base64($_); } 
    ($os_version, $compiler_version);

my $get_latest = q{

    select coalesce(b.os_version, a.os_version) as os_version,
           coalesce(b.compiler_version, a.compiler_version) as compiler_version
    from buildsystems as a left join
         (  select distinct on (name) name, compiler_version, os_version
            from personality
            order by name, effective_date desc
         ) as b
         on (a.name = b.name)
    where a.name = ?
          and a.status = 'approved'

};

$sth = $db->prepare($get_latest);
my $rv = $sth->execute($animal);
unless($rv)
{
	print "Status: 460 old data fetch\nContent-Type: text/plain\n\n";
	print "error: ",$db->errstr,"\n";
	$db->disconnect;
	exit;
}

my ($old_os,$old_comp)=$sth->fetchrow_array();
$sth->finish;



$os_version ||= $old_os;
$compiler_version ||= $old_comp;

my $new_personality = q{

    insert into personality (name, os_version, compiler_version)
	values (?,?,?)

}; 


$sth = $db->prepare($new_personality);
$rv = $sth->execute($animal,$os_version, $compiler_version);

unless($rv)
{
	print "Status: 470 new data insert\nContent-Type: text/plain\n\n";
	print "error: $db->errstr\n";
	$db->disconnect;
	exit;
}

$sth->finish;



$db->disconnect;

print "Content-Type: text/plain\n\n";
print "request was on:\n$content\n";



