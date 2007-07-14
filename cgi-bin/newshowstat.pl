#!/usr/bin/perl

use strict;

BEGIN
{
    $ENV{BFConfDir} ||= $ENV{HOME};
    require "$ENV{BFConfDir}/BuildFarmWeb.conf";
}

use lib $BuildFarmWeb::conf{libdir};

use BuildFarmWeb::Store qw(get_recent_status);

use CGI;
use Template;

my $template = new Template($BuildFarmWeb::conf{template_options});

my $query = new CGI;

my @members = $query->param('member');

my $statrows = get_recent_status(@members);

my $template_vars = {statrows=>$statrows};

print "Content-Type: text/html\n\n";
$template->process("dashboard.tt",$template_vars);




