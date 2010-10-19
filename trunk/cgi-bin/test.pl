#!/usr/bin/perl

#print "Content-Type: text/html\n\n";
#print "<h1>My quick perl hello</h1>";

use CGI;

my $query = new CGI;

my $url = $query->url();

my $base = $query->url(-base=>1);

print <<EOF;
Content-Type: text/plain


url = $url

base = $base

EOF


