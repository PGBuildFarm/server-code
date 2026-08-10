package PatchStackLog;

use strict;
use warnings;

## no critic (ProhibitAutomaticExportation)
use Exporter qw(import);
our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@EXPORT = qw( parse_patch_stack_log diff_patch_stack );

# Parse the structured patch_stack.log artifact written by
# PGBuild::Modules::PatchStack (client-side): "key: value" header lines
# followed by one line per patch, in series order.
#
# Format 1, written by clients before the blob-SHA change, has two
# tab-separated fields per patch line: name and subject. Format 2
# announces itself with a "patch_stack_format: 2" header and has three:
# name, blob SHA, subject. The SHA is what lets diff_patch_stack() below
# report a patch whose content changed under an unchanged filename,
# which format 1 gives no way to detect.
#
# Header lines carry no tab, and the parser depends on that in the
# other direction: it is why a server that predates a given key skips
# it rather than mistaking it for a patch row. Any key added later must
# keep that property.
sub parse_patch_stack_log
{
	my $text = shift;
	return unless defined $text && $text ne '';

	my @lines = split(/\n/, $text);

	# Settle the format before interpreting any patch line; the marker
	# is written first but nothing requires it to stay that way.
	my $format = 1;
	foreach my $line (@lines)
	{
		$format = $1 if $line =~ /^patch_stack_format:\s?(\d+)/;
	}

	my %info = (format => $format);
	my @patches;

	foreach my $line (@lines)
	{
		if ($line =~ /^patch_stack_(id|commit|source|status):\s?(.*)$/)
		{
			$info{$1} = $2;
			next;
		}

		# Any other patch_stack_* key, known or not, is not a patch row.
		next if $line     =~ /^patch_stack_\w+:/;
		next unless $line =~ /\t/;

		if ($format >= 2)
		{
			my ($name, $sha, $subject) = split(/\t/, $line, 3);

			# The limit of 3 keeps a tab inside the subject intact. A
			# format-2 line short of a field is read the old way rather
			# than yielding a silently undefined SHA.
			if (defined $subject)
			{
				push(@patches,
					{ name => $name, sha => $sha, subject => $subject });
				next;
			}
		}

		my ($name, $subject) = split(/\t/, $line, 2);
		push(@patches, { name => $name, sha => undef, subject => $subject });
	}

	$info{patches} = \@patches;
	return \%info;
}

# Compare two parsed patch_stack.log structures. Reports patch filenames
# added and removed and -- when both runs carry blob SHAs -- filenames
# whose content changed. Returns undef when nothing moved.
#
# The identity short-circuit keeps out noise from e.g. a subject line
# changing while the series itself is untouched.
#
# When either side predates format 2 there are no SHAs to compare, so
# modifications are simply not reported. That under-reports across a
# client upgrade rather than claiming a change that may not have
# happened.
#
# A filename listed twice in one series collapses in these hashes and is
# not distinguished. That limitation predates this code and is unchanged.
sub diff_patch_stack
{
	my ($cur, $prev) = @_;

	my $cur_id  = defined $cur->{id}  ? $cur->{id}  : '';
	my $prev_id = defined $prev->{id} ? $prev->{id} : '';
	return if $cur_id eq $prev_id;

	my %cur_sha  = map { $_->{name} => $_->{sha} } @{ $cur->{patches} };
	my %prev_sha = map { $_->{name} => $_->{sha} } @{ $prev->{patches} };

	my @added   = sort grep { !exists $prev_sha{$_} } keys %cur_sha;
	my @removed = sort grep { !exists $cur_sha{$_} } keys %prev_sha;

	my @modified;
	foreach my $name (sort keys %cur_sha)
	{
		next unless exists $prev_sha{$name};
		next unless defined $cur_sha{$name} && defined $prev_sha{$name};
		next if $cur_sha{$name} eq $prev_sha{$name};
		push(
			@modified,
			{
				name => $name,
				from => $prev_sha{$name},
				to   => $cur_sha{$name}
			}
		);
	}

	return unless @added || @removed || @modified;
	return {
		added    => \@added,
		removed  => \@removed,
		modified => \@modified
	};
}

1;
