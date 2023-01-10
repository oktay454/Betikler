#!/bin/bash

test -z ${DOMAIN} && DOMAIN="TEST.LOCAL"
test -z ${DC_USER} && DC_USER="domain.admin"
test -z ${DC_PASS} && DC_PASS="Passw0rd!"
test -z ${STANDALONE_USER} && STANDALONE_USER="administrator" # Even if it is in the administrator group, there is an authorization problem other than the Administrator user.
test -z ${STANDALONE_PASS} && STANDALONE_PASS="Passw0rd!"

test -z ${APP_NAME} && APP_NAME='mufettis'

VAR_DIR="/usr/local/${APP_NAME}"
DATA_DIR="/var/lib/${APP_NAME}"
SSH_KEY="${DATA_DIR}/ssh-key/${APP_NAME}-priv-key"
PSSCRIPS="${VAR_DIR}/psscripts"

ACCESS_FILES_DIR="${DATA_DIR}"
COMMON_ACCESS_DOMAIN="${ACCESS_FILES_DIR}/access-domain"
COMMON_ACCESS_STANDALONE="${ACCESS_FILES_DIR}/access-standalone"
MACHINE_LIST="${VAR_DIR}/machine-list"
MACHINE_NUMBER="$(cat "${MACHINE_LIST}" | wc -l)"

ACTIVE_LIST="/tmp/${APP_NAME}.active"
PROCESS_ID_LIST="/tmp/${APP_NAME}.ids"
PREFIX_TEMP_DIR="${APP_NAME}"

function CPUUsage()
{
	cat <(grep 'cpu ' /proc/stat) <(sleep 1 && grep 'cpu ' /proc/stat) | awk -v RS="" '{printf "%.0f\n", ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5)}'
}

function MemoryInfo()
{
	case ${1} in
		TenPercentOfYourMemory|tenpercentofyourmemory|TENPERCENTOFYOURMEMORY)
			awk '/MemTotal/ {print int($2*0.1)}' /proc/meminfo;;
		Available|available|AVAILABLE)
			awk '/MemAvailable/ {print $2}' /proc/meminfo;;
	esac
}

function WaitIfSystemResourceIsInsufficient()
{
	while true
	do
		if [ $(MemoryInfo Available) -gt $(MemoryInfo TenPercentOfYourMemory) -a $(CPUUsage) -lt 90 ]
		then
			break
		else
			sleep 5
		fi
	done
}

function ColorEcho()
{
	RED='\e[31m'
	GREEN='\e[32m'
	BLUE='\e[34m'
	YELLOW='\e[1;33m'
	L_BLUE='\e[1;34m'
	NONCOLOR='\e[0m'
	echo -e "${!1}${2}${NONCOLOR}"
}

function CreateNTLMAccessFile()
{
cat > ${1} << EOF
[windows:vars]
ansible_user=${2}
ansible_password=${3}
ansible_port=5985
ansible_connection=winrm
ansible_winrm_transport=ntlm

[windows]
${4}
EOF
}

function RunCommandViaWinRM()
{
	ansible "${1}" -T 5 -m win_shell -a "${3}" -i ${2}
}

function RunCommandViaSSH()
{
	test -z ${3} && local SSH_PORT=22 || local SSH_PORT="${3}"
	ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no ${4} root@${1} -- "${2}"
}

function CopyFilesViaWinRM()
{
	ansible "${1}" -T 5 -m win_copy -a "src=${3} dest=${4}" -i ${2}
}

function CopyFilesViaSSH()
{
	test -z ${4} && local SSH_PORT=22 || local SSH_PORT="${4}"
	scp -P ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no ${5} root@${1} "${2}" "${3}"
}
function AddToList()
{
	grep -q "^${1}$" "${2}" || echo "${1}" >> ${2}
}

function CreateTempDir()
{
	TEMP_DIR=$(mktemp -d /tmp/${PREFIX_TEMP_DIR}.XXXXXXX)
}

function CheckLivesViaPing()
{
	ping "${1}" -c 1 2>&1 > /dev/null

}

function CheckLivesViaWinRM()
{
	ansible "${1}" -T 5 -m win_shell -a "whoami" -i "${2}" 2>&1 > /dev/null
}

function CheckLivesViaSSH()
{
	test -z ${2} && local SSH_PORT=22 || local SSH_PORT="${2}"
	ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no ${3} root@${1} -- whoami 2>&1 > /dev/null
}

function AddHostsFile()
{
	printf "${1}\t${2}\n" >> /etc/hosts
}

