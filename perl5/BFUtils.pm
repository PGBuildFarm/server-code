

package BFUtils;

use strict;
use warnings;

## no critic (ProhibitAutomaticExportation)
use Exporter qw(import);
our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@EXPORT = qw( check_email_only );

sub check_email_only
{
	no warnings qw(once);
	return unless $main::email_only;
	print "Content-Type: text/plain\n\n",
	  "web display not available on this server\n";
	exit;
}

1;
