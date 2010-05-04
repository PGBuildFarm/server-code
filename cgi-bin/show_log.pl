#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;
use URI::Escape;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport @log_file_names);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";
#require "BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $query = new CGI;

my $system = $query->param('nm'); $system =~ s/[^a-zA-Z0-9_ -]//g;
my $logdate = $query->param('dt'); $logdate =~ s/[^a-zA-Z0-9_ -]//g;

my $log = "";
my $conf = "";
my ($stage,$changed_this_run,$changed_since_success,$sysinfo,$branch,$scmurl);
my $scm;

use vars qw($info_row);

if ($system && $logdate)
{

	my $db = DBI->connect($dsn,$dbuser,$dbpass);

	die $DBI::errstr unless $db;

	my $statement = <<EOS;

  select log,conf_sum,stage, changed_this_run, changed_since_success,branch,
      log_archive_filenames, scm, scmurl
  from build_status
  where sysname = ? and snapshot = ?

EOS
;
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

	$statement = <<EOS;

          select operating_system, os_version, 
                 compiler, compiler_version, 
                 architecture,
		 replace(owner_email,'\@',' [ a t ] ') as owner_email,
		 sys_notes_ts::date AS sys_notes_date, sys_notes
          from buildsystems 
          where status = 'approved'
                and name = ?

EOS
;
	$sth=$db->prepare($statement);
	$sth->execute($system);
	$info_row=$sth->fetchrow_hashref;
        # $sysinfo = join(" ",@$row);
	$sth->finish;
	$db->disconnect;
}

foreach my $chgd ($changed_this_run,$changed_since_success)
{
	my $cvsurl = 'http://anoncvs.postgresql.org/cvsweb.cgi';
	my $giturl = $scmurl || 'http://git.postgresql.org/gitweb?p=postgresql.git;a=commit;h=';
    my @lines = split(/!/,$chgd);
    foreach (@lines)
    {
		if ($scm eq 'git')
		{
			s!(^\S+)(\s+)(\S+)!<a href="$giturl$3">$1</a>!;
		}
		elsif ($scm eq 'cvs')
		{
			next unless m!^pgsql/!;
			s!(^\S+)(\s+)(\S+)!<a href="$cvsurl/$1?rev=$3">$1$2$3</a>!;
		}
    }
    $chgd = join("\n",@lines);
    $chgd ||= 'not recorded';
	
}

