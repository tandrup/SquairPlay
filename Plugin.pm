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
use IPC::Open2;
use IO::Socket;
use MIME::Base64;
use Crypt::OpenSSL::RSA;
eval "use IO::Socket::INET6;";

my %wavsource;			# per-client friendly wavin device name 

my @hw_addr = (0, map { int rand 256 } 1..5);

my $apname = "Squeezebox";

my $airport_pem = join '', <DATA>;
my $rsa = Crypt::OpenSSL::RSA->new_private_key($airport_pem) || die "RSA private key import failed";

my $hairtunes_cli = '/Users/tandrup/Work/SquairPlay/shairport/hairtunes';
my $pipepath = '/Users/tandrup/Work/SquairPlay/shairport/rawpipe';

our $avahi_publish;
our $listen;
our %conns = {};

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
    
    publish_service();   

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

sub shutdownPlugin {
	$log->info("SquairPlay - shutdownPlugin begin...");
    
    unpublish_service();
    
	$log->info("SquairPlay - shutdownPlugin end.");
}

sub publish_service {
    my $portNumber = 5000;
    
    $avahi_publish = fork();
    if ($avahi_publish==0) {
        exec 'avahi-publish-service',
        join('', map { sprintf "%02X", $_ } @hw_addr) . "\@$apname",
        "_raop._tcp",
        "$portNumber",
        "tp=UDP","sm=false","sv=false","ek=1","et=0,1","cn=0,1","ch=2","ss=16","sr=44100","pw=false","vn=3","txtvers=1";
        exec 'dns-sd', '-R',
        join('', map { sprintf "%02X", $_ } @hw_addr) . "\@$apname",
        "_raop._tcp",
        ".",
        "$portNumber",
        "tp=UDP","sm=false","sv=false","ek=1","et=0,1","cn=0,1","ch=2","ss=16","sr=44100","pw=false","vn=3","txtvers=1";
        die "could not run avahi-publish-service nor dns-sd";
    }
    
    {
        eval {
            local $SIG{__DIE__};
            $listen = new IO::Socket::INET6(Listen => 1,
            Domain => AF_INET6,
            LocalPort => $portNumber,
            ReuseAddr => 1,
            Proto => 'tcp');
        };
        if ($@) {
            print "**************************************\n",
            "* IO::Socket::INET6 not present!     *\n",
            "* Install this if iTunes won't play. *\n",
            "**************************************\n\n";
        }
        
        $listen ||= new IO::Socket::INET(Listen => 1,
        LocalPort => $portNumber,
        ReuseAddr => 1,
        Proto => 'tcp');
    }
    die "Can't listen on port $portNumber: $!" unless $listen;

    Slim::Networking::Select::addRead( $listen, \&_readInput );

}

sub unpublish_service {
    kill 9, $avahi_publish;

	if ( defined $listen ) {
		Slim::Networking::Select::removeRead( $listen );
        
		$listen->close;
        
		$listen = undef;
	}
}

sub getFirstClient {
    for my $client ( Slim::Player::Client::clients() ) {
       return $client;
    }
    return undef;
}

sub _readInput {

    my $fh = shift;

    if ($fh==$listen) {
        my $new = $listen->accept;
        $log->info("new connection from ", $new->sockhost);

        Slim::Networking::Select::addRead( $new, \&_readInput );

        $new->blocking(0);
        $conns{$new} = {fh => $fh};

    } else {
        if (eof($fh)) {
            $log->info("Closed connection from ", $fh);
            Slim::Networking::Select::removeRead( $fh, \&_readInput );
            close $fh;
            #eval { kill $conns{$fh}{decoder_pid} };
            delete $conns{$fh};
        }
        if (exists $conns{$fh}) {
            conn_handle_data($fh);
        }
    }
}

sub conn_handle_data {
    my $fh = shift;
    my $conn = $conns{$fh};
    
    if ($conn->{req_need}) {
        if (length($conn->{data}) >= $conn->{req_need}) {
            $conn->{req}->content(substr($conn->{data}, 0, $conn->{req_need}, ''));
            conn_handle_request($fh, $conn);
        }
        undef $conn->{req_need};
        return;
    }
    
    read $fh, my $data, 4096;
    $conn->{data} .= $data;
    
    if ($conn->{data} =~ /(\r\n\r\n|\n\n|\r\r)/) {
        my $req_data = substr($conn->{data}, 0, $+[0], '');
        $conn->{req} = HTTP::Request->parse($req_data);
        printf "REQ: %s\n", $conn->{req}->method;
        conn_handle_request($fh, $conn);
        conn_handle_data($fh) if length($conn->{data});
    }
}

