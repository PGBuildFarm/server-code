#!/usr/bin/perl

=comment

Copyright (c) 2003-2026, Andrew Dunstan

See accompanying License file for license details

Populate the branch_git_tip table directly from the git repository, instead
of from the branches_of_interest files (see branches_of_interest.pl). Every
branch present in $local_git_clone is upserted with its current tip commit,
using the branch name exactly as git reports it -- no filtering and no name
translation, as this is intended for a non-standard repository.

=cut

use strict;
use warnings;

use DBI;
use DBD::Pg;

our ($local_git_clone);

use vars qw($dbhost $dbname $dbuser $dbpass $dbport_bin);

BEGIN
{
	$ENV{BFConfDir} ||= $ENV{BFCONFDIR};
	$ENV{BFCONFDIR} ||= $ENV{BFConfDir};
}

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

# connect as the running user (peer/ident auth), as branches_of_interest.pl does
$dbuser = "";
$dbpass = "";

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost"     if $dbhost;
$dsn .= ";port=$dbport_bin" if $dbport_bin;

my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my $stmt = $db->prepare(q(
    insert into branch_git_tip
        (branch, git_commit_ref, git_commit_ts, git_commit_header)
    values (?, ?, ?, ?)
    on conflict (branch) do
        update set git_commit_ref = excluded.git_commit_ref,
                   git_commit_ts = excluded.git_commit_ts,
                   git_commit_header = excluded.git_commit_header
));

my @gitdir = ("--git-dir=$local_git_clone");

# enumerate every branch in the repo. List form is used for all git calls so
# that the configured path and arbitrary branch names never reach a shell.
open(my $refs_fh, '-|', 'git', @gitdir, 'for-each-ref',
	'--format=%(refname:short)', 'refs/heads/')
  or die "running git for-each-ref: $!";
my @refs = <$refs_fh>;
close($refs_fh);
chomp @refs;

# guard against wiping the table if the repo could not be read
die "no branches found in $local_git_clone" unless @refs;

$db->begin_work;

foreach my $branch (@refs)
{
	# tip format matches branches_of_interest.pl
	open(my $log_fh, '-|', 'git', @gitdir, 'log', '-1',
		'--format=%h %cI %s', $branch)
	  or die "running git log for $branch: $!";
	my $log = <$log_fh>;
	close($log_fh);
	next unless defined $log;
	chomp $log;
	my ($ref, $ts, $subj) = split(/ /, $log, 3);

	$stmt->execute($branch, $ref, $ts, $subj);
}

# prune branches that are no longer present in the repo
$db->do('delete from branch_git_tip where branch <> all(?::text[])',
	undef, \@refs);

$db->commit;

$stmt->finish();
$db->disconnect();
