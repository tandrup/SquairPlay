SquairPlay
==========
This is the first hacky attempt at streaming stuff from iTunes/iPhone to Squeezebox Server via AirPlay.

Matthew Flint, m@tthew.org

Pre-requisites
--------------
Avahi, OpenSSL and probably other stuff.

Installation
------------
1. Make a folder somewhere - I called mine "SquairPlay" and cd into it
2. Grab the source from GitHub
3. cd shairport
4. make
5. make a soft-link to your Squeezebox Server plugins directory from SquairPlay
   sudo /path/to/SquairPlay/ /usr/share/squeezeboxserver/Plugins/SquairPlay

Usage
-----
1. restart Squeezebox Server
2. ./shairport.pl
3. Use your SBS web interface to create a Favourite which points to "ShairPlay:"
4. Play something in iTunes or on iPhone
5. Connect to the AirPlay instance which should now be visible
6. Open Favourite for ShairPlay on your Squeezebox

To do
-----
1. Start "./shairport.pl" automatically
2. Update "shairport" to version 0.5 (currently 0.3)
3. Prevent 'hairplay' from using a new port each time it restarts

Bugs
----
Many, probably, including:
1. It's fragile
2. "custom-convert.conf" has a hard-coded path to "/usr/bin/sox" instead of the preferred "[sox]". This is because I'm using x64 Linux, and my version of Squeezebox Server didn't come with x64 binaries in the bundle

