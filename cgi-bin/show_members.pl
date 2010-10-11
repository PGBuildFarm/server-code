#!/usr/bin/perl

use strict;
use CGI;
use DBI;
use Template;



use vars qw($dbhost $dbname $dbuser $dbpass $dbport $sort_by);


require "$ENV{BFConfDir}/BuildFarmWeb.pl";
#require "BuildFarmWeb.pl";

my $query = new CGI;
my %sort_ok = ('name' => 'lower(name)' , 
	       'owner' => 'lower(owner_email)', 
	       'os' => 'lower(operating_system), os_version', 
	       'compiler' => 'lower(compiler), compiler_version' ,
	       'arch' => 'lower(architecture)' );
$sort_by = $query->param('sort_by');$sort_by =~ s/[^a-zA-Z0-9_ -]//g;
$sort_by = $sort_ok{$sort_by} || $sort_ok{name};

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $db = DBI->connect($dsn,$dbuser,$dbpass);

# there is possibly some redundancy in this query, but it makes
# a lot of the processing simpler.

my $statement = <<EOS;

  select name, operating_system, os_version, compiler, compiler_version, owner_email, 
    architecture as arch, ARRAY(
				select branch || ':' || 
				       extract(days from now() - latest_snapshot)
				from build_status_latest l 
				where l.sysname = s.name
				order by branch <> 'HEAD', branch desc 
				) as branches 
  from buildsystems s
  where status = 'approved'
  order by $sort_by

EOS
;

my $statrows=[];
my $sth=$db->prepare($statement);
$sth->execute;
while (my $row = $sth->fetchrow_hashref)
{
    $row->{branches} =~ s/^\{(.*)\}$/$1/;
    $row->{owner_email} =~ s/\@/ [ a t ] /;
    push(@$statrows,$row);
}
$sth->finish;


$db->disconnect;

# use Data::Dumper; print "Content-Type: text/plain\n\n",Dumper($statrows),"VERSION: ",$DBD::Pg::VERSION,"\n"; exit;


my $template = new Template({});

print "Content-Type: text/html\n\n";

$template->process(\*DATA,{statrows=>$statrows});

exit;


__DATA__
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
	<title>PostgreSQL BuildFarm Members</title>
	<link rel="icon" type="image/png" href="/elephant-icon.png" />
	<link rel="stylesheet" rev="stylesheet" href="/inc/pgbf.css" charset="utf-8" />
	<style type="text/css"><!--
	li#members a { color:rgb(17,45,137); background: url(/inc/b/r.png) no-repeat 100% -20px; } 
	li#members { background: url(/inc/b/l.png) no-repeat 0% -20px; }
	--></style>
   </style>
</head>
<body class="members">
<div id="wrapper">
<div id="banner">
<a href="/index.html"><img src="/inc/pgbuildfarm-banner.png" alt="PostgreSQL BuildFarm" width="800" height="73" /></a>
<div id="nav">
<ul>
    <li id="home"><a href="/index.html" title="PostgreSQL BuildFarm Home">Home</a></li>
    <li id="status"><a href="/cgi-bin/show_status.pl" title="Current results">Status</a></li>
    <li id="members"><a href="/cgi-bin/show_members.pl" title="Platforms tested">Members</a></li>
    <li id="register"><a href="/cgi-bin/register-form.pl" title="Join PostgreSQL BuildFarm">Register</a></li>
    <li id="pgfoundry"><a href="http://pgfoundry.org/projects/pgbuildfarm/">PGFoundry</a></li>
</ul>
</div><!-- nav -->
</div><!-- banner -->
<div id="main">
<h1>PostgreSQL BuildFarm Members</h1>
    <p>Click branch links to see build history. Click the heading links to resort the list. Select members by checkbox and hit the button at the bottom to create a status custom filter.</p>
    <form name="filter" method="GET" action="/cgi-bin/show_status.pl">
    <table cellspacing="0">
    <tr>
    <td>&nbsp;</td>
    <th><a href="/cgi-bin/show_members.pl?sort_by=name">Name</a><br /><a href="/cgi-bin/show_members.pl?sort_by=owner">Owner</a></th>
    <th><a href="/cgi-bin/show_members.pl?sort_by=os">OS / Version</a></th>
    <th><a href="/cgi-bin/show_members.pl?sort_by=compiler">Compiler / Version</a></th>
    <th><a href="/cgi-bin/show_members.pl?sort_by=arch">Arch</a></th>
    <th>Branches reported on<br />(most recent report)</th>
    </tr>
[% alt = true %]
[% FOREACH row IN statrows ;
    have_recent = 0;
    FOREACH branch_days IN row.branches.split(',') ;
       branch_fields = branch_days.split(':');
       branch_day = branch_fields.1;
       IF branch_day < 365 ; have_recent = 1; END;
    END;
 IF have_recent ;
%]    <tr [%- IF alt %]class="alt"[% END -%]>
    [% alt = ! alt %]
    <td><input type="checkbox" name="member" value="[% row.name %]" /></td>
    <td>[% row.name %]<br />[% row.owner_email %]</td>
    <td>[% row.operating_system %]<br />[% row.os_version %]</td>
    <td>[% row.compiler %]<br />[% row.compiler_version %]</td>
    <td>[% row.arch %]</td>
    <td class="branch">[% IF ! row.branches ; '&nbsp;' ; END -%]
    <ul>
    [%- 
       FOREACH branch_days IN row.branches.split(',') ;
       branch_fields = branch_days.split(':');
       branch = branch_fields.0;
       branch_day = branch_fields.1;
       IF branch_day < 365 ;
    %]<li><a 
    href="show_history.pl?nm=[% row.name %]&amp;br=[% branch %]"
    title="History"
    >[% branch %]</a>&nbsp;([% branch_day %]&nbsp;days&nbsp;ago)</li>[% END; END %]</ul></td>
    </tr>
[% END; END %]
    </table>
    <input type="submit" value="Make Filter" />
    </form>
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








