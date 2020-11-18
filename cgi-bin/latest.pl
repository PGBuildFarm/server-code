#!/usr/bin/perl

=comment

print "Content-Type: text/plain\n\n";

print "Conf: $ENV{BFConfDir}\n";

print `pwd`;

print `id`;

foreach my $key (sort keys %ENV)
{
  my $val = $ENV{$key};
  print "$key=$val\n";
}

=cut

use strict;
use warnings;

use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $query    = CGI->new;
my $pathinfo = $query->path_info();
my $netloc   = $query->url(-base => 1);
my ($junk, $branch, $member, $stage) = split(/\//, $pathinfo);
do { s/[^a-zA-Z0-9_ -]//g; }
  foreach ($branch, $member, $stage);

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn, $dbuser, $dbpass, { pg_expand_array => 0 })
  or die("$dsn,$dbuser,$dbpass,$!");

my $statement = <<"EOS";


  select b.*
  from dashboard_mat b
  where branch = ? and sysname = ?

EOS

my $row = $db->selectrow_hashref($statement, undef, $branch, $member);

$db->disconnect;

$row->{snapshot} =~ s/ /%20/g;

if (!$stage)
{
	print $query->redirect(
		"$netloc/cgi-bin/show_log.pl?nm=$member&dt=$row->{snapshot}");
}
else
{
	print $query->redirect("$netloc/cgi-bin/show_stage_log.pl?"
		  . "nm=$member&dt=$row->{snapshot}&stg=$stage");
}

#print "\n\nbranch = $branch, member=$member, stage=$stage,
# ts=$row->{snapshot}\n";
#use Data::Dumper; print Dumper(\$row);
