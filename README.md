SquairPlay
========== 
This is a hacky attempt at streaming stuff from iTunes/iPhone to Squeezebox Server via AirPlay. It's been tested with:

* Squeezebox Server 7.5.4 (r31792)
* Mac OS X Snow Leopard
* iPhone 4, firmware 4.3.3

It starts publishing its services when the first Squeezebox connects. And automatically stops again when the server stops or the Squeezebox disconnects. Since I only own one Squeezebox the support for multiple squeezeboxes is not very good. The server will simple pick the first available Squeezebox and start streaming to it.

It seems that iTunes have some trouble with multiple AirPlay services on the same machine. But more investigation is needed.

Contributors
------------
* Matthew Flint, m@tthew.org
* Mads Tandrup

Pre-requisites
--------------
Squeezebox Server, Avahi, OpenSSL and probably other stuff.

For Mac OS X I needed to install lame. 
  brew install lame

Installation
------------
1. git clone https://github.com/tandrup/SquairPlay.git SquairPlay
2. cd SquairPlay
3. git submodule init
4. git submodule update
5. cd shairport
6. make
7. make a soft-link to your Squeezebox Server plugins directory from SquairPlay:
   On Linux:
   sudo ln -s /usr/share/squeezeboxserver/Plugins/SquairPlay /path/to/SquairPlay/ 
   On Mac:
   sudo ln -s ~/Library/Application Support/Squeezebox/Plugins/SquairPlay /path/to/SquairPlay/
8. Adjust paths in Plugin.pm and custom-convert.conf (in the SquairPlay directory)

Usage
-----
1. restart Squeezebox Server
2. Play something in iTunes or on iPhone
3. Connect iTunes/iPhone to the AirPlay instance which should now be available
4. Your Squeezebox should now begin to play

To do
-----
1. Prevent 'hairplay' from using a new port each time it restarts
2. Fix the "wav" and "flac" entries in "custom-convert.conf"
3. Provide a settings page where user can enter the AirPort private key. We probably shouldn't distribute the key with the plugin
4. Investigate whether the AirPort protocol sends metadata about the currently-playing track?

Bugs
----
Probably many, including:

1. It's fragile
2. The quality isn't great
3. Only the mp3 conversion is currently close to being functional
4. Think the sample rate might be wrong, because music skips
5. There's a lot of buffering, so it takes a long time for audio to start or stop

