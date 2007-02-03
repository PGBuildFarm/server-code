#!/usr/bin/perl

use strict;
use DBI;
use Template;
use CGI;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $query = new CGI;
my @members = $query->param('member');
map { s/[^a-zA-Z0-9_ -]//g; } @members;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn,$dbuser,$dbpass) or die("$dsn,$dbuser,$dbpass,$!");

# there is possibly some redundancy in this query, but it makes
# a lot of the processing simpler.

my $statement = <<EOS;

  select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago,
      sysname, snapshot, b.status, stage, branch, build_flags,
      operating_system, os_version, compiler, compiler_version, architecture 
  from buildsystems s, 
       build_status b
       natural join 
       (select sysname, branch, max(snapshot) as snapshot
        from build_status
        group by sysname, branch
	having max(snapshot) > now() - '30 days'::interval
       ) m
  where name = sysname
        and s.status = 'approved'
  order by branch = 'HEAD' desc, 
        branch desc, 
        snapshot desc

EOS
;

$statement =<<EOS;


  select (now() at time zone 'GMT')::timestamp(0) - snapshot as when_ago,
      	sysname, snapshot, b.status, stage, branch, build_flags,
      	operating_system, coalesce(b.os_version,s.os_version) as os_version,
      	compiler, coalesce(b.compiler_version, s.compiler_version) as compiler_version, 
	architecture 
  from buildsystems s, 
        (
	select distinct on (bs.sysname, bs.branch, bs.report_time) 
               sysname, snapshot, status, stage, branch, build_flags,
               report_time ,compiler_version, os_version
        from build_status bs
             left join 
             personality p
             on (p.name = bs.sysname and p.effective_date <= bs.report_time)
        order by bs.sysname, bs.branch, bs.report_time, 
                 p.effective_date is null, p.effective_date desc
        ) as b
	natural join 
       	(select sysname, branch, max(snapshot) as snapshot
        from build_status
        group by sysname, branch
    	having max(snapshot) > now() - '30 days'::interval
       	) m
  where name = sysname
        and s.status = 'approved'
  order by branch = 'HEAD' desc,
        branch desc, 
        snapshot desc



EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute;
while (my $row = $sth->fetchrow_hashref)
{
    next if (@members && ! grep {$_ eq $row->{sysname} } @members);
    $row->{build_flags}  =~ s/^\{(.*)\}$/$1/;
    $row->{build_flags}  =~ s/,/ /g;
    $row->{build_flags}  =~ s/--((enable|with)-)?//g;
    $row->{build_flags}  =~ s/\S+=\S+//g;
    push(@$statrows,$row);
}
$sth->finish;


$db->disconnect;

my $template = new Template({});

print "Content-Type: text/html\n\n";

$template->process(\*DATA,{statrows=>$statrows});

exit;

=comment

[%- BLOCK img ; flag ; END -%]
[%- BLOCK imgx ; IF flag_imgs.$flag ; '<img src="' . flag_imgs{flag} . '" alt="' . flag . '" /> ' ; ELSE flag . ' ' ; END ; END -%]

=cut

__DATA__
[%
 flag_imgs = {
     perl = '/img/camel.png',
     python = '/img/python.png',
     debug = '/img/bug.png',
     pam => '/img/pam.png',
     cassert => '/img/cassert.png',
     openssl => '/img/ssl_icon.gif',
     nls => '/img/translateicon.gif',
     krb5 => '/img/krb.gif',
     tcl => '/img/tcl.png',
     xml => '/img/xml.png',
     'thread-safety' => '/img/threads.gif',
     'integer-datetimes' = '/img/days.png',
     }
-%]
[%- BLOCK img ; IF flag == 'depend' or flag == 'gnu-ld' ; ; ELSIF flag_imgs.$flag %]<img src="[% flag_imgs.$flag %]" title="[% flag %]" alt="[% flag %]" height="16" width="16" class="inline" align="bottom" />  [% ELSE %][%#
																									  flag ; ' '
%][% END ; END -%]
[%- BLOCK cl %] class=" [% SWITCH bgfor -%]
  [%- CASE 'OK' %]pass[% CASE 'ContribCheck' %]warn[% CASE [ 'Check' 'InstallCheck' ] %]warnx[% CASE %]fail[% END %]"
[%- END -%]
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <title>PostgreSQL BuildFarm Status</title>
<link rel="icon" type="image/png" href="/elephant-icon.png" />	
    <link rel="stylesheet" rev="stylesheet" href="/inc/pgbf.css" charset="utf-8" />
	<style type="text/css"><!--
	li#status a { color:rgb(17,45,137); background: url(/inc/b/r.png) no-repeat 100% -20px; } 
	li#status { background: url(/inc/b/l.png) no-repeat 0% -20px; }
	--></style>
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
    <li id="postgresql.org"><a href="http://www.postgresql.org">PostgreSQL.org</a></li>
</ul>
</div><!-- nav -->
</div><!-- banner -->
<div id="main">
    <h1>PostgreSQL BuildFarm Status</h1>
    <p>
      Shown here is the latest status of each farm member 
      for each branch it has reported on in the last 30 days.
    </p>
    <p>
       Use the farm member link for history of that member 
       on the relevant branch.
    </p>
<table><tr><th class="head" rowspan="2">Legend</th>
[% FOREACH flagset IN flag_imgs %]
<td><img src="[% flagset.value %]" title="[% flagset.key %]" alt="[% flagset.key %]" height="16" width="16" class="inline"  align="center"/> =  [% flagset.key %]</td>
[% IF loop.count == 5 %]</tr><tr>[% END %]
[% END %]
</tr></table>
<br />
    <table cellspacing="0">
[% brch = "" %]
[% FOREACH row IN statrows %]
[% IF row.branch != brch ; brch = row.branch %]
<tr><th class="head" colspan="4">Branch: [% brch %]</th></tr>
<tr><th>Alias</th><th>System</th><th>Status</th><th>Flags</th></tr>
[% END %]
<tr [% PROCESS cl bgfor=row.stage %]>
    <td><a 
    href="show_history.pl?nm=[% row.sysname %]&amp;br=[% row.branch %]"
    title="History"
    >[% row.sysname %]</a></td>
    <td><span class="opsys">[% row.operating_system %]
            [% row.os_version %]</span> <span class="compiler">
            [%- row.compiler %]
            [% row.compiler_version %]</span> <span class="arch">
            [%- row.architecture %]</span></td>
    <td class="status">
            [%- row.when_ago | replace('\s','&nbsp;') %]&nbsp;ago&nbsp;
            [% row.stage -%]
            <a href="show_log.pl?nm=
               [%- row.sysname %]&amp;dt=
               [%- row.snapshot | uri %]">
                [%- IF row.stage != 'OK' %]Details[% ELSE %]Config[% END -%]</a></td>

    <td class="flags">[% FOREACH flag IN row.build_flags.split().sort() ; PROCESS img ; END %]</td>
</tr>
[% END %]
    </table>
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








