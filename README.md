# ipblock
This is a script that downloads subnets from www.ipdeny.com, creates an ASA object group, and configures it on the ASA.

Note - For an ASA 5510, at least 512Mb of memory is needed to configure the complete list of US subnets in a object group.  

You will need to install the following perl modules:

	Net::Netmask
	Net::SSH::Expect
	LWP::UserAgent
	Time::HiRes
	Array::Diff

I only allow US subnets inboud to my firewall, I use the object group (PERMIT-US-IN) created by the script like this:

	access-list outside extended permit object-group PERMIT-OUTSIDE-IN object-group PERMIT-US-IN any

	object-group service PERMIT-OUTSIDE-IN
  	service-object tcp eq 22
 
 You can run the script on a cron schedule and it will download the subnets you want from www.ipdeny.com, grab the contents
 of the configured object group on the ASA, compare the 2 lists and add or remove any subnets needed from the object group 
 so it is in sync with the downloaded list. 
 
 You can also get all but the US subnets to deny them and allow any to certain ports below the deny, but the list is much longer.
 
How to get all but US subnets:

	   #unless ($1 eq 'us') {  <<<< uncomment this line
	    if ($1 eq 'us') {       <<<< comment this line
