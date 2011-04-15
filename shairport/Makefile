CFLAGS = `pkg-config --cflags --libs openssl`

hairtunes: hairtunes.c alac.c
	gcc hairtunes.c alac.c -D__i386 -pthread -lm $(CFLAGS) -o hairtunes
