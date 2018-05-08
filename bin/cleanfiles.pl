#! /usr/bin/perl -w
    eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
        if 0; #$running_under_some_shell

use strict;
use warnings;

use File::Find ();

# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name   = *File::Find::name;
*dir    = *File::Find::dir;
*prune  = *File::Find::prune;

sub wanted;

my @files;

# Traverse desired filesystems
File::Find::find({wanted => \&wanted}, 
    '/home/pgbuildfarm/website/buildlogs');

foreach my $fname (@files)
{
    next unless -e $fname;
    unlink($fname) || warn "$fname: $!";
}

exit;

## no critic (ValuesAndExpressions::ProhibitFiletest_f)

sub wanted {
    my ($dev,$ino,$mode,$nlink,$uid,$gid);

    (($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_)) &&
    (int(-M _) > 7) &&
#    ( -M _ > 0.05 ) && # 1.2 hours
    -f _ &&
    push(@files,$name);
	return;
}
