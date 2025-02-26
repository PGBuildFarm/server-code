#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use lib "$ENV{BFCONFDIR}/perl5";
use BFUtils;

use DBI;
use Template;
use CGI;
use File::Temp qw(tempfile);

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir $email_only);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $query = CGI->new;

my $system = $query->param('nm');
$system =~ s/[^a-zA-Z0-9_ -]//g if $system;
my $logdate = $query->param('dt');
$logdate =~ s/[^a-zA-Z0-9:_ -]//g if $logdate;
my $stage = $query->param('stg');
$stage =~ s/[^a-zA-Z0-9._ -]//g if $stage;
my $brnch = $query->param('branch') || 'HEAD';
$brnch =~ s{[^a-zA-Z0-9._/ -]}{}g;
$brnch =~ s/^master$/HEAD/;
my $raw = $query->param('raw') || '0';
$raw =~ s{[^a-zA-Z0-9._/ -]}{}g;

use vars qw($tgz);

# sanity check the date - some browsers mangle decoding it
if (   $system
	&& $logdate
	&& (   $logdate =~ /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/
		|| $logdate =~ /^latest$/i)
	&& $stage)
{
	my $db = DBI->connect($dsn, $dbuser, $dbpass);

	die $DBI::errstr unless $db;

	if ($logdate =~ /^latest$/i)
	{
		my $find_latest = qq{
            select max(snapshot)
            from build_status_log
            where sysname = ?
                and snapshot > now() - interval '30 days'
                and log_stage = ? || '.log'
                and branch = ?
        };
		my $logs =
		  $db->selectcol_arrayref($find_latest, undef, $system, $stage, $brnch);
		$logdate = shift(@$logs);
	}

	my $statement = q(

        select branch, log_text
        from build_status_log
        where sysname = ? and snapshot = ? and log_stage = ? || '.log'

        );

	my $sth = $db->prepare($statement);
	$sth->execute($system, $logdate, $stage);
	my $row = $sth->fetchrow_arrayref;
	my ($branch, $logtext);
	if ($row)
	{
		$branch  = $row->[0];
		$logtext = $row->[1];
	}
	$sth->finish;
	$db->disconnect;

	$branch ||= "unknown";
	$logtext //= "";

	if ($raw || $stage eq 'typedefs')
	{

		print
		  "Content-Type: text/plain\nContent-disposition: inline; filename=$stage.log\n\n";

		if ($stage ne 'typedefs')
		{
			print "Snapshot: $logdate\n\n";
			$logtext ||= "no log text found";
		}

		$logtext =~
		  s/([\x00-\x08\x0B\x0C\x0E-\x1F\x80-\xff])/sprintf("\\x%.02x",ord($1))/ge
		  if $logtext;
		print $logtext if $logtext;

	}
	else
	{
		my $log = $logtext;
		my $template_opts = { INCLUDE_PATH => $template_dir};
		my $template = Template->new($template_opts);

		my $log_marker = "==~_~===-=-===~_~==";

		my @log_pieces;
		my @log_piece_names;
		my @pieces = split (/$log_marker (.*?) $log_marker\r?\n/, $log);
		if ($log =~ /^$log_marker/)
		{
			$log = "";
		}
		else
		{
			$log = shift(@pieces) // "";
			# skip useless preliminary make output
			if ($log =~ /.*?\n(([A-Za-z]{3} \d\d \d\d:\d\d:\d\d )?(echo "\+\+\+))/s)
			{
				my $pos = $-[1];
				my $good = substr($log,$pos);
				my $head = substr($log,0,$pos);
				$head =~ s/.*ake.*?Nothing to be done for.*?\n//s;
				$log = $head . $good;
			}
		}
		while (@pieces)
		{
			push(@log_piece_names, shift(@pieces));
			push(@log_pieces, shift(@pieces));
		}
		for (@log_piece_names)
		{
			s!.*?/(upgrade\.$system)!$1!;
		}

		$branch =~ s/^HEAD$/master/;

		print "Content-Type: text/html\n\n";

		$template->process(
						   'log_stage.tt',
						 {
						  system                     => $system,
						  branch                     => $branch,
						  stage                      => $stage,
						  urldt                      => $logdate,
						  log                        => $log,
						  log_pieces => \@log_pieces,
						  log_piece_names => \@log_piece_names,
						  });
	}
}

else
{
	print "Status: 460 bad parameters\n", "Content-Type: text/plain\n\n";
}

