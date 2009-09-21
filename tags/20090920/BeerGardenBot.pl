#!/usr/bin/perl

use strict;

$| = 1;
$0 = "LikeableBot";

use POE;
use POE::Component::IRC;
# The below modules should not be needed at this time since I don't use the bootblock.de/wq3 site now.
use LWP;
use HTTP::Cookies;
use HTTP::Request::Common;
use LWP::Debug ('-');
use URI;


sub CHANNEL () { "#smokinguns" }

my $noiseLevel = 'quiet';
my $daTime = 15;
my $nick;
my $ReportPlayerNames = 1;
my $msgType = '';

$nick = 'SG_Deputy' . $$ % 1000;

# Create the component that will represent an IRC network.
my ($irc) = POE::Component::IRC->spawn();

# Create the bot session.  The new() call specifies the events the bot
# knows about and the functions that will handle those events.
POE::Session->create(
    inline_states => {
        _start           => \&bot_start,
        irc_001          => \&on_connect,
        irc_public       => \&on_public,
        irc_msg          => \&on_msg,
        irc_disconnected => \&bot_reconnect,
        irc_error        => \&bot_reconnect,
        irc_socketerr    => \&bot_reconnect,
        autoping         => \&bot_do_autoping,
				auto             => \&GetOnlinePlayersAuto,
    },
);

sub on_msg{
	my ($kernel,$sender,$who,$where,$what) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
	my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];
    print "channel = [" . $channel . "]\n";
    print "sender = [" . $sender . "]\n";
    print "nick = [" . $nick . "]\n";
    my $lcmsg = lc($what);
    chomp($lcmsg);
	if($what =~ /help/){
		print "give help\n";
		$irc->yield( privmsg => $nick, "Type 'player count' to check the online players for the WQ3 servers on bootblock.de/wq3. " );
	
		$irc->yield( privmsg => $nick, "The other commands need to be sent to the bot (not public). 'giddyup|auto [minutes]' will turn on the auto checker, every 15 minutes by default. 'whoa' will stop that. 'quiet' will not report if there are no live players, quiet by default. 'noisy' will report even if there are no live players. 'report player names' will show the live players, on by default now. 'no player names' will turn it off." );

	} elsif( ($lcmsg eq 'buckaroo') || ($lcmsg eq 'player count') ){
		# somebody sent a msg to get the player count 
    my $strMessage = GetOnlinePlayers('privmsg');
		$irc->yield( privmsg => $nick, $strMessage);
	} elsif( ($lcmsg =~ /auto/) || ($lcmsg =~ /giddyup/) ){
		print "AUTO\n";
		# see if they gave a time increment
		if($lcmsg =~ /\d/){
			# should be the time
			$daTime = (split /\ /, $lcmsg)[1];
			$daTime =~ s/\D//g;
		}
		my $strMessage = GetOnlinePlayers();
    if($daTime eq '' || $daTime == 0){
			print "in IF!\n";
			$daTime = 1500;	
		} else {
			print "in ELSE!\n";
			$daTime = $daTime * 60;
		}
		print "daTime = [" . $daTime . "]\n";
		
		$strMessage = "Auto mode set for $daTime seconds. " . $strMessage;
		
		$irc->yield( privmsg => $nick, $strMessage);
		$kernel->delay( auto => $daTime );
	} elsif($lcmsg =~ /whoa/){
		$irc->yield( privmsg => $nick, "whoa!.");
		$kernel->delay( auto => undef );
	} elsif($lcmsg =~ /quiet/){
		$noiseLevel = 'quiet';
	} elsif($lcmsg =~ /noisy/){
		$noiseLevel = 'noisy';
	} elsif($lcmsg eq 'report player names'){
		$ReportPlayerNames = 1;
	} elsif($lcmsg eq 'no player names'){
		$ReportPlayerNames = 0;
	} elsif($lcmsg eq 'adios amigos'){
		exit;	
	}elsif($lcmsg eq 'player count'){
		#my $strMessage = GetOnlinePlayers('privmsg');
		#$irc->yield( privmsg => $nick, $strMessage);
	} else {
		$irc->yield( privmsg => $nick, "Howdy, use the /query Bonanaz### help command to get help.");
	}
}# on_msg


sub bot_connected {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    # Join channel(s), set user modes, etc.
    $heap->{seen_traffic} = 1;
    $kernel->delay( autoping => 100 );
}# bot_connected

# Ping ourselves, but only if we haven't seen any traffic since the
# last ping.  This prevents us from pinging ourselves more than
# necessary (which tends to get noticed by server operators).
sub bot_do_autoping {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $kernel->post( poco_irc => userhost => $nick )
      unless $heap->{seen_traffic};
    $heap->{seen_traffic} = 0;
    $kernel->delay( autoping => 100 );
}

# Reconnect in 60 seconds.  Don't ping while we're disconnected.  It's
# important to wait between connection attempts or the server may
# detect "abuse".  In that case, you may be prohibited from connecting
# at all.
sub bot_reconnect {
    my $kernel = $_[KERNEL];
    $kernel->delay( autoping => undef );
    $kernel->delay( connect  => 60 );
}# bot_reconnect


