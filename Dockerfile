FROM alpine:latest

RUN apk add --no-cache alpine-sdk rustup \
 && rustup-init -y --target x86_64-unknown-linux-musl \
 && source ~/.cargo/env \
 && cargo install --target x86_64-unknown-linux-musl boringtun

FROM alpine:latest

COPY --from=0 /root/.cargo/bin/boringtun /usr/bin

RUN apk add --no-cache tini wireguard-tools \
 && apk add --no-cache --virtual .build-deps libcap \
 && setcap cap_net_admin+ep /usr/bin/boringtun \
 && apk del --purge .build-deps \
 && printf '%s\n' '#!/bin/sh' 'mkdir -p /var/run/wireguard && chown "$LOGNAME:" /var/run/wireguard && exec su -s /usr/bin/boringtun -- "$LOGNAME" "$@"' \
  | tee /usr/local/bin/boringtun \
 && printf '%s\n' '#!/bin/bash' 'if [[ $# -eq 2 && $1 == up ]]; then' '	eval "$(sed -e "/^# ~~ function override insertion point ~~$/q" /usr/bin/wg-quick)"' '	add_if() { kill -18 $$ && until test -S "/var/run/wireguard/$INTERFACE.sock"; do sleep 1 && kill -0 $$ || return; done; }' '	die() { echo "$PROGRAM: $*" >&2; kill -9 $$; exit 1; }' '	auto_su' '	parse_options "$2"' '	( cmd_up & )' '	kill -19 $$' '	cmd exec "${WG_QUICK_USERSPACE_IMPLEMENTATION:-wireguard-go}" --foreground "$INTERFACE"' 'else' '	exec /usr/bin/wg-quick "$@"' 'fi' \
  | tee /usr/local/bin/wg-quick \
 && chmod a+x /usr/local/bin/boringtun /usr/local/bin/wg-quick

VOLUME ["/etc/wireguard"]

ENV WG_QUICK_USERSPACE_IMPLEMENTATION=boringtun LOGNAME=nobody INTERFACE=wg0

ENTRYPOINT ["/sbin/tini", "--", "/bin/sh", "-c", "test -f \"/etc/wireguard/$INTERFACE.conf\" || ( umask 077 && printf '%s\\n' '[Interface]' 'Address = 10.8.0.1/24' 'PostUp = iptables --table nat --append POSTROUTING --jump MASQUERADE' 'PostDown = iptables --table nat --delete POSTROUTING --jump MASQUERADE' 'ListenPort = 51820' \"PrivateKey = $(wg genkey)\" | tee \"/etc/wireguard/$INTERFACE.conf\" ) && test -c /dev/net/tun || { mkdir -p /dev/net && mknod -m 666 /dev/net/tun c 10 200; } && exec wg-quick up \"$INTERFACE\"", "--"]
