#!/bin/sh
. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

proto_openconnect_init_config() {
	proto_config_add_string "server"
	proto_config_add_int "port"
	proto_config_add_int "mtu"
	proto_config_add_int "juniper"
	proto_config_add_string "interface"
	proto_config_add_string "username"
	proto_config_add_string "serverhash"
	proto_config_add_string "authgroup"
	proto_config_add_string "password"
	proto_config_add_string "password2"
	proto_config_add_string "token_mode"
	proto_config_add_string "token_secret"
	proto_config_add_string "token_script"
	proto_config_add_string "os"
	proto_config_add_string "csd_wrapper"
	proto_config_add_array 'form_entry:regex("[^:]+:[^=]+=.*")'
	proto_config_add_string "dtls_ciphers"
	proto_config_add_string "dtls12_ciphers"
	no_device=1
	available=1
}

proto_openconnect_add_form_entry() {
	[ -n "$1" ] && append cmdline "--form-entry $1"
}

proto_openconnect_setup() {
	local config="$1"

	json_get_vars server port interface username serverhash authgroup password password2 token_mode token_secret token_script os csd_wrapper mtu juniper form_entry dtls_ciphers dtls12_ciphers

	grep -q tun /proc/modules || insmod tun
	ifname="vpn-$config"

	logger -t openconnect "initializing..."

	logger -t "openconnect" "adding host dependency for $server at $config"
	for ip in $(resolveip -t 10 "$server"); do
		logger -t "openconnect" "adding host dependency for $ip at $config"
		proto_add_host_dependency "$config" "$ip" "$interface"
	done

	[ -n "$port" ] && port=":$port"

	cmdline="$server$port -i "$ifname" --non-inter --syslog --script /lib/netifd/vpnc-script"
	[ -n "$mtu" ] && cmdline="$cmdline --mtu $mtu"

	# migrate to standard config files
	[ -f "/etc/config/openconnect-user-cert-vpn-$config.pem" ] && mv "/etc/config/openconnect-user-cert-vpn-$config.pem" "/etc/openconnect/user-cert-vpn-$config.pem"
	[ -f "/etc/config/openconnect-user-key-vpn-$config.pem" ] && mv "/etc/config/openconnect-user-key-vpn-$config.pem" "/etc/openconnect/user-key-vpn-$config.pem"
	[ -f "/etc/config/openconnect-ca-vpn-$config.pem" ] && mv "/etc/config/openconnect-ca-vpn-$config.pem" "/etc/openconnect/ca-vpn-$config.pem"

	[ -f /etc/openconnect/user-cert-vpn-$config.pem ] && append cmdline "-c /etc/openconnect/user-cert-vpn-$config.pem"
	[ -f /etc/openconnect/user-key-vpn-$config.pem ] && append cmdline "--sslkey /etc/openconnect/user-key-vpn-$config.pem"
	[ -f /etc/openconnect/ca-vpn-$config.pem ] && {
		append cmdline "--cafile /etc/openconnect/ca-vpn-$config.pem"
		append cmdline "--no-system-trust"
	}

	# Possible DTLS ciphers were: OC-DTLS1_2-AES128-GCM:OC-DTLS1_2-AES256-GCM:AES256-SHA:AES128-SHA:DES-CBC3-SHA:PSK-NEGOTIATE
	[ -n "$dtls_ciphers" ] && append cmdline "--dtls-ciphers=$dtls_ciphers"

	# Possible DTLS 1.2 ciphers were: AES128-GCM-SHA256:AES256-GCM-SHA384:PSK-NEGOTIATE
	[ -n "$dtls12_ciphers" ] && append cmdline "--dtls12-ciphers=$dtls12_ciphers"

	if [ "${juniper:-0}" -gt 0 ]; then
		append cmdline "--juniper"
	fi

	[ -n "$serverhash" ] && {
		append cmdline " --servercert=$serverhash"
		append cmdline "--no-system-trust"
	}
	[ -n "$authgroup" ] && append cmdline "--authgroup $authgroup"
	[ -n "$username" ] && append cmdline "-u $username"
	[ -n "$password" ] || [ "$token_mode" = "script" ] && {
		umask 077
		mkdir -p /var/etc
		pwfile="/var/etc/openconnect-$config.passwd"
		[ -n "$password" ] && {
			echo "$password" > "$pwfile"
			[ -n "$password2" ] && echo "$password2" >> "$pwfile"
		}
		[ "$token_mode" = "script" ] && {
			$token_script > "$pwfile" 2> /dev/null || {
				logger -t openconenct "Cannot get password from script '$token_script'"
				proto_setup_failed "$config"
			}
		}
		append cmdline "--passwd-on-stdin"
	}

	[ -n "$token_mode" -a "$token_mode" != "script" ] && append cmdline "--token-mode=$token_mode"
	[ -n "$token_secret" ] && append cmdline "--token-secret=$token_secret"
	[ -n "$os" ] && append cmdline "--os=$os"
	[ -n "$csd_wrapper" ] && [ -x "$csd_wrapper" ] && append cmdline "--csd-wrapper=$csd_wrapper"

	json_for_each_item proto_openconnect_add_form_entry form_entry

	proto_export INTERFACE="$config"
	logger -t openconnect "executing 'openconnect $cmdline'"

	if [ -f "$pwfile" ]; then
		proto_run_command "$config" /usr/sbin/openconnect-wrapper $pwfile $cmdline
	else
		proto_run_command "$config" /usr/sbin/openconnect $cmdline
	fi
}

proto_openconnect_teardown() {
	local config="$1"

	pwfile="/var/etc/openconnect-$config.passwd"

	rm -f $pwfile
	logger -t openconnect "bringing down openconnect"
	proto_kill_command "$config" 2
}

add_protocol openconnect
