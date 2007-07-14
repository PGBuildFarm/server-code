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

my $system = $query->param('nm');
my $logdate = $query->param('dt');
my $stage = $query->param('stg');

use vars qw($tgz $output);

if ($stage && $system && $logdate)
{
    
}

if ($system && $logdate)
{

    my $db = DBI->connect($dsn,$dbuser,$dbpass);

    die $DBI::errstr unless $db;

    if ($stage)
    {
	my $lst = q(
		    select log_text
		    from build_status_log
		    where sysname = ?
		       and snapshot = ?
		       and log_file_name = ?
		    );
	
    }

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
    $output = `tar -z -O -xf $filename $stage.log 2>&1`
	if $stage;;



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
