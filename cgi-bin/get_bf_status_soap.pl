#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut 

use SOAP::Lite +trace;

my $obj = SOAP::Lite
    ->uri('http://www.pgbuildfarm.org/PGBuildFarm')
    ->proxy('http://127.0.0.1/cgi-bin/show_status_soap.pl')
    ->request->header("Host" => "www.pgbuildfarm.org")
    ;

my $data = $obj->get_status->result;
my @fields = qw( branch sysname stage status 
                                 operating_system os_version
                                 compiler compiler_version architecture
                                 when_ago snapshot build_flags
		 );

print "Content-Type: text/plain\n\n";

my $head = join (' | ', @fields);
print $head,"\n";

foreach my $datum (@$data)
{
    my $line = join (' | ', @{$datum}{@fields});
    print $line,"\n";
}

