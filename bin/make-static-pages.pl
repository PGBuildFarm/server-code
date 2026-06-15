#!/usr/bin/perl

=comment

Copyright (c) 2003-2026, Andrew Dunstan

See accompanying License file for license details

Regenerate the static htdocs/index.html and htdocs/lists.html pages from the
index.tt and lists.tt templates, using the active site livery (see $livery and
%liveries in BuildFarmWeb.pl). Run this after switching the livery or editing
either template.

  BFConfDir=/path/to/conf perl bin/make-static-pages.pl /path/to/htdocs

=cut

use strict;
use warnings;

BEGIN
{
	$ENV{BFConfDir} ||= $ENV{BFCONFDIR};
	$ENV{BFCONFDIR} ||= $ENV{BFConfDir};
}
use lib "$ENV{BFConfDir}/perl5";
use BFUtils;
use Template;

use vars qw($template_dir);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

my $htdocs = shift @ARGV
  or die "usage: $0 <htdocs-directory>\n";

my $template = Template->new(
	{ INCLUDE_PATH => $template_dir, VARIABLES => { livery => livery() } });

foreach my $page ([ 'index.tt', 'index.html' ], [ 'lists.tt', 'lists.html' ])
{
	$template->process($page->[0], {}, "$htdocs/$page->[1]")
	  or die $template->error;
}

exit;
