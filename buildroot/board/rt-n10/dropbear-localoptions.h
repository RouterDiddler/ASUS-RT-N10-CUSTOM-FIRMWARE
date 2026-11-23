/* RT-N10 B1: LAN-only SSH console, public-key login only. */

/* no password logins at all (root has no password on this router) */
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_USE_PASSWORD_ENV 0

/* no forwarding of any kind */
#define DROPBEAR_X11FWD 0
#define DROPBEAR_SVR_AGENTFWD 0
#define DROPBEAR_SVR_LOCALTCPFWD 0
#define DROPBEAR_SVR_REMOTETCPFWD 0
#define DROPBEAR_SVR_LOCALSTREAMFWD 0

/* Ed25519 keys only */
#define DROPBEAR_RSA 0
#define DROPBEAR_DSS 0
#define DROPBEAR_ECDSA 0
#define DROPBEAR_ED25519 1

/* key exchange: curve25519 and ML-KEM768 hybrid (OpenSSH default) */
#define DROPBEAR_CURVE25519 1
#define DROPBEAR_MLKEM768 1
#define DROPBEAR_SNTRUP761 0
#define DROPBEAR_ECDH 0
#define DROPBEAR_DH_GROUP14_SHA256 0
#define DROPBEAR_DH_GROUP14_SHA1 0
#define DROPBEAR_DH_GROUP16 0

/* misc */
#define DO_MOTD 0
#define INETD_MODE 0
#define DROPBEAR_SFTPSERVER 0
