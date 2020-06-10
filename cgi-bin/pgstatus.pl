#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport
  $all_stat $fail_stat $change_stat $green_stat
  $server_time
  $min_script_version $min_web_script_version
  $default_host $local_git_clone
  $status_from
  $status_url
  $skip_mail
  $skip_rss
  $ignore_branches_of_interest

);

# force this before we do anything - even load modules
BEGIN { $server_time = time; }

use CGI;
use Digest::SHA qw(sha1_hex sha256_hex);
use MIME::Base64;
use DBI;
use DBD::Pg;
use Data::Dumper;
use Mail::Send;
use Time::ParseDate;
use Storable qw(nfreeze thaw);
use JSON::PP;
use URI::Escape;
use Scalar::Util qw(looks_like_number);

# for RSS work
use XML::RSS;
use DateTime::Format::W3CDTF;
use File::Copy;
use Fcntl qw(:flock);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";
my $buildlogs = "$ENV{BFConfDir}/buildlogs";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $query = CGI->new;

# don't let people play games with GET requests - this should be called via POST
# the URL should only contain the signature
if ($query->request_method eq 'GET')
{
	print
	  "Status: 496 wrong request method\nContent-Type: text/plain\n\n",
	  "wrong request method\n";
	exit;
}

my $sig = $query->path_info;
$sig =~ s/[^0-9a-fA-F.]//g
  if $sig;    # must be hex digits or ".", also trim leading /

my $stage                 = $query->param('stage');
my $ts                    = $query->param('ts');
my $animal                = $query->param('animal');
my $log                   = $query->param('log');
my $res                   = $query->param('res');
my $conf                  = $query->param('conf');
my $branch                = $query->param('branch');
my $changed_since_success = $query->param('changed_since_success');
my $changed_this_run      = $query->param('changed_files');
my $log_archive           = $query->param('logtar');
my $frozen_sconf          = $query->param('frozen_sconf') || '';

my $txanimal = $animal || 'unknown';
$txanimal =~ s/[^a-zA-Z0-9_-]//g;    # no funky chars in filename
my $rawfilets = time;
my $rawtxfile = "$buildlogs/$txanimal.$rawfilets";

open(my $tx, ">", $rawtxfile) || die "opening $rawtxfile";
$query->save($tx);
close($tx);

unless ($animal
	&& looks_like_number($ts)
	&& $stage
	&& defined($sig)
	&& $branch
	&& defined($res))
{
	print
	  "Status: 490 bad parameters\nContent-Type: text/plain\n\n",
	  "bad parameters for request\n";
	exit;

}

my $brhandle;
if ((!$ignore_branches_of_interest)
	&& open($brhandle, "<", "../htdocs/branches_of_interest.txt"))
{
	my @branches_of_interest = <$brhandle>;
	close($brhandle);
	chomp(@branches_of_interest);
	unless (grep { $_ eq $branch } @branches_of_interest)
	{
		my $msgbranch = uri_escape($branch, "^A-Za-z0-9\-\._~/");
		print
		  "Status: 492 bad branch parameter\n",
		  "Content-Type: text/plain\n\n",
		  "bad branch parameter $msgbranch\n";
		exit;
	}
}

my $content =
	"branch=$branch&res=$res&stage=$stage&animal=$animal&"
  . "ts=$ts&log=$log&conf=$conf";

my $extra_content =
	"changed_files=$changed_this_run&"
  . "changed_since_success=$changed_since_success&";


my $db = DBI->connect($dsn, $dbuser, $dbpass);

die $DBI::errstr unless $db;

my ($raw_tables) = $db->selectrow_array(
	q(select count(*)
      from pg_class
      where relname = 'build_status_log_raw'));

my ($raw_suffix, $log_text_type) = $raw_tables ?
  ('_raw', DBD::Pg::PG_BYTEA) :
  ('' , DBD::Pg::PG_TEXT);

