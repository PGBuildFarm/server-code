#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use DBD::Pg;
use File::Copy;
use JSON::PP;

our ($template_dir, $local_git_clone);

use vars qw($dbhost $dbname $dbuser $dbpass $dbport_bin);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

# don't use configged dbuser/dbpass

$dbuser = "";
$dbpass = "";

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
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

foreach my $branch_list (qw(branches_of_interest old_branches_of_interest))
{
	my $branches_of_interest = "$template_dir/../htdocs/$branch_list.txt";
	next unless -e $branches_of_interest;
	open(my $boi, "<", "$branches_of_interest")
	  || die "opening $branches_of_interest: $!";
	my @boi = <$boi>;
	close $boi;
	chomp @boi;

	chdir $local_git_clone;
	my $boi_ext = [];
	foreach my $branch (@boi)
	{
		my $format = '%h %cI %s';
		my $log = `git log -1 --format="$format" $branch`;
		next if $?;
		chomp $log;
		my ($ref, $ts, $subj) = split(/ /,$log, 3);
		push @$boi_ext, { $branch => $ref };
		$stmt->execute($branch, $ref, $ts, $subj);
	}

	chdir "$template_dir/../htdocs";
	open(my $ext_file,'>',"boiext.tmp") || die "opening file $!";
	my $json = JSON::PP->new->ascii->pretty->allow_nonref;
	print $ext_file $json->encode($boi_ext);
	close ($ext_file);
	move("boiext.tmp","$branch_list.json");
}

$stmt->finish();
$db->disconnect();
