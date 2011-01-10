#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut 

use strict;
use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport 
			$template_dir @log_file_names $local_git_clone);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $template_opts = { INCLUDE_PATH => $template_dir, EVAL_PERL => 1};
my $template = new Template($template_opts);

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $query = new CGI;

my $system = $query->param('nm'); $system =~ s/[^a-zA-Z0-9_ -]//g;
my $logdate = $query->param('dt'); $logdate =~ s/[^a-zA-Z0-9_ :-]//g;

my $log = "";
my $conf = "";
my ($stage,$changed_this_run,$changed_since_success,$sysinfo,$branch,$scmurl);
my $scm;
my ($git_head_ref, $last_build_git_ref, $last_success_git_ref);

use vars qw($info_row);

if ($system && $logdate)
{

	my $db = DBI->connect($dsn,$dbuser,$dbpass,{pg_expand_array => 0});

	die $DBI::errstr unless $db;

	my $statement = q{

  		select log,conf_sum,stage, changed_this_run, changed_since_success,
                branch,	log_archive_filenames, scm, scmurl, git_head_ref
  		from build_status
  		where sysname = ? and snapshot = ?

	};
	my $last_build_statement = q{
		select distinct on (sysname) sysname, snapshot, stage, git_head_ref 
        from build_status 
        where sysname = ? and branch = ? and snapshot < ? 
        order by sysname, snapshot desc limit 1
	};
	my $last_success_statement = q{
		select distinct on (sysname) sysname, snapshot, git_head_ref 
        from build_status 
        where sysname = ? and branch = ? and snapshot < ? and stage = 'OK' 
        order by sysname, snapshot desc limit 1
	};
	my $sth=$db->prepare($statement);
	$sth->execute($system,$logdate);
	my $row=$sth->fetchrow_arrayref;
	$branch = $row->[5];
	$git_head_ref = $row->[9];
	$sth->finish;
	my $last_build_row;
	if ($git_head_ref)
	{
		$last_build_row = 
		  $db->selectrow_hashref($last_build_statement,undef,
								 $system,$branch,$logdate);
		$last_build_git_ref = $last_build_row->{git_head_ref}
		  if $last_build_row;
		
	}
	my $last_success_row;
	if (ref $last_build_row && $last_build_row->{stage} ne 'OK')
	{
		$last_success_row =
		  $db->selectrow_hashref($last_success_statement,undef,
								 $system,$branch,$logdate);
		$last_success_git_ref = $last_success_row->{git_head_ref}
		  if $last_success_row;
	}
	$log=$row->[0];
	$conf=$row->[1] || "not recorded" ;
	$stage=$row->[2] || "unknown";
	$changed_this_run = $row->[3];
	$changed_since_success = $row->[4];
	my $log_file_names = $row->[6];
	$scm = $row->[7];
	$scm ||= 'cvs'; # legacy scripts
	$scmurl = $row->[8];
	$log_file_names =~ s/^\{(.*)\}$/$1/;
	@log_file_names=split(',',$log_file_names)
	    if $log_file_names;

	$statement = q{

          select operating_system, os_version, 
                 compiler, compiler_version, 
                 architecture,
		 replace(owner_email,'\@',' [ a t ] ') as owner_email,
		 sys_notes_ts::date AS sys_notes_date, sys_notes
          from buildsystems 
          where status = 'approved'
                and name = ?

	};
	$sth=$db->prepare($statement);
	$sth->execute($system);
	$info_row=$sth->fetchrow_hashref;

	my $latest_personality = $db->selectrow_arrayref(q{
	    select os_version, compiler_version
	    from personality
	    where effective_date < ?
	    and name = ?
	    order by effective_date desc limit 1
	}, undef, $logdate, $system);
	if ($latest_personality)
	{
	    $info_row->{os_version} = $latest_personality->[0];
	    $info_row->{compiler_version} = $latest_personality->[1];
	}
	$sth->finish;
	$db->disconnect;
}

my ($changed_this_run_logs, $changed_since_success_logs);
($changed_this_run, $changed_this_run_logs) = 
  process_changed($changed_this_run,
				  $git_head_ref,$last_build_git_ref);
($changed_since_success, $changed_since_success_logs) = 
  process_changed($changed_since_success,
				  $last_build_git_ref,$last_success_git_ref);

$conf =~ s/\@/ [ a t ] /g;

print "Content-Type: text/html\n\n";

$template->process('log.tt',
	{
		scm => $scm,
		scmurl => $scmurl,
		system => $system,
		branch => $branch,
		stage => $stage,
		urldt => $logdate,
		log_file_names => \@log_file_names,
		conf => $conf,
		log => $log,
		changed_this_run => $changed_this_run,
		changed_since_success => $changed_since_success,
		changed_this_run_logs => $changed_this_run_logs,
		changed_since_success_logs => $changed_since_success_logs,
		info_row => $info_row,
	    git_head_ref => $git_head_ref,
	    last_build_git_ref => $last_build_git_ref,
	    last_success_git_ref => $last_success_git_ref,

	});

exit;

##########################################################

sub process_changed
{

	my $chgd = shift;
	my $git_to = shift;
	my $git_from = shift;

    my @lines = split(/!/,$chgd);
    my @changed_rows;
	my %commits;
	my @commit_logs;
	my $gitcmd = "TZ=UTC GIT_DIR=$local_git_clone git log --date=local";
    foreach (@lines)
    {
		next if ($scm eq 'cvs' and ! m!^(pgsql|master|REL\d_\d_STABLE)/!);
		push(@changed_rows,[$1,$3]) if (m!(^\S+)(\s+)(\S+)!);
		$commits{$3} = 1 if $scm eq 'git';
    }
	if ($git_from && $git_to)
	{
		my $format = 'commit %h %cd UTC%w(160,2,2)%s';
		my $gitlog = `$gitcmd --pretty=format:"$format" $git_from..$git_to 2>&1`;
		@commit_logs = split(/(?=^commit)/m,$gitlog)
	}
	else
	{
		# normally we expect to have the git refs. this is just a fallback.
		my $format = 'epoch: %at%ncommit %h %cd UTC%w(160,2,2)%s';
		foreach my $commit ( keys %commits )
		{
			my $commitlog = 
			  `$gitcmd -n 1 --pretty=format:"$format" $commit 2>&1`;
			push(@commit_logs,$commitlog);
		}
		@commit_logs = reverse (sort @commit_logs);
		s/epoch:.*\n// for (@commit_logs);
	}
		return (\@changed_rows,\@commit_logs);
}