my $gethost =
  "select secret from buildsystems where name = ? and status = 'approved'";
my $sth = $db->prepare($gethost);
$sth->execute($animal);
my ($secret) = $sth->fetchrow_array();
$sth->finish;

my $tsdiff = time - $ts;

my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
  localtime($ts);
$year += 1900;
$mon  += 1;
my $date =
  sprintf("%d-%.2d-%.2d_%.2d:%.2d:%.2d", $year, $mon, $mday, $hour, $min, $sec);

if ($ENV{BF_DEBUG} || ($ts > time) || ($ts + 86400 < time) || (!$secret))
{
	my $logtar_len = defined($log_archive) ? length($log_archive) : 0;
	open(my $tx, ">", "$buildlogs/$txanimal.$date")
	  || die "opening $buildlogs/$txanimal.$date";
	print $tx "sig=$sig\nlogtar-len=$logtar_len",
	  "\nstatus=$res\nstage=$stage\nconf:\n$conf\n",
	  "tsdiff:$tsdiff\n",
	  "changed_this_run:\n$changed_this_run\n",
	  "changed_since_success:\n$changed_since_success\n",
	  "frozen_sconf:$frozen_sconf\n",
	  "log:\n", $log;
	close($tx);
}

unlink($rawtxfile) if -e $rawtxfile;

unless ($secret)
{
	my $msganimal = uri_escape($animal, "^A-Za-z0-9\-\._~/");
	print
	  "Status: 495 Unknown System\nContent-Type: text/plain\n\n",
	  "System $msganimal is unknown\n";
	$db->disconnect;
	exit;

}

my $orig_sig  = $sig;
my $calc_sig  = sha1_hex($content, $secret);
my $calc_sig2 = sha1_hex($extra_content, $content, $secret);
if (substr($sig, 0, 5) eq ".256.")
{
	$calc_sig2 = sha256_hex($extra_content, $content, $secret);
	$sig       = substr($sig, 5);
}

if ($calc_sig ne $sig && $calc_sig2 ne $sig)
{
	print "Status: 450 sig mismatch\nContent-Type: text/plain\n\n";
	print "$orig_sig mismatches $calc_sig($calc_sig2)\n";
	$db->disconnect;
	exit;
}

# undo escape-proofing of base64 data and decode it
do { tr/$@/+=/ if $_; $_ = decode_base64($_) if $_; }
  foreach ($log, $conf, $changed_this_run, $changed_since_success, $log_archive,
	$frozen_sconf);

my $config_flags;
my $client_conf;
if ($frozen_sconf)
{
	if ($frozen_sconf !~ /[[:cntrl:]]/)
	{
		# should be json, almost certainly not something frozen.
		$frozen_sconf = nfreeze(decode_json($frozen_sconf));
	}
	$client_conf = thaw $frozen_sconf;
}

# adjust snapshot timestamp for clock skew
# essentially this means we believe the client on how long the run took
# but we don't believe its clock setting
my $client_now = $client_conf->{current_ts};
my $skew       = 0;
if (defined $client_now)
{
	$skew = $server_time - $client_now;
	$client_conf->{clock_skew} = $skew;
	$ts += $skew;
}

# re-freeze after adding the skew setting
$frozen_sconf = nfreeze($client_conf);

unless ($ts < time + 120)
{
	my $gmt = gmtime($ts);
	print
	  "Status: 491 bad ts parameter - $ts ($gmt GMT) is in the future.\n",
	  "Content-Type: text/plain\n\n",
	  "bad ts parameter - $ts ($gmt GMT) is in the future\n";
	$db->disconnect;
	exit;
}

unless ($ts + 86400 > time
	|| ($client_conf->{config_env}->{CPPFLAGS} || "x") =~ /CLOBBER_CACHE/)
{
	my $gmt = gmtime($ts);
	print
	  "Status: 491 bad ts parameter - ",
	  "$ts ($gmt GMT) is more than 24 hours ago.\n",
	  "Content-Type: text/plain\n\n",
	  "bad ts parameter - $ts ($gmt GMT) is more than 24 hours ago.\n";
	$db->disconnect;
	exit;
}

