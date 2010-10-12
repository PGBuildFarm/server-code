#!/usr/bin/perl

use strict;

use vars qw($dbhost $dbname $dbuser $dbpass $dbport
       $all_stat $fail_stat $change_stat $green_stat
       $server_time
	   $min_script_version $min_web_script_version
);

# force this before we do anything - even load modules
BEGIN { $server_time = time; }

use CGI;
use Digest::SHA1  qw(sha1_hex);
use MIME::Base64;
use DBI;
use DBD::Pg;
use Data::Dumper;
use Mail::Send;
use Safe;

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn="dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $query = new CGI;

my $sig = $query->path_info;
$sig =~ s!^/!!;

my $stage = $query->param('stage');
my $ts = $query->param('ts');
my $animal = $query->param('animal');
my $log = $query->param('log');
my $res = $query->param('res');
my $conf = $query->param('conf');
my $branch = $query->param('branch');
my $changed_since_success = $query->param('changed_since_success');
my $changed_this_run = $query->param('changed_files');
my $log_archive = $query->param('logtar');

my $content = 
	"branch=$branch&res=$res&stage=$stage&animal=$animal&".
	"ts=$ts&log=$log&conf=$conf";

my $extra_content = 
	"changed_files=$changed_this_run&".
	"changed_since_success=$changed_since_success&";

unless ($animal && $ts && $stage && $sig)
{
	print 
	    "Status: 490 bad parameters\nContent-Type: text/plain\n\n",
	    "bad parameters for request\n";
	exit;
	
}

unless ($branch =~ /^(HEAD|REL\d+_\d+_STABLE)$/)
{
        print
            "Status: 492 bad branch parameter $branch\nContent-Type: text/plain\n\n",
            "bad branch parameter $branch\n";
        exit;

}


my $db = DBI->connect($dsn,$dbuser,$dbpass);

die $DBI::errstr unless $db;

my $gethost=
    "select secret from buildsystems where name = ? and status = 'approved'";
my $sth = $db->prepare($gethost);
$sth->execute($animal);
my ($secret)=$sth->fetchrow_array();
$sth->finish;

my $tsdiff = time - $ts;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
$year += 1900; $mon +=1;
my $date=
    sprintf("%d-%.2d-%.2d_%.2d:%.2d:%.2d",$year,$mon,$mday,$hour,$min,$sec);

if ($ENV{BF_DEBUG} || ($ts > time) || ($ts + 86400 < time ) || (! $secret) )
{
    open(TX,">../buildlogs/$animal.$date");
    print TX "sig=$sig\nlogtar-len=" , length($log_archive),
        "\nstatus=$res\nstage=$stage\nconf:\n$conf\n",
        "tsdiff:$tsdiff\n",
	"changed_this_run:\n$changed_this_run\n",
	"changed_since_success:\n$changed_since_success\n",
	"log:\n",$log;
#    $query->save(\*TX);
    close(TX);
}

unless ($ts < time + 120)
{
    my $gmt = gmtime($ts);
    print "Status: 491 bad ts parameter - $ts ($gmt GMT) is in the future.\n",
    "Content-Type: text/plain\n\n bad ts parameter - $ts ($gmt GMT) is in the future\n";
	$db->disconnect;
    exit;
}

unless ($ts + 86400 > time)
{
    my $gmt = gmtime($ts);
    print "Status: 491 bad ts parameter - $ts ($gmt GMT) is more than 24 hours ago.\n",
     "Content-Type: text/plain\n\n bad ts parameter - $ts ($gmt GMT) is more than 24 hours ago.\n";
    $db->disconnect;
    exit;
}

unless ($secret)
{
	print 
	    "Status: 495 Unknown System\nContent-Type: text/plain\n\n",
	    "System $animal is unknown\n";
	$db->disconnect;
	exit;
	
}




my $calc_sig = sha1_hex($content,$secret);
my $calc_sig2 = sha1_hex($extra_content,$content,$secret);

if ($calc_sig ne $sig && $calc_sig2 ne $sig)
{

	print "Status: 450 sig mismatch\nContent-Type: text/plain\n\n";
	print "$sig mismatches $calc_sig($calc_sig2) on content:\n$content";
	$db->disconnect;
	exit;
}

# undo escape-proofing of base64 data and decode it
map {tr/$@/+=/; $_ = decode_base64($_); } 
    ($log, $conf,$changed_this_run,$changed_since_success,$log_archive);

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($ts);
$year += 1900; $mon +=1;
my $dbdate=
    sprintf("%d-%.2d-%.2d %.2d:%.2d:%.2d",$year,$mon,$mday,$hour,$min,$sec);

my $log_file_names;
my @log_file_names;
my $dirname = "../buildlogs/tmp.$$.unpacklogs";

