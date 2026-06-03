

package BFUtils;

use strict;
use warnings;

## no critic (ProhibitAutomaticExportation)
use Exporter qw(import);
our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@EXPORT = qw( check_email_only livery );

sub check_email_only
{
	no warnings qw(once);
	return unless $main::email_only;
	print "Content-Type: text/plain\n\n",
	  "web display not available on this server\n";
	exit;
}

# Return the active site livery as a hashref (brand, colours, host, mail
# branding, ...). Liveries are defined by %liveries in BuildFarmWeb.pl and the
# active one is named by $livery there; fall back to 'build' if the selection
# is missing or unknown. Web templates receive this hashref as the 'livery'
# variable; the email/RSS scripts read it directly.
sub livery
{
	my ($name) = @_;
	no warnings qw(once);
	$name = $main::livery unless defined $name;
	$name = 'build'
	  unless defined $name && exists $main::liveries{$name};
	return $main::liveries{$name} || {};
}

1;