=comment

# CLOBBER_CACHE_RECURSIVELY can takes forever to run, so omit the snapshot
# sanity check in such cases. Everything else needs to have been made with a
# snapshot that is no more than 24 hours older than the last commit on the
# branch.

if ($client_conf->{config_env}->{CPPFLAGS} !~ /CLOBBER_CACHE_RECURSIVELY/ &&
	$log =~/Last file mtime in snapshot: (.*)/)
{
    my $snaptime = parsedate($1);
    my $brch = $branch eq 'HEAD' ? 'master' : $branch;
    my $last_branch_time = time - (30 * 86400);
    $last_branch_time =
      `TZ=UTC GIT_DIR=$local_git_clone git log -1 --pretty=format:\%ct  $brch`;
    if ($snaptime < ($last_branch_time - 86400))
    {
	print "Status: 493 snapshot too old: $1\nContent-Type: text/plain\n\n";
	print "snapshot to old: $1\n";
	$db->disconnect;
	exit;	
    }
}

=cut

($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime($ts);
$year += 1900;
$mon  += 1;
my $dbdate =
  sprintf("%d-%.2d-%.2d %.2d:%.2d:%.2d", $year, $mon, $mday, $hour, $min, $sec);

my $log_file_names;
my @log_file_names;
my $dirname = "$buildlogs/tmp.$$.unpacklogs";

my $githeadref;

if ($log_archive)
{
	my $log_handle;
	my $archname = "$buildlogs/tmp.$$.tgz";
	open($log_handle, ">", $archname) || die "opening $archname";
	binmode $log_handle;
	print $log_handle $log_archive;
	close $log_handle;
	mkdir $dirname;
	@log_file_names = `tar -z -C $dirname -xvf $archname 2>/dev/null`;
	do { s/\s+//g; }

	  foreach @log_file_names;
	my @qnames = grep { $_ ne 'githead.log' } @log_file_names;
	do { $_ = qq("$_"); }
	  foreach @qnames;
	$log_file_names = '{' . join(',', @qnames) . '}';

	if (-e "$dirname/githead.log")
	{
		open(my $githead, "<", "$dirname/githead.log")
		  || die "opening $dirname/githead.log";
		$githeadref = <$githead>;
		chomp $githeadref;
		close $githead;
	}

	# unlink $archname;
}

if ($min_script_version)
{
	$client_conf->{script_version} ||= '0.0';
	my $cli_ver = $client_conf->{script_version};
	$cli_ver =~ s/^REL_//;
	my ($minmajor, $minminor) = split(/\./, $min_script_version);
	my ($smajor,   $sminor)   = split(/\./, $cli_ver);

	# provide for one part version numbers
	$minminor = 0 unless defined($minminor);
	$sminor   = 0 unless defined($sminor);

	if ($minmajor > $smajor || ($minmajor == $smajor && $minminor > $sminor))
	{
		print
		  "Status: 460 script version too low\nContent-Type: text/plain\n\n";
		print
		  "Script version is below minimum required\n",
		  "Reported version: $client_conf->{script_version},",
		  "Minumum version required: $min_script_version\n";
		$db->disconnect;
		exit;
	}
}

if (0 && $min_web_script_version)
{
	$client_conf->{web_script_version} ||= '0.0';
	my $cli_ver = $client_conf->{web_script_version};
	$cli_ver =~ s/^REL_//;
	my ($minmajor, $minminor) = split(/\./, $min_web_script_version);
	my ($smajor,   $sminor)   = split(/\./, $cli_ver);

	# provide for one part version numbers
	$minminor = 0 unless defined($minminor);
	$sminor   = 0 unless defined($sminor);

	if ($minmajor > $smajor || ($minmajor == $smajor && $minminor > $sminor))
	{
		print
		  "Status: 461 web script version too low\n",
		  "Content-Type: text/plain\n\n";
		print
		  "Web Script version is below minimum required\n",
		  "Reported version: $client_conf->{web_script_version}, ",
		  "Minumum version required: $min_web_script_version\n";
		$db->disconnect;
		exit;
	}
}

my @config_flags;
if (not exists $client_conf->{config_opts})
{
	@config_flags = ();
}
elsif (ref $client_conf->{config_opts} eq 'HASH')
{
	# leave out keys with false values
	@config_flags = grep { $client_conf->{config_opts}->{$_} }
	  keys %{ $client_conf->{config_opts} };
}
elsif (ref $client_conf->{config_opts} eq 'ARRAY')
{
	@config_flags = @{ $client_conf->{config_opts} };
}

if (@config_flags)
{
	@config_flags = grep { !m/=/ } @config_flags;
	do { s/\s+//g; $_ = qq("$_"); }
	  foreach @config_flags;
	push @config_flags, 'git' if $client_conf->{scm} eq 'git';
	$config_flags = '{' . join(',', @config_flags) . '}';
}

my $scm    = $client_conf->{scm} || 'cvs';
my $scmurl = $client_conf->{scm_url};

# if it's a git failure, throttle it so we don't get failures too often

if ($stage =~ /git/i)
{
	my $lsql = q{select stage,
                 extract(epoch from current_timestamp - report_time) as age,
                 report_time
          from build_status
          where sysname = ? and branch = ?
          order by report_time desc limit 1};

	my $row = $db->selectrow_hashref($lsql, undef, $animal, $branch);
	if (defined $row && ($row->{stage} eq $stage) && ($row->{age} < 3 * 3600))
	{

		print
		  "Status: 494 Git failure too frequent\nContent-Type: text/plain\n\n";
		print
		  "Frequent git failure reports are throttled\n",
		  "Please report again after 3 hours have elapsed ",
		  "since $row->{report_time}\n";
		$db->disconnect;
		exit;
	}
}

my $logst = <<"EOSQL";
    insert into build_status$raw_suffix
      (sysname, snapshot,status, stage, log,conf_sum, branch,
       changed_this_run, changed_since_success,
       log_archive_filenames , log_archive, build_flags, scm, scmurl,
       git_head_ref,frozen_conf)
    values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
EOSQL

# this transaction lets us set log_error_verbosity to terse
# just for the duration of the transaction. That turns off logging the
# bind params, so all the logs don't get stuffed on the postgres logs

my $sqlres;
$db->begin_work;
$db->do("select set_local_error_terse()");

$sth = $db->prepare($logst);

$sth->bind_param(1, $animal);
$sth->bind_param(2, $dbdate);
$sth->bind_param(3, $res & 0x8fffffff);    # in case we get a 64 bit int status!
$sth->bind_param(4, $stage);
$log =~ s/\x00/\\0/g;
$sth->bind_param(5,  $log, { pg_type => $log_text_type });
$sth->bind_param(6,  $conf);
$sth->bind_param(7,  $branch);
$sth->bind_param(8,  $changed_this_run);
$sth->bind_param(9,  $changed_since_success);
$sth->bind_param(10, $log_file_names);

#$sth->bind_param(11,$log_archive,{ pg_type => DBD::Pg::PG_BYTEA });
$sth->bind_param(11, undef, { pg_type => DBD::Pg::PG_BYTEA });
$sth->bind_param(12, $config_flags);
$sth->bind_param(13, $scm);
$sth->bind_param(14, $scmurl);
$sth->bind_param(15, $githeadref);
$sth->bind_param(16, $frozen_sconf, { pg_type => DBD::Pg::PG_BYTEA });

$sqlres = $sth->execute;

if ($sqlres)
{

	$sth->finish;

	my $logst2 = <<"EOSQL";

	  insert into build_status_log$raw_suffix
		(sysname, snapshot, branch, log_stage, log_text, stage_duration)
		values (?, ?, ?, ?, ?, ?)
EOSQL

	$sth = $db->prepare($logst2);

	$/ = undef;

	my $stage_start = $ts;

	foreach my $log_file (@log_file_names)
	{
		next if $log_file =~ /^githead/;
		my $handle;
		open($handle, "<", "$dirname/$log_file")
		  || die "opening $dirname/$log_file";
		my $mtime          = (stat $handle)[9];
		my $stage_interval = $mtime - $stage_start;
		$stage_start = $mtime;
		my $ltext = <$handle>;
		close($handle);
		$ltext =~ s/\x00/\\0/g;
		my $sinterval = "$stage_interval seconds";

		$sth->bind_param(1, $animal);
		$sth->bind_param(2, $dbdate);
		$sth->bind_param(3, $branch);
		$sth->bind_param(4, $log_file);
		$sth->bind_param(5, $ltext, { pg_type => $log_text_type });
		$sth->bind_param(6, $sinterval);

		$sqlres = $sth->execute;
		last unless $sqlres;
	}

	$sth->finish unless $sqlres;

}

if (!$sqlres)
{

	print "Status: 462 database failure\nContent-Type: text/plain\n\n";
	print "Your report generated a database failure:\n", $db->errstr, "\n";
	$db->rollback;
	$db->disconnect;
	exit;
}

$db->commit;

my $prevst = <<"EOSQL";

  select coalesce((select distinct on (snapshot) stage
                  from build_status
                  where sysname = ? and branch = ? and snapshot < ?
                  order by snapshot desc
                  limit 1), 'NEW') as prev_status

EOSQL

$sth = $db->prepare($prevst);
$sth->execute($animal, $branch, $dbdate);
my $row       = $sth->fetchrow_arrayref;
my $prev_stat = $row->[0];
$sth->finish;

my $det_st = <<"EOS";

          select operating_system, os_version,
                 compiler, compiler_version,
                 architecture as arch
          from buildsystems
          where status = 'approved'
                and name = ?

EOS
$sth = $db->prepare($det_st);
$sth->execute($animal);
$row = $sth->fetchrow_arrayref;
$sth->finish;

my $latest_personality = $db->selectrow_arrayref(
	q{
            select os_version, compiler_version
            from personality
            where name = ?
            order by effective_date desc limit 1
    }, undef, $animal
);

if ($latest_personality)
{
	$row->[1] = $latest_personality->[0];
	$row->[3] = $latest_personality->[1];
}

my ($os, $compiler, $arch) =
  ("$row->[0] / $row->[1]", "$row->[2] / $row->[3]", $row->[4]);

$db->do("select refresh_dashboard()");

if ($stage ne 'OK')
{
	$db->do("select refresh_recent_failures()");
}

$db->disconnect;

print "Content-Type: text/plain\n\n";
print "request was on:\n";
print "res=$res&stage=$stage&animal=$animal&ts=$ts";

my $client_events = $client_conf->{mail_events};

if ($ENV{BF_DEBUG})
{
	my $client_time = $client_conf->{current_ts};
	open(my $tx, ">>", "$buildlogs/$animal.$date")
	  || die "opening $buildlogs/$animal.$date";
	print $tx "\n", Dumper(\$client_conf), "\n";
	print $tx "server time: $server_time, client time: $client_time\n"
	  if $client_time;
	close($tx);
	# rename the file using the dbdate so they can be matched up
	# but turn the space into a T like iso 8601
	my $ndbdate = $dbdate;
	$ndbdate =~ s/ /T/g;
	move "$buildlogs/$animal.$date", "$buildlogs/$animal.$ndbdate"
}

my $url = $status_url;
$url ||= $query->url(-base => 1);

# replace space with a plus for use in URLs
my $urldbdate = $dbdate;
$urldbdate =~ s/ /+/;

if (!$skip_rss && $stage ne $prev_stat && "$stage$prev_stat" !~ /Git/)
{
	my ($rsec, $rmin, $rhour, $rmday, $rmon, $ryear, $rwday, $ryday, $risdst) =
	  gmtime(time);
	$ryear += 1900;
	$rmon  += 1;
	my $rssdate = sprintf("%d-%.2d-%.2dT%.2d:%.2d:%.2d+00:00",
		$ryear, $rmon, $rmday, $rhour, $rmin, $rsec);
	my $rssfile = "../htdocs/rss/bf-rss.xml";
	open(my $rsslock, ">", "/tmp/rsslock") || die "opening rsslock: $!";
	flock($rsslock, LOCK_EX);
	my $rss;

	if (-e $rssfile)
	{
		$rss = XML::RSS->new;
		$rss->parsefile($rssfile);
	}
	else
	{
		# bootstrap RSS
		$rss = XML::RSS->new(version => '1.0');
		$rss->channel(
			title => "PostgreSQL Build farm",
			link  => "http://buildfarm.postgresql.org/cgi-bin/show_status.pl",
			description => "Status changes for PostgreSQL Build Farm animals",
		);
		$rss->image(
			title => "PostgreSQL Build Farm",
			url => "http://buildfarm.postgresql.org/inc/pbbuildfarm-banner.png",
			link => "http://buildfarm.postgresql.org/cgi-bin/show_status.pl"
		);
	}
	$rss->add_item(
		title => "$branch: $animal to $stage",
		link  => "$url/cgi-bin/show_log.pl?nm=$animal&dt=$urldbdate",
		description =>
		  "$animal changed from $prev_stat to $stage on branch $branch\n"
		  . "<br />OS: $os Arch: $arch Comp: $compiler\n",
		dc => { date => $rssdate }
	);
	while (@{ $rss->{'items'} } > 15)
	{
		# trim old entries but keep a minimum of 15
		# assume items are in date order - they should be
		my $rssdt   = $rss->{items}->[0]->{dc}->{date};
		my $horizon = time - (48 * 3600);                    # 48 hours ago
		my $w3c     = DateTime::Format::W3CDTF->new;
		my $dt      = $w3c->parse_datetime($rssdt)->epoch;
		last if $dt > $horizon;

		shift(@{ $rss->{'items'} });
	}

	$rss->save("$rssfile.tmp") || die "saving $rssfile.tmp";
	chmod 0664, "$rssfile.tmp";
	move("$rssfile.tmp", "$rssfile");
	close($rsslock);
}


exit if $skip_mail;

my $bcc_stat = [];
my $bcc_chg  = [];
if (ref $client_events)
{
	my $cbcc = $client_events->{all};
	if (ref $cbcc)
	{
		push @$bcc_stat, @$cbcc;
	}
	elsif (defined $cbcc)
	{
		push @$bcc_stat, $cbcc;
	}
	if ($stage ne 'OK')
	{
		$cbcc = $client_events->{fail};
		if (ref $cbcc)
		{
			push @$bcc_stat, @$cbcc;
		}
		elsif (defined $cbcc)
		{
			push @$bcc_stat, $cbcc;
		}
	}
	$cbcc = $client_events->{change};
	if (ref $cbcc)
	{
		push @$bcc_chg, @$cbcc;
	}
	elsif (defined $cbcc)
	{
		push @$bcc_chg, $cbcc;
	}
	if ($stage eq 'OK' || $prev_stat eq 'OK')
	{
		$cbcc = $client_events->{green};
		if (ref $cbcc)
		{
			push @$bcc_chg, @$cbcc;
		}
		elsif (defined $cbcc)
		{
			push @$bcc_chg, $cbcc;
		}
	}
}

# copied from http://www.perlmonks.org/?node_id=142710
# not using Filter::Indent::HereDoc because the indented end token
# seems to upset emacs

sub unindent
{
	my ($data, $whitespace) = @_;
	if (!defined $whitespace)
	{
		($whitespace) = $data =~ /^(\s+)/;
	}
	$data =~ s/^$whitespace//mg;
	return $data;
}

my $stat_type = $stage eq 'OK' ? 'Status' : 'Failed at Stage';

my $mailto = [@$all_stat];
push(@$mailto, @$fail_stat) if $stage ne 'OK';

my $me = `id -un`;
chomp($me);

my $host = `hostname`;
chomp($host);
$host = $default_host unless ($host =~ m/[.]/ || !defined($default_host));

my $from_addr = "PG Build Farm <$me\@$host>";
$from_addr =~ tr /\r\n//d;

$from_addr = $status_from if $status_from;

if (@$mailto or @$bcc_stat)
{
	my $msg = Mail::Send->new;

	$Data::Dumper::Indent = 0;    # no indenting the lists at all

	open(my $maillog, ">>", "$buildlogs/mail")
	  || die "opening $buildlogs/mail";
	print $maillog
	  "member $animal Branch $branch $stat_type $stage ($prev_stat)\n";
	print $maillog "mailto: @{[Dumper($mailto)]}\n";
	print $maillog "bcc_stat: @{[Dumper($bcc_stat)]}\n" if @$bcc_stat;
	close($maillog);

	$msg->to(@$mailto)    if (@$mailto);
	$msg->bcc(@$bcc_stat) if (@$bcc_stat);
	$msg->subject(
		"PGBuildfarm member $animal Branch $branch $stat_type $stage");
	$msg->set('From', $from_addr);
	my $fh = $msg->open("sendmail", "-f $from_addr");
	print $fh unindent(<<"EOMAIL");

	The PGBuildfarm member $animal had the following event on branch $branch:

	$stat_type: $stage

	The snapshot timestamp for the build is: $dbdate

	The specs of this machine are:
	OS:  $os
	Arch: $arch
	Comp: $compiler

	For more information, see $url/cgi-bin/show_history.pl?nm=$animal&br=$branch

EOMAIL

	$fh->close;
}

exit if ($stage eq $prev_stat);

$mailto = [@$change_stat];
push(@$mailto, @$green_stat) if ($stage eq 'OK' || $prev_stat eq 'OK');

if (@$mailto or @$bcc_chg)
{
	{
		open(my $maillog, ">>", "$buildlogs/mail")
		  || die "opening $buildlogs/mail";
		print $maillog "mailto: @{[Dumper($mailto)]}\n";
		print $maillog "bcc_chg: @{[Dumper($bcc_chg)]}\n" if @$bcc_chg;
		close($maillog);
	}

	my $msg = Mail::Send->new;

	$msg->to(@$mailto)   if (@$mailto);
	$msg->bcc(@$bcc_chg) if (@$bcc_chg);

	$stat_type =
	  $prev_stat ne 'OK'
	  ? "changed from $prev_stat failure to $stage"
	  : "changed from OK to $stage";
	$stat_type = "New member: $stage" if $prev_stat eq 'NEW';
	$stat_type .= " failure" if $stage ne 'OK';

	$msg->subject(
		"PGBuildfarm member $animal Branch $branch Status $stat_type");
	$msg->set('From', $from_addr);
	my $fh = $msg->open("sendmail", "-f $from_addr");
	print $fh unindent(<<"EOMAIL");

	The PGBuildfarm member $animal had the following event on branch $branch:

	Status $stat_type

	The snapshot timestamp for the build is: $dbdate

	The specs of this machine are:
	OS:  $os
	Arch: $arch
	Comp: $compiler

	For more information, see $url/cgi-bin/show_history.pl?nm=$animal&br=$branch

EOMAIL

	$fh->close;
}