if ($log_archive)
{
    my $log_handle;
    my $archname = "../buildlogs/tmp.$$.tgz";
    open($log_handle,">$archname");
    binmode $log_handle;
    print $log_handle $log_archive;
    close $log_handle;
    mkdir $dirname;
    @log_file_names = `tar -z -C $dirname -xvf $archname 2>/dev/null`;
    map {s/\s+//g; } @log_file_names;
    my @qnames = @log_file_names;
    map { $_ = qq("$_"); } @qnames;
    $log_file_names = '{' . join(',',@qnames) . '}';
    # unlink $archname;
}

my $config_flags;
my $container = new Safe;
my $sconf = $conf; 
unless ($sconf =~ s/.*(\$Script_Config)/$1/ms )
{
    $sconf = '$Script_Config={};';
}
my $client_conf = $container->reval("$sconf;");

if ($min_script_version)
{
	$client_conf->{script_version} ||= '0.0';
	my ($minmajor,$minminor) = split(/\./,$min_script_version);
	my ($smajor,$sminor) = split(/\./,$client_conf->{script_version});
	if ($minmajor > $smajor || ($minmajor == $smajor && $minminor > $sminor))
	{
		print "Status: 460 script version too low\nContent-Type: text/plain\n\n";
		print 
			"Script version is below minimum required\n",
			"Reported version: $client_conf->{script_version},",
			"Minumum version required: $min_script_version\n";
		$db->disconnect;
		exit;
	}
}

if ($min_web_script_version)
{
	$client_conf->{web_script_version} ||= '0.0';
	my ($minmajor,$minminor) = split(/\./,$min_script_version);
	my ($smajor,$sminor) = split(/\./,$client_conf->{script_version});
	if ($minmajor > $smajor || ($minmajor == $smajor && $minminor > $sminor))
	{
		print "Status: 461 web script version too low\nContent-Type: text/plain\n\n";
		print 
			"Web Script version is below minimum required\n",
			"Reported version: $client_conf->{web_script_version},",
			"Minumum version required: $min_web_script_version\n";
		$db->disconnect;
		exit;
	}
}

my @config_flags;
if (not exists $client_conf->{config_opts} )
{
	@config_flags = ();
}
elsif (ref $client_conf->{config_opts} eq 'HASH')
{
	# leave out keys with false values
	@config_flags = grep { $client_conf->{config_opts}->{$_} } 
	    keys %{$client_conf->{config_opts}};
}
elsif (ref $client_conf->{config_opts} eq 'ARRAY' )
{
	@config_flags = @{$client_conf->{config_opts}};
}

if (@config_flags)
{
    @config_flags = grep {! m/=/ } @config_flags;
    map {s/\s+//g; $_=qq("$_"); } @config_flags;
    push @config_flags,'git' if $client_conf->{scm} eq 'git';
    $config_flags = '{' . join(',',@config_flags) . '}' ;
}

my $scm = $client_conf->{scm} || 'cvs';
my $scmurl = $client_conf->{scm_url};

my $logst = <<EOSQL;
    insert into build_status 
      (sysname, snapshot,status, stage, log,conf_sum, branch,
       changed_this_run, changed_since_success, 
       log_archive_filenames , log_archive, build_flags, scm, scmurl)
    values(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
EOSQL
;
$sth=$db->prepare($logst);

$sth->bind_param(1,$animal);
$sth->bind_param(2,$dbdate);
$sth->bind_param(3,$res);
$sth->bind_param(4,$stage);
$sth->bind_param(5,$log);
$sth->bind_param(6,$conf);
$sth->bind_param(7,$branch);
$sth->bind_param(8,$changed_this_run);
$sth->bind_param(9,$changed_since_success);
$sth->bind_param(10,$log_file_names);
#$sth->bind_param(11,$log_archive,{ pg_type => DBD::Pg::PG_BYTEA });
$sth->bind_param(11,undef,{ pg_type => DBD::Pg::PG_BYTEA });
$sth->bind_param(12,$config_flags);
$sth->bind_param(13,$scm);
$sth->bind_param(14,$scmurl);

$sth->execute;
$sth->finish;

my $logst2 = <<EOSQL;

  insert into build_status_log 
    (sysname, snapshot, branch, log_stage, log_text, stage_duration)
    values (?, ?, ?, ?, ?, ?)

EOSQL
    ;

$sth = $db->prepare($logst2);

$/=undef;

my $stage_start = $ts;

foreach my $log_file( @log_file_names )
{
  my $handle;
  open($handle,"$dirname/$log_file");
  my $mtime = (stat $handle)[9];
  my $stage_interval = $mtime - $stage_start;
  $stage_start = $mtime;
  my $ltext = <$handle>;
  close($handle);
  $ltext =~ s/\x00/\\0/g;
  $sth->execute($animal,$dbdate,$branch,$log_file,$ltext, 
		"$stage_interval seconds");
}


$sth->finish;

my $prevst = <<EOSQL;

  select coalesce((select distinct on (snapshot) stage
                  from build_status
                  where sysname = ? and branch = ? and snapshot < ?
                  order by snapshot desc
                  limit 1), 'NEW') as prev_status
  
EOSQL

$sth=$db->prepare($prevst);
$sth->execute($animal,$branch,$dbdate);
my $row=$sth->fetchrow_arrayref;
my $prev_stat=$row->[0];
$sth->finish;

my $det_st = <<EOS;

          select operating_system|| ' / ' || os_version as os , 
                 compiler || ' / ' || compiler_version as compiler, 
                 architecture as arch
          from buildsystems 
          where status = 'approved'
                and name = ?

EOS
;
$sth=$db->prepare($det_st);
$sth->execute($animal);
$row=$sth->fetchrow_arrayref;
my ($os, $compiler,$arch) = @$row;
$sth->finish;

$db->begin_work;
my $have_status = $db->selectrow_arrayref( q{
    select 1 
    from build_status_latest 
    where sysname = ? and branch = ?
}, 
					   undef, $animal, $branch);
if ($have_status) 
{
    $db->do(q{
	      update build_status_latest
		  set latest_snapshot = ?
		  where sysname = ? and branch = ?
	      },
	    undef, $dbdate, $animal, $branch);
}
else
{
    $db->do(q{
	      insert into build_status_latest
		  (sysname, branch, latest_snapshot)
	      values (?,?,?)
	      },
	    undef, $animal, $branch, $dbdate);
}
$db->commit;

$db->begin_work;
$db->do("delete from dashboard_mat");
$db->do("insert into dashboard_mat select * from dashboard_mat_data2");
$db->commit;

$db->disconnect;

print "Content-Type: text/plain\n\n";
print "request was on:\n";
print "res=$res&stage=$stage&animal=$animal&ts=$ts";

my $client_events = $client_conf->{mail_events};

if ($ENV{BF_DEBUG})
{
	my $client_time = $client_conf->{current_ts};
    open(TX,">>../buildlogs/$animal.$date");
    print TX "\n",Dumper(\$client_conf),"\n";
	print TX "server time: $server_time, client time: $client_time\n" if $client_time;
    close(TX);
}

my $bcc_stat = [];
my $bcc_chg=[];
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
	$cbcc = $client_events->{all};
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


my $url = $query->url(-base => 1);


my $stat_type = $stage eq 'OK' ? 'Status' : 'Failed at Stage';

my $mailto = [@$all_stat];
push(@$mailto,@$fail_stat) if $stage ne 'OK';

my $me = `id -un`; chomp $me;

my $host = `hostname`; chomp $host;

my $msg = new Mail::Send;

$msg->set('From',"PG Build Farm <$me\@$host>");

$msg->to(@$mailto);
$msg->bcc(@$bcc_stat) if (@$bcc_stat);
$msg->subject("PGBuildfarm member $animal Branch $branch $stat_type $stage");
my $fh = $msg->open;
print $fh <<EOMAIL; 


The PGBuildfarm member $animal had the following event on branch $branch:

$stat_type: $stage

The snapshot timestamp for the build that triggered this notification is: $dbdate

The specs of this machine are:
OS:  $os
Arch: $arch
Comp: $compiler

For more information, see $url/cgi-bin/show_history.pl?nm=$animal&br=$branch

EOMAIL

$fh->close;

exit if ($stage eq $prev_stat);

$mailto = [@$change_stat];
push(@$mailto,@$green_stat) if ($stage eq 'OK' || $prev_stat eq 'OK');

$msg = new Mail::Send;

$msg->set('From',"PG Build Farm <$me\@$host>");

$msg->to(@$mailto);
$msg->bcc(@$bcc_chg) if (@$bcc_chg);

$stat_type = $prev_stat ne 'OK' ? "changed from $prev_stat failure to $stage" :
    "changed from OK to $stage";
$stat_type = "New member: $stage" if $prev_stat eq 'NEW';
$stat_type .= " failure" if $stage ne 'OK';

$msg->subject("PGBuildfarm member $animal Branch $branch Status $stat_type");
$fh = $msg->open;
print $fh <<EOMAIL;

The PGBuildfarm member $animal had the following event on branch $branch:

Status $stat_type

The snapshot timestamp for the build that triggered this notification is: $dbdate

The specs of this machine are:
OS:  $os
Arch: $arch
Comp: $compiler

For more information, see $url/cgi-bin/show_history.pl?nm=$animal&br=$branch

EOMAIL

$fh->close;
