#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use lib "$ENV{BFCONFDIR}/perl5";
use BFUtils;

use CGI;
use DBI;
use Template;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir $sort_by
		  $email_only);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

my $query   = CGI->new;
my %sort_ok = (
	'name'     => 'lower(name)',
	'owner'    => 'lower(owner_email)',
	'os'       => 'lower(operating_system), os_version',
	'compiler' => 'lower(compiler), compiler_version',
	'arch'     => 'lower(architecture)'
);
$sort_by = $query->param('sort_by');
$sort_by =~ s/[^a-zA-Z0-9_ -]//g if $sort_by;
$sort_by = $sort_by ? $sort_ok{$sort_by} || $sort_ok{name} : $sort_ok{name};

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn, $dbuser, $dbpass, { pg_expand_array => 0 });

# there is possibly some redundancy in this query, but it makes
# a lot of the processing simpler.

my $statement = q{

  select name, operating_system, os_version, compiler, compiler_version,
    owner_email, sys_notes_ts::date AS sys_notes_date, sys_notes,
    architecture as arch, status, status_ts::date as status_date, ARRAY(
				select case when branch = 'HEAD' then 'master' else branch end
                       || ':' || extract(days from now() - l.snapshot)
				from latest_snapshot l
				where l.sysname = s.name
				order by branch <> 'HEAD', branch COLLATE "C" desc
				) as branches,
			  ARRAY(select compiler_version || E'\t' ||  os_version ||
                   E'\t' || effective_date
				from personality p
				where p.name = s.name
				order by effective_date
				) as personalities
  from buildsystems s
  where status not in ('pending','declined')
};

$statement .= "order by $sort_by";

my $statrows = [];
my $sth      = $db->prepare($statement);
$sth->execute;
while (my $row = $sth->fetchrow_hashref)
{
	$row->{branches} =~ s/^\{(.*)\}$/$1/;
	my $personalities = $row->{personalities};
	$personalities =~ s/^\{(.*)\}$/$1/;
	my @personalities = split(',', $personalities);
	$row->{personalities} = [];
	foreach my $personality (@personalities)
	{
		$personality =~ s/^"(.*)"$/$1/;
		$personality =~ s/\\(.)/$1/g;

		my ($compiler_version, $os_version, $effective_date) =
		  split(/\t/, $personality);
		$effective_date =~ s/ .*//;
		push(
			@{ $row->{personalities} },
			{
				compiler_version => $compiler_version,
				os_version       => $os_version,
				effective_date   => $effective_date
			}
		);
	}
	$row->{owner_email} =~ s/\@/ [ a t ] /;
	push(@$statrows, $row);
}
$sth->finish;

$db->disconnect;

# use Data::Dumper;
# print "Content-Type: text/plain\n\n",Dumper($statrows),"VERSION: ",
# $DBD::Pg::VERSION,"\n"; exit;

my $template_opts = { INCLUDE_PATH => $template_dir };
my $template = Template->new($template_opts);

print "Content-Type: text/html\n\n";

$template->process('members.tt', { statrows => $statrows });

exit;

