#! /usr/bin/perl -w
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;    #$running_under_some_shell

use strict;
use warnings;

use DBI;
use DBD::Pg;

use File::Find ();

use vars qw($dbhost $dbname $dbuser $dbpass $dbport
  $default_host $buildlogs_dir);

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my $sth = $db->prepare("SELECT count(*) FROM build_status WHERE sysname = ? and snapshot = ?", { pg_server_prepare => 1 });

sub wanted;

my @files;

# Scan the buildlogs_dir, looking for only regular files (we do not
# want to scan into any subdirectories).
File::Find::find({ preprocess => sub { return grep { -f } @_ }, wanted => \&wanted }, $buildlogs_dir);

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
	if ($file eq 'mail' || $file =~ /^tmp\.\d+/)
	{
		return;
	}

	# File names we are interested in are animal.DATETIME.something, so split
	# them up to use in the query.
	my ($animal, $ts, $suffix) = split(/\./, $file, 3);

	if (! $suffix)
	{
		# this could be the file before it's renamed to .meta, so ignore it
		return;
	}

	if (! ($animal && $ts && $suffix && ($suffix =~ /^(tgz|meta)$/)))
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
	my $rows = $db->selectrow_array($sth,undef,$animal,$ts);
	if (!defined($rows))
	{
		warn "error querying database for `$file': $sth->errstr";
		return;
	}

	# animal,ts is the PK of this table, so we can only get 0 or 1 back
	if ($rows == 1)
	{
		# We got a row back, so this import has been done,
		push (@files, $name);
	}
	else
	{
		# complain if the file has gotten to be old enough that
		# it really *should* have been imported by now
		my ($dev, $ino, $mode, $nlink, $uid, $gid);
		(($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
		  && (int(-M _) > 7)
		  && -f _
		  && warn "$name hasn't been imported yet!";
	}

	return;
}
