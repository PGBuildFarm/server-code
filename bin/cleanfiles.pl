#! /usr/bin/perl -w
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
  if 0;    #$running_under_some_shell

use strict;
use warnings;

use DBI;
use DBD::Pg;

use File::Spec;
use File::Find ();

use vars qw($dbhost $dbname $dbuser $dbpass $dbport
  $default_host $buildlogs_dir);

# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

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

my $sth = $db->prepare("SELECT sysname FROM build_status WHERE sysname = ? and snapshot = ?", { pg_server_prepare => 1 });

sub wanted;

my @files;

# Traverse desired filesystems
File::Find::find({ wanted => \&wanted }, $buildlogs_dir);

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
	my ($dev, $ino, $mode, $nlink, $uid, $gid, $rv);

	# Get the base filename into $file.
	my ($volume,$directories,$file) = File::Spec->splitpath( $_ );

	# ignore hidden files and directories
	if ($file =~ /^\./)
	{
		return;
	}

	# TODO: change these files to be named better so we can check them too
	# instead of just nuking them when they get to be old..
	if ($file =~ /^tmp\.\d+\.(tgz|unpacklogs)$/)
	{
		(($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
		  && (int(-M _) > 7)
		  &&

		  #    ( -M _ > 0.05 ) && # 1.2 hours
		  -f _
		  && push (@files, $name);

		return;
	}

	# File names we are interested in are animal.DATETIME, so split them
	# up to use in the query.
	my ($animal, $ts) = split(/\./, $file);

	if (!defined($animal) || !defined($ts) || $animal eq '' || $ts eq '')
	{
		warn "unrecognized file found: `$file', ignoring";
		return;
	}

	$sth->bind_param(1, $animal);
	$sth->bind_param(2, $ts);

	# Check if the run has been imported yet or not.
	$rv = $sth->execute();
	if (!defined($rv))
	{
		warn "error querying database for `$file': $sth->errstr";
		return;
	}

	# We should only get one, or no, rows returned.
	if ($rv != 1 && $rv != 0)
	{
		warn "checking $file: wrong number of rows returned!";
		return;
	}

	if ($rv == 1)
	{
		# We got a row back, so this import should be done,
		# but just double-check that it's the same animal.
		die "got different animal" unless $animal eq $sth->fetch()->[0];

		push (@files, $name);
	}
	else
	{
		# complain if the file has gotten to be old enough that
		# it really *should* have been imported by now
		(($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
		  && (int(-M _) > 7)
		  &&

		  #    ( -M _ > 0.05 ) && # 1.2 hours
		  -f _
		  && warn "$name hasn't been imported yet!";
	}

	return;
}