$conf =~ s/\@/ [ a t ] /g;
map {s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g; s/\"/&quot;/g;} ($log,$conf);
# map {s/!/\n/g} ($changed_this_run,$changed_since_success);


use POSIX qw(ceil);
my $lrfactor = 6;
my $logrows = ceil(scalar(@log_file_names)/$lrfactor);
my $logcells = $lrfactor * $logrows;

my $heading_done;
my $urldt = uri_escape($logdate);

my $cell = 0;



print "Content-Type: text/html\n\n";

if ($stage eq 'OK')
{
	print <<EOHTML;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <title>PostgreSQL BuildFarm | Configuration summary for system "$system"</title>
	<link rel="icon" type="image/png" href="/elephant-icon.png" />
    <link rel="stylesheet" rev="stylesheet" href="/inc/pgbf.css" charset="utf-8" />
</head>
<body>
<div id="wrapper">
<div id="banner">
<a href="/index.html"><img src="/inc/pgbuildfarm-banner.png" alt="PostgreSQL BuildFarm" width="800" height="73" /></a>
<div id="nav">
<ul>
    <li id="home"><a href="/index.html" title="PostgreSQL BuildFarm Home">Home</a></li>
    <li id="status"><a href="/cgi-bin/show_status.pl" title="Current results">Status</a></li>
    <li id="members"><a href="/cgi-bin/show_members.pl" title="Platforms tested">Members</a></li>
    <li id="register"><a href="/register.html" title="Join PostgreSQL BuildFarm">Register</a></li>
    <li id="pgfoundry"><a href="http://pgfoundry.org/projects/pgbuildfarm/">PGFoundry</a></li>
</ul>
</div><!-- nav -->
</div><!-- banner -->
<div id="main">
<h1>PostgreSQL Build Farm Log</h1>
<table align="top" cellspacing="0">
    <tr>
        <th class="head" rowspan="2">System Information</th>
        <th>Farm member</th>
        <th>Branch</th>
        <th>OS</th>
        <th>Compiler</th>
        <th>Architecture</th>
        <th>Owner</th>
    </tr>
    <tr>
        <td>$system</td>
        <td><a href="/cgi-bin/show_history.pl?nm=$system&amp;br=$branch">$branch</a></td>
        <td>$info_row->{operating_system} $info_row->{os_version}</td>
        <td>$info_row->{compiler} $info_row->{compiler_version}</td>
        <td>$info_row->{architecture}</td>
        <td>$info_row->{owner_email}</td>
    </tr>
    </table>
EOHTML

    if ($info_row->{sys_notes})
    {
        print <<EOHTML;
    <br />
    <table>
     <tr>
       <th class="head" rowspan="2">System Notes</th>
       <th>Date</th>
       <th>Notes</th>
     </tr>
     <tr>
      <td>$info_row->{sys_notes_date}</td>
      <td>$info_row->{sys_notes}</td>
     </tr>
   </table>
EOHTML

    }

for my $logstage (@log_file_names)
{
    print "<br /> <table><tr><th class='head' rowspan='$logrows'>Stage Logs</th>\n"
	unless $heading_done;
    $heading_done = 1;
    $cell++;
    $logstage =~ s/\.log$//;
    print "<tr>\n" if ($cell > 1 && $cell % $lrfactor == 1);
    print "<td><a href='show_stage_log.pl?nm=$system&amp;dt=$urldt&amp;stg=$logstage'>$logstage</a></td>\n";
    print "</tr>\n" if ($cell % $lrfactor == 0);
}

if ($cell)
{
    foreach my $rcell ($cell+1 .. $logcells)
    {
	print "<tr>\n" if ($rcell > 1 && $rcell % $lrfactor == 1);
	print "<td>&nbsp;</td>\n";
	print "</tr>\n" if ($rcell % $lrfactor == 0);
    }
    print "</table>\n";
}

print <<EOHTML;
</table>
<h2>Configuration summary for system "$system"</h2>
<h3>Status 'OK' on snapshot taken $logdate</h3>
<pre>
$conf
</pre>
<h3>Files changed this run</h3>
<pre>
$changed_this_run
</pre>
EOHTML
print <<EOHTML if ($log);
<h3>Log</h3>
<pre>
$log
</pre>
EOHTML
    print <<EOHTML;
</div><!-- main -->
<hr />
<p style="text-align: center;">
Hosting for the PostgreSQL Buildfarm is generously 
provided by: 
<a href="http://www.commandprompt.com">CommandPrompt, 
The PostgreSQL Company</a>
</p>
</div><!-- wrapper -->
</body>
</html>
EOHTML
;

	exit;
}

print <<EOHTML;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <title>PostgreSQL BuildFarm | Log for system "$system" failure on snapshot taken $logdate</title>
    <link rel="stylesheet" rev="stylesheet" href="/inc/pgbf.css" charset="utf-8" />
</head>
<body>
<div id="wrapper">
<div id="banner">
<a href="/index.html"><img src="/inc/pgbuildfarm-banner.png" alt="PostgreSQL BuildFarm" width="800" height="73" /></a>
<div id="nav">
<ul>
    <li id="home"><a href="/index.html" title="PostgreSQL BuildFarm Home">Home</a></li>
    <li id="status"><a href="/cgi-bin/show_status.pl" title="Status Page">Status</a></li>
    <li id="members"><a href="/cgi-bin/show_members.pl" title="Status Page">Members</a></li>
    <li id="register"><a href="/register.html" title="Register">Register</a></li>
    <li id="pgfoundry"><a href="http://pgfoundry.org/projects/pgbuildfarm/">PGFoundry</a></li>
</ul>
</div><!-- nav -->
</div><!-- banner -->
<div id="main">
    <h1>PostgreSQL Build Farm Log</h1>
<h1>Details for system "$system" failure at stage $stage on snapshot taken $logdate</h1>
<table cellspacing="0">
    <tr>
        <th class="head" rowspan="2">System Information</th>
        <th>Farm member</th>
        <th>Branch</th>
        <th>OS</th>
        <th>Compiler</th>
        <th>Architecture</th>
        <th>Owner</th>
    </tr>
    <tr>
        <td>$system</td>
        <td><a href="/cgi-bin/show_history.pl?nm=$system&amp;br=$branch">$branch</a></td>
        <td>$info_row->{operating_system} $info_row->{os_version}</td>
        <td>$info_row->{compiler} $info_row->{compiler_version}</td>
        <td>$info_row->{architecture}</td>
        <td>$info_row->{owner_email}</td>
    </tr>
  </table>
EOHTML

    if ($info_row->{sys_notes})
    {
        print <<EOHTML;
    <br />
    <table>
     <tr>
       <th class="head" rowspan="2">System Notes</th>
       <th>Date</th>
       <th>Notes</th>
     </tr>
     <tr>
      <td>$info_row->{sys_notes_date}</td>
      <td>$info_row->{sys_notes}</td>
     </tr>
   </table>
EOHTML

    }

for my $logstage (@log_file_names)
{
    print "<br /> <table><tr><th class='head' rowspan='4'>Stage Logs</th>\n"
	unless $heading_done;
    $heading_done = 1;
    $cell++;
    $logstage =~ s/\.log$//;
    print "<tr>\n" if ($cell > 1 && $cell % $lrfactor == 1);
    print "<td><a href='show_stage_log.pl?nm=$system&amp;dt=$urldt&amp;stg=$logstage'>$logstage</a></td>\n";
    print "</tr>\n" if ($cell % $lrfactor == 0);
}

if ($cell)
{
    foreach my $rcell ($cell+1 .. $logcells)
    {
	print "<tr>\n" if ($rcell > 1 && $rcell % $lrfactor == 1);
	print "<td>&nbsp;</td>\n";
	print "</tr>\n" if ($rcell % $lrfactor == 0);
    }
    print "</table>\n";
}

print <<EOHTML;
<h3>Configuration summary</h3>
<pre>
$conf
</pre>
<h3>Files changed this run</h3>
<pre>
$changed_this_run
</pre>
<h3>Files changed since last success</h3>
<pre>
$changed_since_success
</pre>
<h3>Log</h3>
<pre>
$log
</pre>
</div><!-- main -->
<hr />
<p style="text-align: center;">
Hosting for the PostgreSQL Buildfarm is generously 
provided by: 
<a href="http://www.commandprompt.com">CommandPrompt, 
The PostgreSQL Company</a>
</p>
</div><!-- wrapper -->
</body>
</html>
EOHTML
;




