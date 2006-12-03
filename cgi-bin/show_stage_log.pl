#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;
use File::Temp qw(tempfile);

use vars qw($dbhost $dbname $dbuser $dbpass $dbport @log_file_names);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";
#require "BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $query = new CGI;

my $system = $query->param('nm'); $system =~ s/[^a-zA-Z0-9_ -]//g;
my $logdate = $query->param('dt');$logdate =~ s/[^a-zA-Z0-9_ -]//g;
my $stage = $query->param('stg');$stage =~ s/[^a-zA-Z0-9_ -]//g;

use vars qw($tgz);

if ($system && $logdate)
{

    my $db = DBI->connect($dsn,$dbuser,$dbpass);

    die $DBI::errstr unless $db;

    my $statement = q(

		select log_archive
		from build_status
		where sysname = ? and snapshot = ?

		);


    
    my $sth=$db->prepare($statement);
    $sth->execute($system,$logdate);
    my $row=$sth->fetchrow_arrayref;
    $tgz=$row->[0];
    $sth->finish;
    $db->disconnect;

}

unless ($stage)
{

    print 
	"Content-Type: application/x-gzip\n", 
	"Content-Disposition: attachment; filename=buildfarmlog.tgz\n",
	"\n",
	$tgz;
    exit;
}

my $template = "buildlogXXXXXX";
my ($fh, $filename) = tempfile($template, UNLINK => 1);
print $fh $tgz;
close($fh);

my $output = `tar -z -O -xf $filename $stage.log 2>&1`;

print "Content-Type: text/plain\n\n", $output,

    "-------------------------------------------------\n\n",
    "Hosting for the PostgreSQL Buildfarm is generously ",
    "provided by: CommandPrompt, The PostgreSQL Company";

; exit;

# using <pre> like this on huge files can make browsers choke

print "Content-Type: text/html\n\n";

print <<EOHTML;
<html>
<body>
<pre>
$output
</pre>
</body>
</html>

EOHTML