# The bot session has started.  Register this bot with the "magnet"
# IRC component.  Select a nickname.  Connect to a server.
sub bot_start {
    my $kernel  = $_[KERNEL];
    my $heap    = $_[HEAP];
    my $session = $_[SESSION];

    $irc->yield( register => "all" );
    $irc->yield( connect =>
          { 
	  	Nick => $nick,
            	Username => $nick,
		Ircname => "Smokin Guns online player check",
		Server => "irc.freenode.net",
		Port => 6667,
		Password => 'elvis'
          }
    );

    $kernel->yield("connect");
}# bot_start

# The bot has successfully connected to a server.  Join a channel.
sub on_connect {
    $irc->yield( join => CHANNEL );

     my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

    # Join channel(s), set user modes, etc.

    $heap->{seen_traffic} = 1;
    $kernel->delay( autoping => 300 );

}# on_connect

# The bot has received a public message.  Parse it for commands, and
# respond to interesting things.
sub on_public {
    my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    my $ts = scalar localtime;
    print " [$ts] <$nick:$channel> $msg\n";
    my $lcmsg = lc($msg);
    print "\$lcmsg = " . $lcmsg . "\n";
    chomp($lcmsg);
	if( ($lcmsg eq 'buckaroo') || ($lcmsg eq 'player count') ){
		my $strMessage = GetOnlinePlayers('privmsg');
		$irc->yield( privmsg => CHANNEL, $strMessage );
	} elsif($lcmsg eq 'likeable') {
		my @redMessages = ('I have naked pics of T-Fun and Growler!', 'I\'M GONNA ROCK YOU LIKE A HURRICANE', 'Don\'t Shoot me I\m busy tb\'n someone!');
		@redMessages = randarray(@redMessages);
		my $strMessage = @redMessages[0];				
		print "\$strMessage = " . $strMessage . "\n";
		if($noiseLevel ne 'quiet') {
			$irc->yield( privmsg => CHANNEL, $strMessage);
		}
		
		
	} #if
}#on_public


sub GetOnlinePlayers{
	my $msgType = shift;
	print "msgType = [" . $msgType . "]\n";
	my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];

	# Data parse section
	my $playerCount = 0;
	my $strMessage = "";
	my $thisServer = "";

	my @ips = ('70.38.22.170:27960', '91.121.74.167:27960', '69.12.76.75:27960', '66.225.11.217:27960', '91.121.207.93:27962', '72.36.180.29:27960', '91.121.207.93:27961', '173.74.37.74:27960', '74.52.14.98:27962', '62.75.222.123:33000', '91.121.106.158:27962', '92.75.104.152:27961');
	
	#my @ips = ('91.121.74.167:27960', '66.225.11.217:27960', '91.121.106.158:27962', '1.121.207.93:27961', '69.12.76.75:27960', '62.75.222.123:33000');
	my $master_count = 0;
	foreach my $ip (@ips) {
		my $count = 1;
		my $command = `quakestat -raw ___  -P -q3s $ip`;
		my @all_lines = split(/\n/, $command);
		my $player_line = ' [';
		my $player_count = 0;
		my $strMessagetmp = '';
		
		foreach my $line (@all_lines) {
			if( $count == 1) {
				# get server name
				my @server = split(/___/, $line);
				$strMessagetmp .= @server[2];
				#print '$server: ' . @server[2] . "\n";
			} else {
				# get the player name
				my @player_line = split(___, $line);
				if(@player_line[2] > 0) {
					
					print 'player:' . @player_line[0] . "\n";
					$player_line .= @player_line[0] . ", ";
					
					$player_count++;
				} else {
					#print "we have a bot - " . @player_line[0] . "\n";
				}
			}
			$count++;
			$master_count++;
		}
		if($player_count > 0) {
			$player_line =~ s/\s$//;	
			$player_line =~ s/,$//;
			$strMessage .= $strMessagetmp . " has " . $player_count . " players - " . $player_line . ']  ' . "     ";
		}
		
		#print "\n-----------------------\n"; 
	}
  
  print "msgType = [" . $msgType . "]\n";
	if($strMessage eq ""){
		#no report :(
		if($noiseLevel eq 'noisy' || $msgType eq 'privmsg'){
			$strMessage = "No luck cowpoke. Just bots are playin.";
		} else {
			# sshhhh
		}
	}
	print "strMessage = [" . $strMessage . "]\n";
	return $strMessage;
		
}# GetOnlinePlayers


sub GetOnlinePlayersAuto{
	my ($kernel,$sender,$who,$where,$what) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
    print @_ . '\n';
	my $nick = ( split /!/, $who )[0];
	print "GetOnlinePlayersAuto nick = [" . $nick . "]\n";
    my $channel = $where->[0];
    
    my $lcmsg = lc($what);
    chomp($lcmsg);
    
	my $strMessage = GetOnlinePlayers();
    
	$irc->yield( privmsg => CHANNEL, $strMessage);
	$kernel->delay( auto => $daTime );
}#GetOnlinePlayersAuto


sub randarray {
	my @array = @_;
	my @rand = undef;
	my $seed = $#array + 1;
	my $randnum = int(rand($seed));
	$rand[$randnum] = shift(@array);
	while (1) {
		my $randnum = int(rand($seed));
		if ($rand[$randnum] eq undef) {
			$rand[$randnum] = shift(@array);
		}
		last if ($#array == -1);
	}
	return @rand;
}



# Run the bot until it is done.
$poe_kernel->run();
exit 0;
