package Plugins::SquairPlay::Plugin;

#
# Plugin.pm
#

use strict;

use base qw(Slim::Plugin::Base);

use vars qw($VERSION);
use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);
use Slim::Utils::Misc;
use Plugins::SquairPlay::SquairPlay;

my %wavsource;			# per-client friendly wavin device name 



# create log categogy before loading other modules
my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.squairplay',
	defaultLevel => 'INFO',
	description  => getDisplayName(),
} );


sub getDisplayName {
	return 'PLUGIN_SQUAIRPLAY';
}

sub setMode {
	my $client = shift;
	my $method = shift;

	$log->info("SquairPlay, in setMode");

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$client->lines(\&lines);
	$client->update();
}

sub leaveMode {
    my $client = shift;
}

sub play {
	my $client = shift;
	my $wavsource = $wavsource{$client};
	my $name = "Audio Input $wavsource";
	my $wavinurl = "wavin:$wavsource";

	$log->info( "SquairPlay Playing : $name");
	Slim::Music::Info::setTitle($wavinurl, $name);
#	Slim::Music::Info::setBitrate($wavinurl, $bitrate, $vbr );

	Slim::Control::Command::execute($client, ['playlist', 'play', $wavinurl]);
	Slim::Control::Command::execute($client, ['play']);
}

my %functions = (

	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},

	'play' => sub {
		my $client = shift;
		play($client);
	}

	);


sub lines {

	my $client = shift;

	my($line1, $line2, $overlay);

	# for now, always use the wave mapper
	$wavsource{$client} = 0;

	my $wavsource = $wavsource{$client};
	my $name = "Audio Input $wavsource";

	# TODO: localise this
	$line1 = "SquairPlay";

	# get current song and play mode
	my $playmode = Slim::Player::Source::playmode($client);
	my $stream = Slim::Player::Playlist::song($client);
	
	if ($stream eq undef) {
		$log->info("SquairPlay, in lines playmode=$playmode stream=undef");
		$line2 = "$name (press PLAY)";
		return($line1, $line2, undef, $overlay);
	} else {
		$log->info("SquairPlay, in lines playmode=$playmode stream=$stream");
	}
	
	$stream = $stream->path;

	if ($playmode eq 'play' && $stream =~ /^wavin:/) {
		$line2 = "$name playing";
		$overlay = $client->symbols('notesymbol');
	} else {
		$line2 = "$name (press PLAY)";
	}

	return($line1, $line2, undef, $overlay);
}


sub getFunctions()
{
	return \%functions;
}

sub initPlugin {

	my $class = shift;

	$log->info("Initialising SquairPlay" . $class->_pluginDataFor('version'));
	$log->info("SquairPlay - initPlugin begin...");

	# TODO: platform-specific checking for 
	
	# Check for wavin2cmd - Windows only for now
	#if (Slim::Utils::OSDetect::OS() ne "win") {
	#	$log->info("SquairPlay - non-Windows OS not yet supported");
	#	return 0;
	#}

	#my $path = Slim::Utils::Misc::findbin('wavin2cmd');
	#if (!$path) {
	#	$log->info("SquairPlay - wavin2cmd not found");
	#	return 0;
	#}

	$log->info("SquairPlay - initPlugin ...end");

	return 1;
}

sub webPages {
	my %pages = (
		"index\.(?:htm|xml)" => \&handleWeb,
	);

	Slim::Web::Pages->addPageLinks('radio', { 'PLUGIN_WAVE_INPUT' => 'plugins/WaveInput/index.html' });			

	return (\%pages);
}

sub handleWeb {
	my ($client, $params) = @_;

	if ($client) {
		play($client);
	}
	
	return Slim::Web::HTTP::filltemplatefile('plugins/WaveInput/index.html', $params);
}

1;
