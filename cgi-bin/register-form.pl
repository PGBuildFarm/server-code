#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use lib "$ENV{BFCONFDIR}/perl5";
use BFUtils;

use Template;
use CGI;


use vars qw( $template_dir $captcha_invis_pubkey $skip_captcha $email_only);
$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

check_email_only();

my $template_opts = { INCLUDE_PATH => $template_dir };
my $template = Template->new($template_opts);

my $cgi = CGI->new();
print "Content-Type: text/html\n\n";

$template->process(
	'register-form.tt',
	{
		skip_captcha      => $skip_captcha,
		captcha_publickey => $captcha_invis_pubkey,
		cgi               => $cgi
	}
);

