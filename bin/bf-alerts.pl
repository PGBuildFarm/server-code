#!/usr/bin/perl

=comment

Copyright (c) 2003-2022, Andrew Dunstan

See accompanying License file for license details

=cut 

use strict;
use warnings;

use Digest::SHA qw(sha1_hex);
use MIME::Base64;
use DBI;
use DBD::Pg;
use Data::Dumper;
use Mail::Send;
use Storable qw(thaw);

use vars qw($dbhost $dbname $dbuser $dbpass $dbport_bin
  $all_stat $fail_stat $change_stat $green_stat
  $default_host $alerts_from $template_dir $ignore_branches_of_interest
);

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

# don't use configged dbuser/dbpass

$dbuser = "";
$dbpass = "";

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport_bin" if $dbport_bin;

my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my $clear_old = $db->do(
	q[

    DELETE FROM alerts
    WHERE sysname IN
      (SELECT name FROM buildsystems WHERE no_alerts or status <> 'approved')
			   ]
);

my $boilit               = '{}';
my $branches_of_interest = "$template_dir/../htdocs/branches_of_interest.txt";
if (-e $branches_of_interest && !$ignore_branches_of_interest)
{
	open(my $boi, "<", "$branches_of_interest")
	  || die "opening $branches_of_interest: $!";
	my @boi = <$boi>;
	close $boi;
	chomp @boi;
	$boilit = '{' . join(',', @boi) . '}';
	$db->do(q{delete from alerts where not (branch = any ($1))},
		undef, $boilit);
}

my $sth = $db->prepare(
	q[

    SELECT DISTINCT ON (sysname, branch) 
	 sysname, branch, 
	 extract(epoch from snapshot at time zone 'GMT')::int as snapshot, 
	 frozen_conf as config
    FROM build_status s join buildsystems b on (s.sysname = b.name)
    WHERE NOT b.no_alerts and
       b.status = 'approved' and
       snapshot > current_timestamp - interval '30 days'
       and (array_length($1::text[],1) = 0 or branch = any ($1))
    ORDER BY sysname, branch, snapshot desc

			  ]
);

$sth->execute($boilit);

my @last_heard;

while (my $row = $sth->fetchrow_hashref)
{
	push(@last_heard, $row);
}

$sth->finish;

my $sql = q[

   SELECT sysname, branch, 
	    extract(epoch from first_alert) as first_alert, 
	    extract(epoch from last_notification) as last_notification
   FROM alerts

	    ];

my $alerts = $db->selectall_hashref($sql, [ 'sysname', 'branch' ]);

my @need_cleared;
my @need_alerts;

my $clear_sth = $db->prepare(
	q[

  DELETE FROM alerts
  WHERE sysname = ?
  AND branch = ?
		      ]
);

my $update_sth = $db->prepare(
	q[

  UPDATE alerts
  SET last_notification = timestamp '1970-01-01' + ( interval '1 second' * $1)
  WHERE sysname = $2
  AND branch = $3
		      ]
);

my $insert_sth = $db->prepare(
	q[

  INSERT INTO alerts ( sysname, branch, first_alert, last_notification )
  VALUES ($1, $2,  
	  timestamp '1970-01-01' + ( interval '1 second' * $3),
	  timestamp '1970-01-01' + ( interval '1 second' * $4))
		      ]
);


my $now = time;
my $lts = scalar(localtime);
print "starting alert run: $lts\n";

