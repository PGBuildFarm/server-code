#!/usr/bin/perl

use strict;

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut

use warnings;

print "Content-Type: text/plain\n\n";

use vars qw($envtestenabled);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};
require "$ENV{BFConfDir}/BuildFarmWeb.pl";

exit unless $envtestenabled;

print "Conf: $ENV{BFConfDir}\n";

print `pwd`;

print `id`;

foreach my $key (sort keys %ENV)
{
	my $val = $ENV{$key};
	print "$key=$val\n";
}
