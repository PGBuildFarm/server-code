#!/usr/bin/perl

use strict;
use warnings;

use File::Copy;
use JSON::PP;

our ($template_dir, $local_git_clone);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

foreach my $branch_list (qw(branches_of_interest old_branches_of_interest))
{
	my $branches_of_interest = "$template_dir/../htdocs/$branch_list.txt";
	next unless -e $branches_of_interest;
	open(my $boi, "<", "$branches_of_interest")
	  || die "opening $branches_of_interest: $!";
	my @boi = <$boi>;
	close $boi;
	chomp @boi;

	chdir $local_git_clone;
	my $boi_ext = [];
	foreach my $branch (@boi)
	{
		my $format = '%h';
		my $ref = `git log -1 --format=$format $branch`;
		next if $?;
		chomp $ref;
		push @$boi_ext, { $branch => $ref };
	}
	
	chdir "$template_dir/../htdocs";
	open(my $ext_file,'>',"boiext.tmp") || die "opening file $!";
	my $json = JSON::PP->new->ascii->pretty->allow_nonref;
	print $ext_file $json->encode($boi_ext);
	close ($ext_file);
	move("boiext.tmp","$branch_list.json");
}
