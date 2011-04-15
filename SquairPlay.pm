package Plugins::SquairPlay::SquairPlay;
		  
# SquairPlay URL protocol handler

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use base qw(Slim::Player::Pipeline);

my $log = logger('plugin.squairplay');
my $prefs = preferences('server');


# register protocol handler
	$log->info( "SquairPlay - register protocol");
    Slim::Player::ProtocolHandlers->registerHandler("squairplay",  __PACKAGE__);

# new is called by openRemoteStream() for URLs with "squairplay:" protocol prefix

sub isRemote { 1 } 
sub new {

	$log->info( "SquairPlay - new openRemoteStream begin...");

	my $class = shift;
	my $args  = shift;
	my $transcoder = $args->{'transcoder'};
	my $url        = $args->{'url'} ;
	my $client     = $args->{'client'};


	Slim::Music::Info::setContentType($url, 'squairplay');
	my $quality = preferences('server')->client($client)->get('lameQuality');

	my $command = Slim::Player::TranscodingHelper::tokenizeConvertCommand2( $transcoder, $url, $url, 1, $quality );
	#$log->info("SquairPlay command: $command");

	my $self = $class->SUPER::new(undef, $command);

	${*$self}{'contentType'} = $transcoder->{'streamformat'};
	$log->info("SquairPlay - new openRemoteStream ...end");

	return $self;
}



sub canHandleTranscode {
	my ($self, $song) = @_;
	
	return 1;
}

sub getStreamBitrate {
	my ($self, $maxRate) = @_;
	
	return Slim::Player::Song::guessBitrateFromFormat(${*$self}{'contentType'}, $maxRate);
}


sub contentType 
{
	my $self = shift;
	return ${*$self}{'contentType'};
}

sub isAudioURL { 1 }

# XXX - I think that we scan the track twice, once from the playlist and then again when playing
sub scanUrl {
	my ( $class, $url, $args ) = @_;
	
	Slim::Utils::Scanner::Remote->scanURL($url, $args);
}

sub canDirectStream {
	return 0;
}

sub contentType {
	my $self = shift;

	return ${*$self}{'contentType'};
}

1;
