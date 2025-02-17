#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use SOAP::Lite;
use CGI;

my $query = CGI->new;
my $netloc = $query->url(-base => 1);

my $obj = SOAP::Lite->uri("$netloc/PGBuildFarm")
  ->proxy("$netloc/cgi-bin/show_status_soap.pl");

my $data   = $obj->get_status->result;
my @fields = qw( branch sysname stage status
  operating_system os_version
  compiler compiler_version architecture
  when_ago snapshot build_flags
);

print "Content-Type: text/plain\n\n";

my $head = join(' | ', @fields);
print $head, "\n";

foreach my $datum (@$data)
{
        $datum->{build_flags} = join(',',@{$datum->{build_flags}}) if ref $datum->{build_flags};
	my $line = join(' | ', @{$datum}{@fields});
	print $line, "\n";
}

