#!/usr/bin/perl
use Fcntl qw(:flock);
use Net::Netmask;
use Net::SSH::Expect;
use LWP::UserAgent;
use Time::HiRes qw( usleep );
use Array::Diff;

# Version 1.0

my $host = "192.168.1.1"; 	#ASA IP
my $user = "user";  	  	#ASA username 
my $password = 'passw0rd';	#ASA Password
my $enable = '321';             #ASA Enable password
my $log = './acloutput.log';	#SSH terminal log
my $prompt = '#';		#ASA prompt
my $objectgroup = 'PERMIT-US-IN';#Name of the object group that the subnets will be in
my $loginPrompt = 'Type';	 #Prompt seen after login 
my $EnablePrompt = 'Password:';	 #Enable Password prompt
my $to = 2; 			 #Expect timeout
my $timeoutmsg = "prompt $prompt not found after 1 second";
my $debug = 1;			  #Enable debug 1 or 0
#______________________________________________________________________________________#



my $break = 
"------------------------\n------------------------\n
------------------------\n------------------------\n
------------------------\n------------------------\n
------------------------\n------------------------\n";

my $ua = LWP::UserAgent->new();
 $ua->timeout(5);

my $page_txt;
my $req = $ua->get('http://www.ipdeny.com/ipblocks/data/aggregated/');
if ($req->is_success) { $page_txt = $req->content; }

my @page = split("\n", $page_txt);
my $subnets;

foreach my $line(@page) {
   if ($line =~ /.*href=\"(..)-aggregated\.zone/g) {
	 #unless ($1 eq 'us') {
	  if ($1 eq 'us') {
	    my $req = $ua->get('http://www.ipdeny.com/ipblocks/data/aggregated/'.$1.'-aggregated.zone');
	    if ($req->is_success) { $page_txt = $req->content; }
	     $subnets .= $page_txt;
	 } 
   }
}

my @subnetslist = split("\n", $subnets);

@subnetslist = asaformat(@subnetslist); 

print scalar(@subnetslist)." subnets in downloaded lists\n";


# Exit if the list is too small
if (scalar(@subnetslist) le 1000) {
        print "Error - Subnet list is too small, something went wrong. array size " . scalar(@subnetslist) ."\n";
        exit 1;
       }




$ssh = &login($host, $user, $password, $loginPrompt, $log, $EnablePrompt);
$ssh->eat($ssh->peek(0));
$ssh->send ("sh run object-group id ".$objectgroup);

my $line;
my @lastsubnetslist;
print "ASA object group entries:\n" if $debug;
while ( defined ($line = $ssh->read_line()) ) {
  $line = cleanlinewo($line);
  next if ($line =~ /does not exist/);
  next if ($line =~ /#/);
  next if ($line =~ /object-group/);
  next if ($line eq "");
  push @lastsubnetslist, $line;
  print "$line\n" if $debug;
}

print $break if $debug;

print scalar(@lastsubnetslist)." subnets in ASA object group\n";

my @lastsubnetslist_sort = sort @lastsubnetslist;
my @subnetslist_sort = sort @subnetslist;

  my $diff = Array::Diff->diff( \@lastsubnetslist_sort, \@subnetslist_sort );    #( OLD, NEW ) 
  
 if ($debug) { 
   print $break; 
   print "Adds:\n";
    foreach my $line(@{ $diff->added }) { print $line."\n"; }     #present in the NEW array and absent in the OLD one. Add to object group
   print $break; 
   print "Deletes:\n";
    foreach my $line(@{ $diff->deleted }) { print "no ".$line."\n"; } #present in the OLD array and absent in the NEW one. Remove from object group 
 }



$ssh->send("conf t\n");
$ssh->waitfor($prompt, $to) or die $timeoutmsg;
$ssh->send("object-group network ".$objectgroup);
$ssh->waitfor($prompt, $to) or die $timeoutmsg;


foreach my $subnet(@{ $diff->added }) {
	$ssh->send($subnet);
	$ssh->waitfor($prompt, $to) or die $timeoutmsg;
	$ssh->eat($ssh->peek(0));
	usleep (60000); # sleep microseconds
}

foreach my $subnet(@{ $diff->deleted }) {
        $ssh->send("no $subnet");
        $ssh->waitfor($prompt, $to) or die $timeoutmsg;
        $ssh->eat($ssh->peek(0));
        usleep (60000); # sleep microseconds
}

$ssh->send("exit");
$ssh->waitfor($prompt, $to) or die $timeoutmsg;
$ssh->send("exit");
$ssh->waitfor($prompt, $to) or die $timeoutmsg;
$ssh->send("wr me");
$ssh->waitfor($prompt, $to) or die $timeoutmsg;


$ssh->close();


#___________________________________SUBS_______________________________________________



sub login {
my ($host, $user, $password, ,$loginPrompt, $TempLogFile, $EnablePrompt) = @_;

my $ssh = Net::SSH::Expect->new (
        host => $host,
        port => "22",
        user => $user,
        password => $password,
        raw_pty => 1,
        timeout => '4',
        log_file => "$TempLogFile"
        );


 my $login_output = $ssh->login();
      if ($login_output !~ /$loginPrompt/) {
          die "Login has failed. Login output was $login_output";
       }

if (defined($EnablePrompt)) {
  $ssh->send("enable\n");   # using send() instead of exec()
  $ssh->waitfor($EnablePrompt, $to) or die "prompt $EnablePrompt not found after 1 second";
  $ssh->send($enable);
  $ssh->waitfor($prompt, $to) or die $timeoutmsg;
}

$ssh->send("terminal pager 0\n");
$ssh->waitfor($prompt, $to) or die $timeoutmsg;

#$ssh->send("terminal length 0\n");
#$ssh->waitfor($prompt, $to) or die $timeoutmsg;

$ssh->eat($ssh->peek(0));  # removes whatever is on the input stream now

return $ssh;
}

sub asaformat {
my (@subnetslist) = @_;
my @temparr; 
  foreach my $subnet(@subnetslist) {
    $subnet = cleanlinewo($subnet);
    my $block = Net::Netmask->new2( $subnet ) or print "Error with getting mask for $subnet\n" && next;
    #print $block->base." ".$block->mask."\n";
    push @temparr, "network-object ".$block->base." ".$block->mask;
   }
return @temparr;
}


sub cleanlinewo {
#remove everything that is not a word from the start and end
   my ($cleanedlinewo) = @_;
   $cleanedlinewo =~ s/^\W+//;  #remove crap from the start
   $cleanedlinewo =~ s/\W+$//;  #remove crap from the end
   return $cleanedlinewo;
}


sub filecheck { 
my ($filename) = @_;
  unless(-e $filename) {
      #Create the file if it doesn't exist
      open my $fc, ">", $filename;
      close $fc;
  }
}
