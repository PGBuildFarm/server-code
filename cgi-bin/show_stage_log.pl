#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut 

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
my $stage = $query->param('stg');$stage =~ s/[^a-zA-Z0-9._ -]//g;

use vars qw($tgz);

if ($system && $logdate && $stage)
{
    my $db = DBI->connect($dsn,$dbuser,$dbpass);

    die $DBI::errstr unless $db;

    my $statement = q(

        select branch, log_text
        from build_status_log
        where sysname = ? and snapshot = ? and log_stage = ? || '.log'

        );


    
    my $sth=$db->prepare($statement);
    $sth->execute($system,$logdate,$stage);
    my $row=$sth->fetchrow_arrayref;
    my ($branch, $logtext) = ("unknown","no log text found");
    if ($row)
    {
        $branch = $row->[0];
        $logtext =$row->[1];
    }
    $sth->finish;
    $db->disconnect;

    print "Content-Type: text/plain\n\n", $logtext,

    "-------------------------------------------------\n\n",
    "Hosting for the PostgreSQL Buildfarm is generously ",
    "provided by: CommandPrompt, The PostgreSQL Company";

}

else 
{
    print "Status: 460 bad parameters\n",
    "Content-Type: text/plain\n\n";
}

