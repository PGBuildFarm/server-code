#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport $template_dir @log_file_names);

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

use vars qw($info_row);

if ($system && $logdate)
{

	my $db = DBI->connect($dsn,$dbuser,$dbpass);

	die $DBI::errstr unless $db;

	my $statement = q{

  		select log,conf_sum,stage, changed_this_run, changed_since_success,branch,
      			log_archive_filenames, scm, scmurl
  		from build_status
  		where sysname = ? and snapshot = ?

	};
	my $sth=$db->prepare($statement);
	$sth->execute($system,$logdate);
	my $row=$sth->fetchrow_arrayref;
	$log=$row->[0];
	$conf=$row->[1] || "not recorded" ;
	$stage=$row->[2] || "unknown";
	$changed_this_run = $row->[3];
	$changed_since_success = $row->[4];
	$branch = $row->[5];
	my $log_file_names = $row->[6];
	$scm = $row->[7];
	$scm ||= 'cvs'; # legacy scripts
	$scmurl = $row->[8];
	$log_file_names =~ s/^\{(.*)\}$/$1/;
	@log_file_names=split(',',$log_file_names)
	    if $log_file_names;
	$sth->finish;

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
        # $sysinfo = join(" ",@$row);
	if ($latest_personality)
	{
	    $info_row->{os_version} = $latest_personality->[0];
	    $info_row->{compiler_version} = $latest_personality->[1];
	}
	$sth->finish;
	$db->disconnect;
}

foreach my $chgd ($changed_this_run,$changed_since_success)
{
	my $cvsurl = 'http://anoncvs.postgresql.org/cvsweb.cgi';
	my $giturl = $scmurl || 'http://git.postgresql.org/gitweb?p=postgresql.git;a=commit;h=';
    my @lines = split(/!/,$chgd);
    my $changed_rows = [];
    foreach (@lines)
    {
	next if ($scm eq 'cvs' and ! m!^(pgsql|master|REL\d_\d_STABLE)/!);
	push(@$changed_rows,[$1,$3]) if (m!(^\S+)(\s+)(\S+)!);
    }
    $chgd = $changed_rows;
}

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
		info_row => $info_row,

	});

