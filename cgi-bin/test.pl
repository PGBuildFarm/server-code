#!/usr/bin/perl

#print "Content-Type: text/html\n\n";
#print "<h1>My quick perl hello</h1>";

use strict;
use warnings;

use CGI;

my $query = CGI->new;

my $url = $query->url();

my $base = $query->url(-base=>1);

print <<"EOF";
Content-Type: text/plain


url = $url

base = $base

EOF

