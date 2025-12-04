#!/bin/bash

# ==============================================================================
# BASH NETSTAT/SS (Saf Bash - Built-ins Only)
# ==============================================================================

function HexToDec() { printf "%d" "0x${1}"; }

function GetStateName()
{
	local STATE_HEX="${1}"
	local PROTO="${2}"

	if [[ "${PROTO}" == *"udp"* ]]; then echo "UNCONN"; return; fi

	case "${STATE_HEX}" in
		"01") echo "ESTAB" ;;	 "02") echo "SYN_SENT" ;;
		"03") echo "SYN_RECV" ;;  "04") echo "FIN_WAIT1" ;;
		"05") echo "FIN_WAIT2" ;; "06") echo "TIME_WAIT" ;;
		"07") echo "CLOSE" ;;	 "08") echo "CLOSE_WAIT" ;;
		"09") echo "LAST_ACK" ;;  "0A") echo "LISTEN" ;;
		"0B") echo "CLOSING" ;;	*)   echo "UNKNOWN" ;;
	esac
}

function ParseIPv4()
{
	local HEX_STR="${1}"
	local IP_BYTES=()
	for (( i=0; i<8; i+=2 )); do
		IP_BYTES+=($(printf "%d" "0x${HEX_STR:$i:2}"))
	done
	echo "${IP_BYTES[3]}.${IP_BYTES[2]}.${IP_BYTES[1]}.${IP_BYTES[0]}"
}

function ParseIPv6()
{
	local HEX_STR="${1}"
	local HEX_PARTS=()
	
	# 1. Okuma ve Hextet Dönüşümü
	for (( i=0; i<32; i+=8 )); do
		local WORD="${HEX_STR:$i:8}"
		local SWAPPED="${WORD:6:2}${WORD:4:2}${WORD:2:2}${WORD:0:2}"
		HEX_PARTS+=("$(printf '%x' 0x${SWAPPED:0:4})")
		HEX_PARTS+=("$(printf '%x' 0x${SWAPPED:4:4})")
	done

	# 2. En Uzun Sıfır Bloğunu Bul
	local MAX_IDX=-1; local MAX_LEN=0
	local CUR_IDX=-1; local CUR_LEN=0

	for (( i=0; i<8; i++ )); do
		if [ "${HEX_PARTS[$i]}" == "0" ]; then
			[ "${CUR_IDX}" -eq -1 ] && CUR_IDX=${i}
			((CUR_LEN++))
		else
			if [ "${CUR_LEN}" -gt "${MAX_LEN}" ]; then
				MAX_LEN=${CUR_LEN}; MAX_IDX=${CUR_IDX}
			fi
			CUR_IDX=-1; CUR_LEN=0
		fi
	done
	[ "${CUR_LEN}" -gt "${MAX_LEN}" ] && { MAX_LEN=${CUR_LEN}; MAX_IDX=${CUR_IDX}; }

	# 3. Adresi Oluştur
	local IP_ADDR=""
	[ "${MAX_LEN}" -lt 2 ] && MAX_IDX=-1

	for (( i=0; i<8; i++ )); do
		if [ "${i}" -eq "${MAX_IDX}" ]; then
			IP_ADDR+="::"
			(( i += MAX_LEN - 1 ))
		else
			IP_ADDR+="${HEX_PARTS[$i]}"
			if [ "${i}" -lt 7 ]; then
				local NEXT=$((i+1))
				[ "${NEXT}" -ne "${MAX_IDX}" ] && IP_ADDR+=":"
			fi
		fi
	done
	echo "${IP_ADDR}"
}

# ==============================================================================
# ANA İŞLEV
# ==============================================================================

function MySS()
{
	# Varsayılan Ayarlar (Hepsi Açık)
	local SHOW_TCP=true
	local SHOW_UDP=true
	local SHOW_4=true
	local SHOW_6=true
	local FILTER_Active=false # Argüman verilirse filtreleme başlar

	# Argümanları Kontrol Et
	for ARG in "$@"; do
		case "${ARG}" in
			-t|--tcp)
				[ "${FILTER_Active}" = false ] && { SHOW_TCP=true; SHOW_UDP=false; FILTER_Active=true; } || SHOW_TCP=true
				;;
			-u|--udp)
				[ "${FILTER_Active}" = false ] && { SHOW_TCP=false; SHOW_UDP=true; FILTER_Active=true; } || SHOW_UDP=true
				;;
			-4)
				SHOW_4=true; SHOW_6=false
				;;
			-6)
				SHOW_4=false; SHOW_6=true
				;;
			-a|--all) # Dinlemeyenleri de göster (CLOSE vb) - Şimdilik LISTEN/UNCONN zorunlu değilse açılabilir
				 ;;
		esac
	done

	# Başlık
	printf "%-6s %-10s %-45s %-45s %s\n" "Proto" "State" "Local Address" "Peer Address" "Process"
	echo "------------------------------------------------------------------------------------------------------------------------------------------"

	local FILES=()
	if [ "${SHOW_TCP}" = true ]; then
		[ "${SHOW_4}" = true ] && FILES+=("/proc/net/tcp")
		[ "${SHOW_6}" = true ] && FILES+=("/proc/net/tcp6")
	fi
	if [ "${SHOW_UDP}" = true ]; then
		[ "${SHOW_4}" = true ] && FILES+=("/proc/net/udp")
		[ "${SHOW_6}" = true ] && FILES+=("/proc/net/udp6")
	fi
	
	for FILE in "${FILES[@]}"; do
		[ ! -f "${FILE}" ] && continue
		
		local PROTO="${FILE##*/}"
		local LINE_NUM=0
		
		while read -r LINE; do
			((LINE_NUM++)); [ "${LINE_NUM}" -eq 1 ] && continue

			local FIELDS=(${LINE})
			local LOCAL_FULL="${FIELDS[1]}"; local REM_FULL="${FIELDS[2]}"
			local STATE_HEX="${FIELDS[3]}";  local INODE="${FIELDS[9]}"
			
			# Filtreleme: TCP ise sadece LISTEN (0A), UDP ise hepsi
			if [[ "${PROTO}" == *"tcp"* && "${STATE_HEX}" != "0A" ]]; then continue; fi

			# IP Ayrıştırma
			local LOCAL_ADDR=""; local REM_ADDR=""
			if [[ "${PROTO}" == *"6" ]]; then
				LOCAL_ADDR=$(ParseIPv6 "${LOCAL_FULL%:*}"); REM_ADDR=$(ParseIPv6 "${REM_FULL%:*}")
			else
				LOCAL_ADDR=$(ParseIPv4 "${LOCAL_FULL%:*}"); REM_ADDR=$(ParseIPv4 "${REM_FULL%:*}")
			fi

			local LOCAL_PORT=$(HexToDec "${LOCAL_FULL#*:}")
			local REM_PORT=$(HexToDec "${REM_FULL#*:}")
			local STATE_STR=$(GetStateName "${STATE_HEX}" "${PROTO}")
			
			local PROCESS_INFO="-"; [ "${INODE}" != "0" ] && PROCESS_INFO="inode=${INODE}"

			printf "%-6s %-10s %-45s %-45s %s\n" \
				"${PROTO}" "${STATE_STR}" "${LOCAL_ADDR}:${LOCAL_PORT}" "${REM_ADDR}:${REM_PORT}" "${PROCESS_INFO}"

		done < "${FILE}"
	done
}

# İşlevi Çalıştır (Argümanları ilet)
MySS "$@"
