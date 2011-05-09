SquairPlay
========== 
This is the first hacky attempt at streaming stuff from iTunes/iPhone to Squeezebox Server via AirPlay. It's been tested with:

* Squeezebox Server 7.5.3 (r31792)
* Ubuntu 10.10 (x86_64)
* iPhone 4, firmware 4.3.1 (8G4)
* iTunes 10.2.1 (1)

Matthew Flint, m@tthew.org
Mads Tandrup

Warning
-------
I have no intention of maintaing this long-term... so I'm putting it on GitHub and hope that someone will adopt it. ;-) 

Pre-requisites
--------------
Squeezebox Server, Avahi, OpenSSL and probably other stuff.

Installation
------------
1. git clone https://github.com/mflint/SquairPlay.git SquairPlay
2. cd SquairPlay
3. git submodule init
4. git submodule update
5. cd shairport
6. make
7. make a soft-link to your Squeezebox Server plugins directory from SquairPlay:
   sudo /path/to/SquairPlay/ /usr/share/squeezeboxserver/Plugins/SquairPlay
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

