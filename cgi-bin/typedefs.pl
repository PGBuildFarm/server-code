#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use DBI;
use CGI;
use Data::Dumper;
use Template;

my $query = CGI->new;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my %params    = $query->Vars;
my $show_list = $params{show_list};
$show_list = 1 if exists $params{keywords} && $params{keywords} =~ /show_list/;
my $branch = $query->param('branch');
$branch =~ s{[^a-zA-Z0-9_/ -]}{}g if $branch;

if (!$branch || $branch eq 'master')
{
	$branch = 'HEAD';
}
elsif ($branch eq 'ALL')
{
	$branch = undef;
}

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $dbh = DBI->connect($dsn, $dbuser, $dbpass)
  or die("$dsn,$dbuser,$dbpass,$!");

my %words;

my $sql = q{
    with snaps as (
    select sysname, branch, max(snapshot) as snapshot
    from build_status_log
    where log_stage = 'typedefs.log' and
        snapshot > current_date::timestamp - interval '30 days'
    group by sysname, branch
    )
    select snaps.sysname, snaps.branch, snaps.snapshot,
        length(regexp_replace(log_text,'[^\n]','','g')) as lines_found
    from build_status_log l
       join snaps
          on snaps.sysname = l.sysname and snaps.snapshot = l.snapshot
    where log_stage = 'typedefs.log'  and length(log_text) > 5000
    order by snaps.sysname, snaps.branch != 'HEAD', snaps.branch COLLATE "C" desc
};
my $builds = $dbh->selectall_arrayref($sql, { Slice => {} });
my %branches;
foreach my $build (@$builds) { $branches{ $build->{branch} } = 1; }

if (defined $show_list)
{

	my $template_opts = { INCLUDE_PATH => $template_dir, EVAL_PERL => 1 };
	my $template = Template->new($template_opts);

	print "Content-Type: text/html\n\n";

	my $sorter =
	  sub { $a eq 'HEAD' ? -100 : ($b eq 'HEAD' ? 100 : $b cmp $a); };

	$template->process(
		"typedefs.tt",
		{
			builds   => $builds,
			branches => [ sort $sorter keys %branches ],
		}
	);
	exit;
}

$sql = q{
   select log_text
   from build_status_log
   where sysname = ?
     and snapshot = ?
     and log_stage = 'typedefs.log'
     and branch = ?
 };

my $sth = $dbh->prepare($sql);

foreach my $build (@$builds)
{
	next if $branch && $build->{branch} ne $branch;
	$sth->execute($build->{sysname}, $build->{snapshot}, $build->{branch});
	my @row = $sth->fetchrow;
	my @typedefs = split(/\s+/, $row[0]);
	@words{@typedefs} = 1 x @typedefs;
}

print "Content-Type: text/plain\n\n",

  #  Dumper(\%params),
  join("\n", sort keys %words), "\n";
