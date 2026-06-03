

package BFUtils;

use strict;
use warnings;

## no critic (ProhibitAutomaticExportation)
use Exporter qw(import);
our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@EXPORT = qw( check_email_only livery normalize_build_flags
  setup_die_handler print_http_header );

# Set once the response body (or its headers) has begun, so the die handler
# installed by setup_die_handler() knows not to emit a second set of headers.
our $http_header_sent = 0;

sub check_email_only
{
	no warnings qw(once);
	return unless $main::email_only;
	print_http_header("Content-Type: text/plain\n\n");
	print "web display not available on this server\n";
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

# Print a CGI response header (or any leading response output) and record
# that the response has begun. Use this in preference to a bare print for
# the header so that setup_die_handler() can avoid corrupting an
# already-started response with a second set of headers.
sub print_http_header
{
	print @_;
	$http_header_sent = 1;
	return;
}

# Install a $SIG{__DIE__} handler suitable for the CGI scripts. An uncaught
# die produces a generic HTTP 500 response to the client and logs the real
# error to STDERR (the server error log), instead of letting the web server
# return a bare "Premature end of script headers" 500 with nothing useful
# for the client. Dies thrown inside an eval are left untouched so that
# normal exception handling (Template's EVAL_PERL, DBI, ...) still works,
# and once the response body has begun we only log, to avoid emitting a
# second set of headers.
sub setup_die_handler
{
	## no critic (RequireLocalizedPunctuationVars)
	$SIG{__DIE__} = sub {
		my $err = shift;

		# Let exceptions thrown inside an eval propagate normally.
		return if $^S;

		chomp $err;

		# The real error is for the server log only, never the client.
		print STDERR "fatal: $err\n";

		unless ($http_header_sent)
		{
			print "Status: 500 Internal Server Error\n";
			print "Content-Type: text/plain\n\n";
			print "The server encountered an internal error and "
			  . "could not complete your request.\n";
		}
		exit 1;
	};
	return;
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
