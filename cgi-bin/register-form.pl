#!/usr/bin/perl

use strict;
use Template;
use Captcha::reCAPTCHA;

use vars qw( $captcha_pubkey );
require "$ENV{BFConfDir}/BuildFarmWeb.pl";


my $c = Captcha::reCAPTCHA->new;

my $captcha = $c->get_html($captcha_pubkey);


my $template = new Template({INCLUDE_PATH => '/home/community/pgbuildfarm/templates' });

print "Content-Type: text/html\n\n";


$template->process('register-form.tt',{captcha => $captcha});