function CheckInsideHostsFile()
{
	grep -qE "^${1}|${2}$" /etc/hosts
}

function FinalCleaning()
{
	rm -rf "${ACTIVE_LIST}" "${PROCESS_ID_LIST}" "/tmp/${PREFIX_TEMP_DIR}.*"
}

function KeepProcessID()
{
	printf "${1},${2}\n" >> "${PROCESS_ID_LIST}"
}

function DeleteProcessID()
{
	sed -i "/${1}/d" "${PROCESS_ID_LIST}"
}

function FetchFromMachineList()
{
	sed -n ${1}p "${MACHINE_LIST}"
}

function Preliminary()
{
	# Obtaining machine information
	UNIQUE="$(echo ${1} | sha256sum | awk '{print $1}')"
	IP="$(awk -F "," '{print $1}' <<< ${1})"
	HNAME="$(awk -F "," '{print $2}' <<< ${1})"
	MACHINE_TYPE="$(awk -F "," '{print $3}' <<< ${1})"
	PORT="$(awk -F "," '{print $4}' <<< ${1})"
	SSH_OPTIONS="$(awk -F "," '{print $5}' <<< ${1})"
	USER="$(awk -F "," '{print $6}' <<< ${1})"
	PASSWORD="$(awk -F "," '{print $7}' <<< ${1} | base64 -d)"

	# Liveness and connectivity checks
	CheckLivesViaPing ${IP} || return 1
	case "${MACHINE_TYPE}" in
		domain|stanalone|windows)
			ACCESS="${ACCESS_FILES_DIR}/access-${UNIQUE}"
			CreateNTLMAccessFile "${ACCESS}" "${USER}" "${PASSWORD}" "${IP}"
			CheckLivesViaWinRM "${IP}" "${ACCESS}";;
		linux|vmware)
			CheckLivesViaSSH "${IP}" "${PORT}" "${SSH_OPTIONS}";;
		*)
			return 1
	esac

#	CheckInsideHostsFile "${IP}" "${HNAME}" || AddHostsFile "${IP}" "${HNAME}"
#	
#	case "${MACHINE_TYPE}" in
#		domain)
#			ACCESS="${ACCESS_DOMAIN}"
#			test -f "${ACCESS}" || CreateNTLMAccessFile "${ACCESS}" "${DC_USER}" "${DC_PASS}"
#			AddToList "${HNAME}" "${ACCESS}"
#			;;
#		standalone)
#			ACCESS="${ACCESS_STANDALONE}"
#			test -f "${ACCESS}" || CreateNTLMAccessFile "${ACCESS}" "${STANDALONE_USER}" "${STANDALONE_PASS}"
#			AddToList "${HNAME}" "${ACCESS}"
#			;;
#		*)
#			;;
#	esac
}

function StartAudit()
{
	case "${MACHINE_TYPE}" in
		domain|standalone|windows)
			StartWindowsAudit "${IP}" &
			KeepProcessID "${UNIQUE}" "${!}"
			;;
		linux)
			StartLinuxAudit "${IP}" &
			KeepProcessID "${UNIQUE}" "${!}"
			;;
		vmware)
			StartVMWareAudit "${IP}" &
			KeepProcessID "${UNIQUE}" "${!}"
			;;
	esac
}

function StartWindowsAudit()
{
	# We trigger the commands to run on the machine from this function.


	# To clear the PID register when the function is finished.
	DeleteProcessID "${UNIQUE}"
}

function StartLinuxAudit()
{
	# We trigger the commands to run on the machine from this function.


	# To clear the PID register when the function is finished.
	DeleteProcessID "${UNIQUE}"
}

function StartVMWareAudit()
{
	# We trigger the commands to run on the machine from this function.


	# To clear the PID register when the function is finished.
	DeleteProcessID "${UNIQUE}"
}

function WaitForProcessesToFinish()
{
	set -x
	while true
	do
		test ! -s "${PROCESS_ID_LIST}" && break
		sleep 1
	done
}

function MainProcess()
{
	rm -rf "${DATA_DIR}" "${ACCESS_FILES_DIR}/access-*"
	mkdir -p "${DATA_DIR}"
	T=1

	while [ ${T} -le ${MACHINE_NUMBER} ]
	do
		WaitIfSystemResourceIsInsufficient
		local MACHINE_INFO=$(FetchFromMachineList "${T}")
		T=$((T+1))
		Preliminary "${MACHINE_INFO}" || continue
		StartAudit
#		T=$((T+1))
        done

	WaitForProcessesToFinish
}

MainProcess