foreach my $sysbranch (@last_heard)
{
	# not all versions of DBD::Pg decode modern bytea literals nicely. cope.
	$sysbranch->{config} =~ s/^(\\?x)([a-fA-F0-9]+)$/pack('H*',$2)/e;


	my $client_conf = thaw $sysbranch->{config};

	my %client_alert_settings = %{ $client_conf->{alerts} || {} };
	my $setting = $client_alert_settings{ $sysbranch->{branch} };
	unless ($setting && $setting->{alert_after} && $setting->{alert_every})
	{
		# if no valid setting, clear any alert and keep going
		if ($alerts->{ $sysbranch->{sysname} }->{ $sysbranch->{branch} })
		{
			$clear_sth->execute($sysbranch->{sysname}, $sysbranch->{branch});
			push(@need_cleared, [$sysbranch]);
		}
		next;
	}

	# ok, we have valid settings. should the alert be on?
	my $hours_since_heard = ($now - $sysbranch->{snapshot}) / 3600;

	# yep
	print
	  "have settings for $sysbranch->{sysname}:$sysbranch->{branch} ",
	  "hours since heard = $hours_since_heard, ",
	  "setting = $setting->{alert_after} / $setting->{alert_every} \n";

	if ($hours_since_heard > $setting->{alert_after})
	{
		my $known_alert =
		  $alerts->{ $sysbranch->{sysname} }->{ $sysbranch->{branch} };
		if ($known_alert
			&& ($now - (3600 * $setting->{alert_every})) >
			$known_alert->{last_notification})
		{
			# check if it's too old - 15 days and twice initial seems plenty
			if (   $hours_since_heard > 360
				&& $hours_since_heard > 2 * $setting->{alert_after})
			{
				print "alert is too old ... giving up\n";
				next;
			}

			# old alert, but time to alert again
			print "alert is on, but time to alert again\n";
			$update_sth->execute($now, $sysbranch->{sysname},
				$sysbranch->{branch},);
			push(@need_alerts, [ $sysbranch, $setting ]);
			print "alert updated\n";
		}
		elsif (!$known_alert)
		{
			# new alert
			print "new alert needed\n";
			$insert_sth->execute($sysbranch->{sysname}, $sysbranch->{branch},
				$now, $now);
			print "new record inserted\n";
			push(@need_alerts, [ $sysbranch, $setting ]);
		}
	}

	# nope, so clear the alert if it exists
	elsif ($alerts->{ $sysbranch->{sysname} }->{ $sysbranch->{branch} })
	{
		print "clear exisiting alerts";
		$clear_sth->execute($sysbranch->{sysname}, $sysbranch->{branch});
		push(@need_cleared, [ $sysbranch, $setting ]);
	}

}

print "start emails\n";

my $addr_sth = $db->prepare(
	q[

  SELECT owner_email
  FROM buildsystems
  WHERE name = ?
		 ]
);


my $me = `id -un`;
chomp $me;
my $host = `hostname`;
chomp($host);
$host = $default_host unless ($host =~ m/[.]/ || !defined($default_host));

my $from_addr = "PG Build Farm <$me\@$host>";
$from_addr =~ tr /\r\n//d;

$from_addr = $alerts_from if $alerts_from;

foreach my $clearme (@need_cleared)
{
	my ($sysbranch, $setting) = @$clearme;
	my ($animal, $branch) = ($sysbranch->{sysname}, $sysbranch->{branch});
	my $text;
	if ($setting)
	{
		my $hours = sprintf("%.2f", ($now - $sysbranch->{snapshot}) / 3600);
		$text = "$sysbranch->{sysname} has now reported "
		  . "on $sysbranch->{branch} $hours hours ago.";
	}
	else
	{
		$text = "$sysbranch->{sysname} has lost alarm settings on branch: "
		  . "$sysbranch->{branch}. Resetting alarm to off.";
	}
	my $msg = Mail::Send->new;

	$msg->set('From', $from_addr);

	$addr_sth->execute($animal);

	my $mailto = $addr_sth->fetchrow_array;

	print "sending clear to $mailto\n";

	# $sth->finish;

	$msg->to($mailto);
	$msg->set('Auto-Submitted',           'auto-generated');
	$msg->set('X-Auto-Response-Suppress', 'all');

	$msg->subject("PGBuildfarm member $animal Branch $branch Alert cleared");
	my $fh = $msg->open("sendmail", "-f $from_addr");
	print $fh "\n\n$text\n";
	$fh->close;

	print "alert cleared $animal $branch\n";
}

foreach my $needme (@need_alerts)
{
	my ($sysbranch, $setting) = @$needme;
	my ($animal, $branch) = ($sysbranch->{sysname}, $sysbranch->{branch});
	my $hours = sprintf("%.2f", ($now - $sysbranch->{snapshot}) / 3600);
	my $text = "$sysbranch->{sysname} has not reported "
	  . "on $sysbranch->{branch} for $hours hours.";
	my $msg = Mail::Send->new;

	$msg->set('From', $from_addr);

	$addr_sth->execute($animal);

	my ($mailto) = $addr_sth->fetchrow_array;

	# $sth->finish;

	print "sending alert to $mailto\n";

	$msg->to($mailto);
	$msg->set('Auto-Submitted',           'auto-generated');
	$msg->set('X-Auto-Response-Suppress', 'all');

	$msg->subject(
		"PGBuildfarm member $animal Branch $branch " . "Alert notification");
	my $fh = $msg->open("sendmail", "-f $from_addr");
	print $fh "\n\n$text\n";
	$fh->close;

	print "alert sent $animal $branch\n";
}


print "=================================\n";
