

package BFUtils;

use strict;
use warnings;

## no critic (ProhibitAutomaticExportation)
use Exporter qw(import);
our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@EXPORT = qw( check_email_only normalize_build_flags );

sub check_email_only
{
	no warnings qw(once);
	return unless $main::email_only;
	print "Content-Type: text/plain\n\n",
	  "web display not available on this server\n";
	exit;
}

# Normalize a build_flags value for display. Takes the branch and the raw
# flags as fetched with pg_expand_array => 0 (i.e. a '{a,b,c}' style string,
# or undef) and returns a cleaned, space-separated string. Defaults that are
# no longer optional (integer datetimes, thread safety) are made explicit for
# the relevant branches, configure-style prefixes are stripped, and a handful
# of flag names are canonicalized. Callers wanting a list can split the result
# on whitespace.
sub normalize_build_flags
{
	my ($branch, $flags) = @_;
	$flags = '' unless defined $flags;

	$flags =~ s/^\{(.*)\}$/$1/;
	$flags =~ s/,/ /g;

	# enable-integer-datetimes is now the default
	if ($branch eq 'HEAD' || $branch gt 'REL8_3_STABLE')
	{
		$flags .= " --enable-integer-datetimes "
		  unless $flags =~ /--(en|dis)able-integer-datetimes/;
	}

	# enable-thread-safety is now the default
	if ($branch eq 'HEAD' || $branch gt 'REL8_5_STABLE')
	{
		$flags .= " --enable-thread-safety "
		  unless $flags =~ /--(en|dis)able-thread-safety/;
	}

	$flags =~ s/--((enable|with)-)?//g;
	$flags =~ s/libxml/xml/;
	$flags =~ s/libcurl/curl/;
	$flags =~ s/tap_tests/tap-tests/;
	$flags =~ s/injection_points/injection-points/;
	$flags =~ s/asserts/cassert/;
	$flags =~ s/\bssl\b/openssl/;
	$flags =~ s/\S+=\S+//g;
	$flags =~ s/^\s+//;
	$flags =~ s/\s+$//;

	return $flags;
}

1;
