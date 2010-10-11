#!/usr/bin/perl

use strict;
use CGI;
use DBI;
use Template;



use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir $sort_by);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";
#require "BuildFarmWeb.pl";

my $query = new CGI;
my %sort_ok = ('name' => 'lower(name)' , 
	       'owner' => 'lower(owner_email)', 
	       'os' => 'lower(operating_system), os_version', 
	       'compiler' => 'lower(compiler), compiler_version' ,
	       'arch' => 'lower(architecture)' );
$sort_by = $query->param('sort_by');$sort_by =~ s/[^a-zA-Z0-9_ -]//g;
$sort_by = $sort_ok{$sort_by} || $sort_ok{name};

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn,$dbuser,$dbpass);

# there is possibly some redundancy in this query, but it makes
# a lot of the processing simpler.

my $statement = <<EOS;

  select name, operating_system, os_version, compiler, compiler_version, owner_email, 
    architecture as arch, ARRAY(
				select branch || ':' || 
				       extract(days from now() - latest_snapshot)
				from build_status_latest l 
				where l.sysname = s.name
				order by branch <> 'HEAD', branch desc 
				) as branches 
  from buildsystems s
  where status = 'approved'
  order by $sort_by

EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute;
while (my $row = $sth->fetchrow_hashref)
{
    $row->{branches} =~ s/^\{(.*)\}$/$1/;
    $row->{owner_email} =~ s/\@/ [ a t ] /;
    push(@$statrows,$row);
}
$sth->finish;


$db->disconnect;

# use Data::Dumper; print "Content-Type: text/plain\n\n",Dumper($statrows),"VERSION: ",$DBD::Pg::VERSION,"\n"; exit;


my $template_opts = { INCLUDE_PATH => $template_dir};
my $template = new Template($template_opts);

print "Content-Type: text/html\n\n";

$template->process('members.tt',
		{statrows=>$statrows});

exit;

