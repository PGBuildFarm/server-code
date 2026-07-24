#! /usr/bin/perl -w
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;    #$running_under_some_shell

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut


use strict;
use warnings;

use DBI;
use DBD::Pg;
use MIME::Base64;

use File::Find ();

use vars qw($dbhost $dbname $dbuser $dbpass $dbport_bin
  $default_host $buildlogs_dir);

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;

BEGIN
{
	$ENV{BFConfDir} ||= $ENV{BFCONFDIR};
	$ENV{BFCONFDIR} ||= $ENV{BFConfDir};
}

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport_bin" if $dbport_bin;

my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my $sth = $db->prepare(
	"SELECT count(*) FROM build_status WHERE sysname = ? and snapshot = ?",
	{ pg_server_prepare => 1 });

# Set of branches that still have any build in build_status. A build that
# is absent from build_status but whose branch no longer appears here at
# all belongs to a dropped/purged branch; such orphans are reaped rather
# than warned about. This is one scan of build_status, which is fine as
# the script runs periodically.
my %branch_followed;
{
	my $branches =
	  $db->selectcol_arrayref("SELECT DISTINCT branch FROM build_status");
	$branch_followed{$_} = 1 foreach @$branches;
}

sub wanted;
sub meta_branch;

my @files;

# Scan the buildlogs_dir, looking for only regular files (we do not
# want to scan into any subdirectories).
File::Find::find(
	{
		preprocess => sub {
			return grep { -f } @_;
		},
		wanted => \&wanted
	},
	$buildlogs_dir
);

$sth->finish();

foreach my $fname (@files)
{
	next unless -e $fname;
	unlink($fname) || warn "$fname: $!";
}

$db->disconnect;

exit;

## no critic (ValuesAndExpressions::ProhibitFiletest_f)

sub wanted
{
	# we've already filtered out everything but plain files in preprocess

	# $_ is the file name (no directory, we are chdir'ed there)
	my $file = $_;

	# ignore mail file, it should be cleaned up independently.
	# also ignore tmp.nnn files. They will be renamed.
	if ($file eq 'mail' || $file =~ /^tmp\.\d+$/)
	{
		return;
	}

	if ($file =~ /^tmp\.\d+\.tgz$/)
	{
		# could be a tgz in flight, but if it's old we exited before
		# the rename logic, So check for age.
		my ($dev, $ino, $mode, $nlink, $uid, $gid);
		     (($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
		  && (int(-M _) > 7)
		  && -f _
		  && push(@files, $name);
		return;
	}

	# File names we are interested in are animal.DATETIME.something, so split
	# them up to use in the query.
	my ($animal, $ts, $suffix) = split(/\./, $file, 3);

	if (!$suffix)
	{
		# this could be the file before it's renamed to .meta, or left
		# over from an error exit. Ignore unless it's old enough
		if ($ts =~ /^\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d$/)
		{
			my ($dev, $ino, $mode, $nlink, $uid, $gid);
			(($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
			  && (int(-M _) > 7)
			  && -f _
			  && push(@files, $name);
		}

		return;
	}

	if (!($animal && $ts && $suffix && ($suffix =~ /^(tgz|meta)$/)))
	{
		warn "unrecognized file found: `$file', ignoring";
		return;
	}

	if ($ts !~ /^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$/)
	{
		# doesn't look like a timestamp
		warn "unrecognized timestamp in file found: `$file', ignoring";
		return;
	}

	# Check if the run has been imported yet or not.
	my $rows = $db->selectrow_array($sth, undef, $animal, $ts);
	if (!defined($rows))
	{
		warn "error querying database for `$file': $sth->errstr";
		return;
	}

	# animal,ts is the PK of this table, so we can only get 0 or 1 back
	if ($rows == 1)
	{
		# We got a row back, so this import has been done,
		push(@files, $name);
	}
	else
	{
		# No matching build in the database. build_status is populated
		# synchronously by pgstatus.pl, so this never means "not imported
		# yet". Only act once the file is old enough.
		my ($dev, $ino, $mode, $nlink, $uid, $gid);
		return
		  unless (($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
		  && (int(-M _) > 7)
		  && -f _;

		# The build's own row is gone, so recover its branch from the
		# .meta (a .tgz carries no config; read its sibling .meta). If
		# the branch still has builds in build_status the missing row is
		# a real anomaly worth flagging; if the branch has none at all it
		# has been dropped/purged, so reap the orphan instead.
		(my $metafile = $file) =~ s/\.tgz$/.meta/;
		my $branch = meta_branch($metafile);

		if (defined($branch) && !$branch_followed{$branch})
		{
			push(@files, $name);
		}
		else
		{
			warn "$name hasn't been imported yet!";
		}
	}

	return;
}

# Recover the branch of a build from its .meta file. pgstatus.pl does not
# store the branch as its own field, but the client config it dumps into
# frozen_sconf carries it as the last positional argument in
# invocation_args. Returns undef if the file is unreadable or the branch
# cannot be determined.
sub meta_branch
{
	my $metafile = shift;

	open(my $fh, '<', $metafile) or return undef;
	my $branch;
	while (my $line = <$fh>)
	{
		next unless $line =~ /^frozen_sconf:(.*)/;
		my $enc = $1;

		# undo the transport escaping pgstatus.pl applies (+ -> $, = -> @)
		$enc =~ tr/$@/+=/;
		my $json = decode_base64($enc);

		if ($json =~ /"invocation_args"\s*:\s*\[([^\]]*)\]/)
		{
			my @args = $1 =~ /"((?:[^"\\]|\\.)*)"/g;
			$branch = $args[-1] if @args;
		}
		last;
	}
	close($fh);

	# ignore anything that isn't a plausible branch (e.g. an option, or a
	# run with no explicit branch argument): treat as undeterminable.
	undef $branch if defined($branch) && $branch =~ /^-/;

	return $branch;
}