sub conn_handle_request {
    my ($fh, $conn) = @_;
    
    my $req = $conn->{req};;
    my $clen = $req->header('content-length') // 0;
    if ($clen > 0 && !length($req->content)) {
        $conn->{req_need} = $clen;
        return; # need more!
    }
    
    my $resp = HTTP::Response->new(200);
    $resp->request($req);
    $resp->protocol($req->protocol);
    
    $resp->header('CSeq', $req->header('CSeq'));
    $resp->header('Audio-Jack-Status', 'connected; type=analog');
    
    if (my $chall = $req->header('Apple-Challenge')) {
        my $data = decode_base64($chall);
        my $ip = $fh->sockhost;
        if ($ip =~ /((\d+\.){3}\d+)$/) { # IPv4
            $data .= join '', map { chr } split(/\./, $1);
        } else {
            $data .= ip6bin($ip);
        }
        
        $data .= join '', map { chr } @hw_addr;
        $data .= chr(0) x (0x20-length($data));
        
        $rsa->use_pkcs1_padding;    # this isn't hashed before signing
        my $signature = encode_base64 $rsa->private_encrypt($data), '';
        $signature =~ s/=*$//;
        $resp->header('Apple-Response', $signature);
    }
    
    $log->info("Method", $req->method);

    for ($req->method) {
        /^OPTIONS$/ && do {
            $resp->header('Public', 'ANNOUNCE, SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER');
            last;
        };
        
        /^ANNOUNCE$/ && do {
            my $sdptext = $req->content;
            my @sdplines = split /[\r\n]+/, $sdptext;
            my %sdp = map { ($1, $2) if /^a=([^:]+):(.+)/ } @sdplines;
            die("no AESIV") unless my $aesiv = decode_base64($sdp{aesiv});
            die("no AESKEY") unless my $rsaaeskey = decode_base64($sdp{rsaaeskey});
            $rsa->use_pkcs1_oaep_padding;
            my $aeskey = $rsa->decrypt($rsaaeskey) || die "RSA decrypt failed";
            
            $conn->{aesiv} = $aesiv;
            $conn->{aeskey} = $aeskey;
            $conn->{fmtp} = $sdp{fmtp};
            last;
        };
        
        /^SETUP$/ && do {
            my $transport = $req->header('Transport');
            $transport =~ s/;control_port=(\d+)//;
            my $cport = $1;
            $transport =~ s/;timing_port=(\d+)//;
            my $tport = $1;
            $transport =~ s/;server_port=(\d+)//;
            my $dport = $1;
            $resp->header('Session', 'DEADBEEF');
            
            my %dec_args = (
            iv      =>  unpack('H*', $conn->{aesiv}),
            key     =>  unpack('H*', $conn->{aeskey}),
            fmtp    => $conn->{fmtp},
            cport   => $cport,
            tport   => $tport,
            dport   => $dport,
            #                host    => 'unused',
            );
            $dec_args{pipe} = $pipepath if defined $pipepath;

            my $client = getFirstClient();
            
            $log->info("Client should start now", $client);

            my $dec = $hairtunes_cli . join(' ', '', map { sprintf "%s '%s'", $_, $dec_args{$_} } keys(%dec_args));
            
            $log->info("decode command: $dec");
            my $decoder = open2(my $dec_out, my $dec_in, $dec);
            
            $conn->{decoder_pid} = $decoder;
            $conn->{decoder_fh} = $dec_in;
            my $portdesc = <$dec_out>;
            die("Expected port number from decoder; got $portdesc") unless $portdesc =~ /^port: (\d+)/;
            my $port = $1;
            print "launched decoder: $decoder on port: $port\n";
            $resp->header('Transport', $req->header('Transport') . ";server_port=$port");

            #$client->execute(['playlist', 'play', 'http://stream.mainfm.dk/Main128', 'http://stream.mainfm.dk/Main128']);
            $client->execute(['playlist', 'play', 'squairplay:0', 'AirPlay']);

            last;
        };
        
        /^RECORD$/ && last;
        /^FLUSH$/ && do {
            my $dfh = $conn->{decoder_fh};
            print $dfh "flush\n";
            last;
        };
        /^TEARDOWN$/ && do {
            $resp->header('Connection', 'close');
            close $conn->{decoder_fh};
            last;
        };
        /^SET_PARAMETER$/ && do {
            my @lines = split /[\r\n]+/, $req->content;
            my %content = map { /^(\S+): (.+)/; (lc $1, $2) } @lines;
            my $cfh = $conn->{decoder_fh};
            if (exists $content{volume}) {
                printf $cfh "vol: %f\n", $content{volume};
            }
            last;
        };
        /^GET_PARAMETER$/ && last;
        /^DENIED$/ && last;
        die("Unknown method: $_");
    }
    
    print $fh $resp->as_string("\r\n");
    $fh->flush;
}

