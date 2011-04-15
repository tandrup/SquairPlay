SquairPlay
========== 
This is the first hacky attempt at streaming stuff from iTunes/iPhone to Squeezebox Server via AirPlay. It's been tested with:

* Squeezebox Server 7.5.3 (r31792)
* Ubuntu 10.10 (x86_64)
* iPhone 4, firmware 4.3.1 (8G4)
* iTunes 10.2.1 (1)

Matthew Flint, m@tthew.org

Warning
-------
I have no intention of maintaing this long-term... so I'm putting it on GitHub and hope that someone will adopt it. ;-) 

Pre-requisites
--------------
Squeezebox Server, Avahi, OpenSSL and probably other stuff.

Installation
------------
1. Make a folder somewhere - I called mine "SquairPlay" and cd into it
2. Grab the source from GitHub
3. cd shairport
4. make
5. a file "rawpipe" will appear in the "shairport" directory. The "custom-convert.conf" (in the directory above) needs to be told where the rawpipe is, so change the path
6. make a soft-link to your Squeezebox Server plugins directory from SquairPlay:
   sudo /path/to/SquairPlay/ /usr/share/squeezeboxserver/Plugins/SquairPlay

Usage
-----
1. restart Squeezebox Server
2. ./shairport.pl
3. Use your SBS web interface to create a Favourite with URL "squairplay:0" (that's a zero)
4. Play something in iTunes or on iPhone
5. Connect iTunes/iPhone to the AirPlay instance which should now be available
6. Play the SquairPlay favourite on your Squeezebox

To do
-----
1. Start "./shairport.pl" automatically
2. Update "shairport" to version 0.5 (currently 0.3)
3. Prevent 'hairplay' from using a new port each time it restarts
4. Fix the "wav" and "flac" entries in "custom-convert.conf"
5. Provide a settings page where user can enter the AirPort private key. We probably shouldn't distribute the key with the plugin
6. Investigate whether the AirPort protocol sends metadata about the currently-playing track?

Bugs
----
Probably many, including:

1. It's fragile
2. The quality isn't great
3. Only the mp3 conversion is currently close to being functional
4. Think the sample rate might be wrong, because music skips
5. There's a lot of buffering, so it takes a long time for audio to start or stop

