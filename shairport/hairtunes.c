/*
 * HairTunes - RAOP packet handler and slave-clocked replay engine
 * Copyright (c) James Laird 2011
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <openssl/aes.h>
#include <math.h>

#include <assert.h>
int debug = 0;

#include "alac.h"

// default buffer - about half a second
#define BUFFER_FRAMES   64
#define START_FILL    55
#define MAX_PACKET      2048

typedef unsigned short seq_t;

// global options (constant after init)
unsigned char aeskey[16], aesiv[16];
AES_KEY aes;
char *rtphost = 0;
int dataport = 0, controlport = 0, timingport = 0;
int fmtp[32];
int sampling_rate;
int frame_size;
#define FRAME_BYTES (4*frame_size)
// maximal resampling shift - conservative
#define OUTFRAME_BYTES (4*(frame_size+3))


alac_file *decoder_info;

void rtp_request_resend(seq_t first, seq_t last);
void init_buffer(void);
void ab_resync(void);

// interthread variables
  // stdin->decoder
volatile double volume = 1.0;
volatile long fix_volume = 0x10000;

typedef struct audio_buffer_entry {   // decoded audio packets
    int ready;
    signed short *data;
} abuf_t;
volatile abuf_t audio_buffer[BUFFER_FRAMES];
#define BUFIDX(seqno) ((seq_t)(seqno) % BUFFER_FRAMES)

// mutex-protected variables
volatile seq_t ab_read, ab_write;
int ab_buffering = 1, ab_synced = 0;
pthread_mutex_t ab_mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t ab_buffer_ready = PTHREAD_COND_INITIALIZER;

void die(char *why) {
    fprintf(stderr, "FATAL: %s\n", why);
    exit(1);
}

int hex2bin(unsigned char *buf, char *hex) {
    int i, j;
    if (strlen(hex) != 0x20)
        return 1;
    for (i=0; i<0x10; i++) {
        if (!sscanf(hex, "%2X", &j))
           return 1;
        hex += 2;
        *buf++ = j;
    }
    return 0;
}

int init_decoder(void) {
    alac_file *alac;

    frame_size = fmtp[1]; // stereo samples
    sampling_rate = fmtp[11];

    int sample_size = fmtp[3];
    if (sample_size != 16)
        die("only 16-bit samples supported!");
    
    alac = create_alac(sample_size, 2);
    if (!alac)
        return 1;
    decoder_info = alac;

    alac->setinfo_max_samples_per_frame = frame_size;
    alac->setinfo_7a =      fmtp[2];
    alac->setinfo_sample_size = sample_size;
    alac->setinfo_rice_historymult = fmtp[4];
    alac->setinfo_rice_initialhistory = fmtp[5];
    alac->setinfo_rice_kmodifier = fmtp[6];
    alac->setinfo_7f =      fmtp[7];
    alac->setinfo_80 =      fmtp[8];
    alac->setinfo_82 =      fmtp[9];
    alac->setinfo_86 =      fmtp[10];
    alac->setinfo_8a_rate = fmtp[11];
    allocate_buffers(alac);
    return 0;
}

int main(int argc, char **argv) {
    char *hexaeskey = 0, *hexaesiv = 0;
    char *fmtpstr = 0;
    char *arg;
    int i;
    assert(RAND_MAX >= 0x10000);    // XXX move this to compile time
    while (arg = *++argv) {
        if (!strcasecmp(arg, "iv")) {
            hexaesiv = *++argv;
            argc--;
        } else
        if (!strcasecmp(arg, "key")) {
            hexaeskey = *++argv;
            argc--;
        } else
        if (!strcasecmp(arg, "fmtp")) {
            fmtpstr = *++argv;
        } else
        if (!strcasecmp(arg, "cport")) {
            controlport = atoi(*++argv);
        } else
        if (!strcasecmp(arg, "tport")) {
            timingport = atoi(*++argv);
        } else
        if (!strcasecmp(arg, "dport")) {
            dataport = atoi(*++argv);
        } else
        if (!strcasecmp(arg, "host")) {
            rtphost = *++argv;
        }
    }

    if (!hexaeskey || !hexaesiv)
        die("Must supply AES key and IV!");

    if (hex2bin(aesiv, hexaesiv))
        die("can't understand IV");
    if (hex2bin(aeskey, hexaeskey))
        die("can't understand key");
    AES_set_decrypt_key(aeskey, 128, &aes);

    memset(fmtp, 0, sizeof(fmtp));
    i = 0;
    while (arg = strsep(&fmtpstr, " \t"))
        fmtp[i++] = atoi(arg);

    init_decoder();
    init_buffer();
    init_rtp();      // open a UDP listen port and start a listener; decode into ring buffer
    fflush(stdout);
    init_output();              // resample and output from ring buffer
    
    char line[128];
    int in_line = 0;
    int n;
    double f;
    while (fgets(line + in_line, sizeof(line) - in_line, stdin)) {
        n = strlen(line);
        if (line[n-1] != '\n') {
            in_line = strlen(line) - 1;
            if (n == sizeof(line)-1)
                in_line = 0;
            continue;
        }
        if (sscanf(line, "vol: %lf\n", &f)) {
            assert(f<=0);
            if (debug)
                fprintf(stderr, "VOL: %lf\n", f);
            volume = pow(10.0,0.1*f);
            fix_volume = 65536.0 * volume;
            continue;
        }
        if (!strcmp(line, "exit\n")) {
            exit(0);
        }
        if (!strcmp(line, "flush\n")) {
            pthread_mutex_lock(&ab_mutex);
            ab_resync();
            pthread_mutex_unlock(&ab_mutex);
            if (debug)
                fprintf(stderr, "FLUSH\n");
        }
    }
//    fprintf(stderr, "bye!\n");
    fflush(stderr);
}

void init_buffer(void) {
    int i;
    for (i=0; i<BUFFER_FRAMES; i++)
        audio_buffer[i].data = malloc(OUTFRAME_BYTES);
    ab_resync();
}

void ab_resync(void) {
    int i;
    for (i=0; i<BUFFER_FRAMES; i++)
        audio_buffer[i].ready = 0;
    ab_synced = 0;
}

// the sequence numbers will wrap pretty often.
// this returns true if the second arg is after the first
static inline int seq_order(seq_t a, seq_t b) {
    signed short d = b - a;
    return d > 0;
}

void alac_decode(short *dest, char *buf, int len) {
    char packet[MAX_PACKET];
    assert(len<=MAX_PACKET);

    char iv[16];
    int i;
    memcpy(iv, aesiv, sizeof(iv));
    for (i=0; i+16<=len; i += 16)
        AES_cbc_encrypt(buf+i, packet+i, 0x10, &aes, iv, AES_DECRYPT);
    if (len & 0xf)
        memcpy(packet+i, buf+i, len & 0xf);

    int outsize;

    decode_frame(decoder_info, packet, dest, &outsize);

    assert(outsize == FRAME_BYTES);
}

void buffer_put_packet(seq_t seqno, char *data, int len) {
    volatile abuf_t *abuf = 0;
    short read;
    short buf_fill;

    pthread_mutex_lock(&ab_mutex);
    if (!ab_synced) {
        ab_write = seqno;
        ab_read = seqno-1;
        ab_synced = 1;
    }
    if (seqno == ab_write+1) {                  // expected packet
        abuf = audio_buffer + BUFIDX(seqno);
        ab_write = seqno;
    } else if (seq_order(ab_write, seqno)) {    // newer than expected
        rtp_request_resend(ab_write, seqno-1);
        abuf = audio_buffer + BUFIDX(seqno);
        ab_write = seqno;
    } else if (seq_order(ab_read, seqno)) {     // late but not yet played
        abuf = audio_buffer + BUFIDX(seqno);
    } else {    // too late.
        fprintf(stderr, "\nlate packet %04X (%04X:%04X)\n", seqno, ab_read, ab_write);
    }
    buf_fill = ab_write - ab_read;
    pthread_mutex_unlock(&ab_mutex);

    if (abuf) {
        alac_decode(abuf->data, data, len);
        abuf->ready = 1;
    }

    if (ab_buffering && buf_fill >= START_FILL)
        pthread_cond_signal(&ab_buffer_ready);
    if (!ab_buffering) {
        // check if the t+10th packet has arrived... last-chance resend
        read = ab_read + 10;
        abuf = audio_buffer + BUFIDX(read);
        if (!abuf->ready)
            rtp_request_resend(read, read);
    }
}

static int rtp_sockets[2];  // data, control
#ifdef AF_INET6
    struct sockaddr_in6 rtp_client;
#else
    struct sockaddr_in rtp_client;
#endif

void *rtp_thread_func(void *arg) {
    socklen_t si_len = sizeof(rtp_client);
    char packet[MAX_PACKET];
    char *pktp;
    seq_t seqno;
    ssize_t plen;
    int sock = rtp_sockets[0], csock = rtp_sockets[1];
    int readsock;
    char type;

    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    FD_SET(csock, &fds);

    while (select(csock>sock ? csock+1 : sock+1, &fds, 0, 0, 0)!=-1) {
        if (FD_ISSET(sock, &fds)) {
            readsock = sock;
        } else {
            readsock = csock;
        }
        FD_SET(sock, &fds);
        FD_SET(csock, &fds);

        plen = recvfrom(readsock, packet, sizeof(packet), 0, (struct sockaddr*)&rtp_client, &si_len);
        if (plen < 0)
            continue;
        assert(plen<=MAX_PACKET);
            
        type = packet[1] & ~0x80;
        if (type == 0x60 || type == 0x56) {   // audio data / resend
            pktp = packet;
            if (type==0x56) {
                pktp += 4;
                plen -= 4;
            }
            seqno = ntohs(*(unsigned short *)(pktp+2));
            buffer_put_packet(seqno, pktp+12, plen-12);
        }
    }
}

void rtp_request_resend(seq_t first, seq_t last) {
    if (seq_order(last, first))
        return;

//    fprintf(stderr, "requesting resend on %d packets (port %d)\n", last-first+1, controlport);

    char req[8];    // *not* a standard RTCP NACK
    req[0] = 0x80;
    req[1] = 0x55|0x80;  // Apple 'resend'
    *(unsigned short *)(req+2) = htons(1);  // our seqnum
    *(unsigned short *)(req+4) = htons(first);  // missed seqnum
    *(unsigned short *)(req+6) = htons(last-first+1);  // count

#ifdef AF_INET6
    rtp_client.sin6_port = htons(controlport);
#else
    rtp_client.sin_port = htons(controlport);
#endif
    sendto(rtp_sockets[1], req, sizeof(req), 0, (struct sockaddr *)&rtp_client, sizeof(struct sockaddr_in));
}


int init_rtp(void) {
#ifdef AF_INET6
    struct sockaddr_in6 si;
    int type = AF_INET6;
    short *sin_port = &si.sin6_port;
#else
    struct sockaddr_in si;
    int type = AF_INET;
    short *sin_port = &si.sin_port;
#endif
    int sock, csock;    // data and control (we treat the streams the same here)

    sock = socket(type, SOCK_DGRAM, IPPROTO_UDP);
    if (sock==-1)
        die("Can't create socket!");

    memset(&si, 0, sizeof(si));
#ifdef AF_INET6
    si.sin6_family = AF_INET6;
    #ifdef SIN6_LEN
        si.sin6_len = sizeof(si);
    #endif
    si.sin6_addr = in6addr_any;
    si.sin6_flowinfo = 0;
#else
    si.sin_family = AF_INET;
    si.sin_len = sizeof(si);
    si.sin_addr.s_addr = htonl(INADDR_ANY);
#endif

    unsigned short port = 6000 - 3;
    do {
        port += 3;
        *sin_port = htons(port);
    } while (bind(sock, (struct sockaddr*)&si, sizeof(si))==-1);

    csock = socket(type, SOCK_DGRAM, IPPROTO_UDP);
    if (csock==-1)
        die("Can't create socket!");
    *sin_port = htons(port + 1);
    if (bind(csock, (struct sockaddr*)&si, sizeof(si))==-1)
        die("can't bind control socket");

    printf("port: %d\n", port); // let our handler know where we end up listening
    printf("cport: %d\n", port+1);

    pthread_t rtp_thread;
    rtp_sockets[0] = sock;
    rtp_sockets[1] = csock;
    pthread_create(&rtp_thread, NULL, rtp_thread_func, (void *)rtp_sockets);

    return port;
}

static inline short dithered_vol(short sample) {
    static short rand_a, rand_b;
    long out;
    rand_b = rand_a;
    rand_a = rand() & 0xffff;

    out = (long)sample * fix_volume;
    if (fix_volume < 0x10000) {
        out += rand_a;
        out -= rand_b;
    }
    return out>>16;
}

typedef struct {
    double hist[2];
    double a[2];
    double b[3];
} biquad_t;

static void biquad_init(biquad_t *bq, double a[], double b[]) {
    bq->hist[0] = bq->hist[1] = 0.0;
    memcpy(bq->a, a, 2*sizeof(double));
    memcpy(bq->b, b, 3*sizeof(double));
}

static void biquad_lpf(biquad_t *bq, double freq, double Q) {
    double w0 = 2*M_PI*freq/((float)sampling_rate/(float)frame_size);
    double alpha = sin(w0)/(2.0*Q);

    double a_0 = 1.0 + alpha;
    double b[3], a[2];
    b[0] = (1.0-cos(w0))/(2.0*a_0);
    b[1] = (1.0-cos(w0))/a_0;
    b[2] = b[0];
    a[0] = -2.0*cos(w0)/a_0;
    a[1] = (1-alpha)/a_0;

    biquad_init(bq, a, b);
}

static double biquad_filt(biquad_t *bq, double in) {
    double w = in - bq->a[0]*bq->hist[0] - bq->a[1]*bq->hist[1];
    double out = bq->b[1]*bq->hist[0] + bq->b[2]*bq->hist[1] + bq->b[0]*w;
    bq->hist[1] = bq->hist[0];
    bq->hist[0] = w;
}

double bf_playback_rate = 1.0;

static double bf_est_drift = 0.0;   // local clock is slower by 
static biquad_t bf_drift_lpf;
static double bf_est_err = 0.0, bf_last_err;
static biquad_t bf_err_lpf, bf_err_deriv_lpf;
static double desired_fill;
static int fill_count;

void bf_est_reset(short fill) {
    biquad_lpf(&bf_drift_lpf, 1.0/180.0, 0.3);
    biquad_lpf(&bf_err_lpf, 1.0/10.0, 0.25);
    biquad_lpf(&bf_err_deriv_lpf, 1.0/2.0, 0.2);
    fill_count = 0;
    bf_playback_rate = 1.0;
    bf_est_err = bf_last_err = 0;
    desired_fill = fill_count = 0;
}
void bf_est_update(short fill) {
    if (fill_count < 1000) {
        desired_fill += (double)fill/1000.0;
        fill_count++;
        return;
    }

#define CONTROL_A   (1e-4)
#define CONTROL_B   (1e-1)

    double buf_delta = fill - desired_fill;
    bf_est_err = biquad_filt(&bf_err_lpf, buf_delta);
    double err_deriv = biquad_filt(&bf_err_deriv_lpf, bf_est_err - bf_last_err);

    bf_est_drift = biquad_filt(&bf_drift_lpf, CONTROL_B*(bf_est_err*CONTROL_A + err_deriv) + bf_est_drift);

    if (debug)
        fprintf(stderr, "bf %d err %f drift %f desiring %f ed %f estd %f\r", fill, bf_est_err, bf_est_drift, desired_fill, err_deriv, err_deriv + CONTROL_A*bf_est_err);
    bf_playback_rate = 1.0 + CONTROL_A*bf_est_err + bf_est_drift;
    
    bf_last_err = bf_est_err;
}

// get the next frame, when available. return 0 if underrun/stream reset.
short *buffer_get_frame(void) {
    short buf_fill;
    seq_t read;

    pthread_mutex_lock(&ab_mutex);
    
    buf_fill = ab_write - ab_read;
    if (buf_fill < 1 || !ab_synced) {    // init or underrun. stop and wait
//        if (ab_synced)
//            fprintf(stderr, "\nunderrun.\n");

        ab_buffering = 1;
        pthread_cond_wait(&ab_buffer_ready, &ab_mutex);
        ab_read++;
        buf_fill = ab_write - ab_read;
        pthread_mutex_unlock(&ab_mutex);

        bf_est_reset(buf_fill);
        return 0;
    }
    if (buf_fill >= BUFFER_FRAMES) {   // overrunning! uh-oh. restart at a sane distance
//        fprintf(stderr, "\noverrun.\n");
        ab_read = ab_write - START_FILL;
    }
    read = ab_read;
    ab_read++;
    pthread_mutex_unlock(&ab_mutex);

    buf_fill = ab_write - ab_read;
    bf_est_update(buf_fill);

    volatile abuf_t *curframe = audio_buffer + BUFIDX(read);
    if (!curframe->ready) {
//        fprintf(stderr, "\nmissing frame.\n");
        memset(curframe->data, 0, FRAME_BYTES);
    }
    curframe->ready = 0;
    return curframe->data;
}

int stuff_buffer(double playback_rate, short *inptr, short *outptr) {
    int i;
    int stuffsamp = frame_size;
    int stuff = 0;
    double p_stuff;

    p_stuff = 1.0 - pow(1.0 - fabs(playback_rate-1.0), frame_size);

    if ((float)rand()/((float)RAND_MAX) < p_stuff) {
        stuff = playback_rate > 1.0 ? -1 : 1;
        stuffsamp = rand() % (frame_size - 1);
    }

    for (i=0; i<stuffsamp; i++) {   // the whole frame, if no stuffing
        *outptr++ = dithered_vol(*inptr++);
        *outptr++ = dithered_vol(*inptr++);
    };
    if (stuff) {
        if (stuff==1) {
            if (debug)
                fprintf(stderr, "+++++++++\n");
            // interpolate one sample
            *outptr++ = dithered_vol(((long)inptr[-2] + (long)inptr[0]) >> 1);
            *outptr++ = dithered_vol(((long)inptr[-1] + (long)inptr[1]) >> 1);
        } else if (stuff==-1) {
            if (debug)
                fprintf(stderr, "---------\n");
            inptr++;
            inptr++;
        }
        for (i=stuffsamp; i<frame_size + stuff; i++) {
            *outptr++ = dithered_vol(*inptr++);
            *outptr++ = dithered_vol(*inptr++);
        }
    }
}

void *audio_thread_func(void *arg) {
    int i, play_samples;

    signed short buf_fill;
    signed short *inbuf, *outbuf;
    outbuf = malloc(OUTFRAME_BYTES);

	while (1) {
		//printf("Waiting for someone to read the pipe");
		//int fd = open("rawpipe", O_WRONLY);
		//printf("Got a reader!");
		int fd = -1;

		while (1) {
			do {
				inbuf = buffer_get_frame();
			} while (!inbuf);

			if (fd == -1) {
				// attempt to open the pipe, but don't block if there are no readers
				fd = open("rawpipe", O_WRONLY | O_NDELAY);
				if (fd != -1) {
					fprintf(stderr, "[open]");
				}
			}
			if (fd != -1) {
				play_samples = stuff_buffer(bf_playback_rate, inbuf, outbuf);

				write(fd, outbuf, play_samples*4);
			}
		}
	}
}

int init_output(void) {
    mknod("rawpipe", S_IFIFO | 0644, 0);

    pthread_t audio_thread;
    pthread_create(&audio_thread, NULL, audio_thread_func, NULL);
}