sub ip6bin {
    my $ip = shift;
    $ip =~ /((.*)::)?(.+)/;
    my @left = split /:/, $2;
    my @right = split /:/, $3;
    my @mid;
    my $pad = 8 - ($#left + $#right + 2);
    if ($pad > 0) {
        @mid = (0) x $pad;
    }
    
    pack('S>*', map { hex } (@left, @mid, @right));
}

1;


__DATA__
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEA59dE8qLieItsH1WgjrcFRKj6eUWqi+bGLOX1HL3U3GhC/j0Qg90u3sG/1CUt
wC5vOYvfDmFI6oSFXi5ELabWJmT2dKHzBJKa3k9ok+8t9ucRqMd6DZHJ2YCCLlDRKSKv6kDqnw4U
wPdpOMXziC/AMj3Z/lUVX1G7WSHCAWKf1zNS1eLvqr+boEjXuBOitnZ/bDzPHrTOZz0Dew0uowxf
/+sG+NCK3eQJVxqcaJ/vEHKIVd2M+5qL71yJQ+87X6oV3eaYvt3zWZYD6z5vYTcrtij2VZ9Zmni/
UAaHqn9JdsBWLUEpVviYnhimNVvYFZeCXg/IdTQ+x4IRdiXNv5hEewIDAQABAoIBAQDl8Axy9XfW
BLmkzkEiqoSwF0PsmVrPzH9KsnwLGH+QZlvjWd8SWYGN7u1507HvhF5N3drJoVU3O14nDY4TFQAa
LlJ9VM35AApXaLyY1ERrN7u9ALKd2LUwYhM7Km539O4yUFYikE2nIPscEsA5ltpxOgUGCY7b7ez5
NtD6nL1ZKauw7aNXmVAvmJTcuPxWmoktF3gDJKK2wxZuNGcJE0uFQEG4Z3BrWP7yoNuSK3dii2jm
lpPHr0O/KnPQtzI3eguhe0TwUem/eYSdyzMyVx/YpwkzwtYL3sR5k0o9rKQLtvLzfAqdBxBurciz
aaA/L0HIgAmOit1GJA2saMxTVPNhAoGBAPfgv1oeZxgxmotiCcMXFEQEWflzhWYTsXrhUIuz5jFu
a39GLS99ZEErhLdrwj8rDDViRVJ5skOp9zFvlYAHs0xh92ji1E7V/ysnKBfsMrPkk5KSKPrnjndM
oPdevWnVkgJ5jxFuNgxkOLMuG9i53B4yMvDTCRiIPMQ++N2iLDaRAoGBAO9v//mU8eVkQaoANf0Z
oMjW8CN4xwWA2cSEIHkd9AfFkftuv8oyLDCG3ZAf0vrhrrtkrfa7ef+AUb69DNggq4mHQAYBp7L+
k5DKzJrKuO0r+R0YbY9pZD1+/g9dVt91d6LQNepUE/yY2PP5CNoFmjedpLHMOPFdVgqDzDFxU8hL
AoGBANDrr7xAJbqBjHVwIzQ4To9pb4BNeqDndk5Qe7fT3+/H1njGaC0/rXE0Qb7q5ySgnsCb3DvA
cJyRM9SJ7OKlGt0FMSdJD5KG0XPIpAVNwgpXXH5MDJg09KHeh0kXo+QA6viFBi21y340NonnEfdf
54PX4ZGS/Xac1UK+pLkBB+zRAoGAf0AY3H3qKS2lMEI4bzEFoHeK3G895pDaK3TFBVmD7fV0Zhov
17fegFPMwOII8MisYm9ZfT2Z0s5Ro3s5rkt+nvLAdfC/PYPKzTLalpGSwomSNYJcB9HNMlmhkGzc
1JnLYT4iyUyx6pcZBmCd8bD0iwY/FzcgNDaUmbX9+XDvRA0CgYEAkE7pIPlE71qvfJQgoA9em0gI
LAuE4Pu13aKiJnfft7hIjbK+5kyb3TysZvoyDnb3HOKvInK7vXbKuU4ISgxB2bB3HcYzQMGsz1qJ
2gG0N5hvJpzwwhbhXqFKA4zaaSrw622wDniAK5MlIE0tIAKKP4yxNGjoD2QYjhBGuhvkWKaXTyY=
-----END RSA PRIVATE KEY-----
