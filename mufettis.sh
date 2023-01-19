#!/bin/bash

test -z ${DOMAIN} && DOMAIN="TEST.LOCAL"
test -z ${DC_USER} && DC_USER="domain.admin"
test -z ${DC_PASS} && DC_PASS="Passw0rd!"
test -z ${STANDALONE_USER} && STANDALONE_USER="administrator" # Even if it is in the administrator group, there is an authorization problem other than the Administrator user.
test -z ${STANDALONE_PASS} && STANDALONE_PASS="Passw0rd!"

test -z ${APP_NAME} && APP_NAME='mufettis'

VAR_DIR="/usr/local/${APP_NAME}"
DATA_DIR="/var/cache/${APP_NAME}"
SSH_KEY="${DATA_DIR}/ssh-key/${APP_NAME}-priv-key"
PSSCRIPS="${VAR_DIR}/psscripts"

ACCESS_FILES_DIR="${DATA_DIR}"
MACHINE_LIST="${VAR_DIR}/machine-list"
MACHINE_NUMBER="$(wc -l < "${MACHINE_LIST}")"

ACTIVE_LIST="/tmp/${APP_NAME}.active"
PROCESS_ID_LIST="/tmp/${APP_NAME}.ids"
PREFIX_TEMP_DIR="${APP_NAME}"
TIMEOUT_VALUE=5

function CPUUsage()
{
	cat <(grep 'cpu ' /proc/stat) <(sleep 1 && grep 'cpu ' /proc/stat) | awk -v RS="" '{printf "%.0f\n", ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5)}'
}

function MemoryInfo()
{
	case ${1,,} in
		tenpercentofyourmemory)
			awk '/MemTotal/ {print int($2*0.1)}' /proc/meminfo;;
		available)
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
	# 1 IP
	# 2 ACCESS FILE
	# 3 COMMAND
	ansible "${1}" -T ${TIMEOUT_VALUE} -m win_shell -a "${3}" -i ${2}
}

function RunCommandViaSSH()
{
	# 1 IP
	# 2 COMMAND
	# 3 PORT
	# 4 SSH OPTIONS
	# 5 USER
	# 6 PASSWORD
	test -z ${1} && return 2
	test -z ${2} && return 2
	test -z ${3} && local SSH_PORT=22 || local SSH_PORT="${3}"
	test -z ${5} && local USER=root || local USER="${5}"
	test -z ${6} || local SSHPASS="sshpass -p ${6}"
	${SSHPASS} ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=${TIMEOUT_VALUE} ${4} ${USER}@${1} -- "${2}"
}

function CopyFilesViaWinRM()
{
	# 1 IP
	# 2 ACCESS FILE
	# 3 SOURCE
	# 4 DESTINATION
	ansible "${1}" -T ${TIMEOUT_VALUE} -m win_copy -a "src=${3} dest=${4}" -i ${2}
}

function CopyFilesViaSSH()
{
	# 1 IP
	# 2 SOURCE
	# 3 DESTINATION
	# 4 PORT
	# 5 SSH OPTIONS
	# 6 USER
	# 7 PASSWORD
	test -z ${1} && return 2
	test -z ${2} && return 2
	test -z ${3} && return 2
	test -z ${4} && local SSH_PORT=22 || local SSH_PORT="${4}"
	test -z ${6} && local USER=root || local USER="${6}"
	test -z ${7} || local SSHPASS="sshpass -p ${7}"
	${SSHPASS} scp -P ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=${TIMEOUT_VALUE} ${5} ${USER}@${1} "${2}" "${3}"
}
function AddToList()
{
	grep -q "^${1}$" "${2}" || echo "${1}" >> ${2}
}

function CreateTempDir()
{
	TEMP_DIR=$(mktemp -d "/tmp/${PREFIX_TEMP_DIR}.XXXXXXX")
}

function CheckLivesViaPing()
{
	# 1 IP
	ping "${1}" -w ${TIMEOUT_VALUE} -c 1 2>&1 > /dev/null

}

function CheckLivesViaWinRM()
{
	# 1 IP
	# 2 COMMAND
	ansible "${1}" -T ${TIMEOUT_VALUE} -m win_shell -a "whoami;hostname;(Get-WmiObject win32_operatingsystem).caption;(Get-WmiObject -Class Win32_ComputerSystem).Domain;(Get-ItemProperty HKLM:\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine).PowerShellVersion" -i "${2}"
}

function CheckLivesViaSSH()
{
	# 1 IP
	# 2 PORT
	# 3 SSH OPTIONS
	# 4 USER
	# 5 PASSWORD
	test -z ${1} && return 2
	test -z ${2} && local SSH_PORT=22 || local SSH_PORT="${2}"
	test -z ${4} && local USER=root || local USER="${4}"
	test -z ${5} || local SSHPASS="sshpass -p ${5}"
	${SSHPASS} ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=${TIMEOUT_VALUE} ${3} ${USER}@${1} -- 'whoami;hostname;cat /etc/issue.net;uname -a'
}

function AddHostsFile()
{
	# 1 IP
	# 2 DNS
	printf "${1}\t${2}\n" >> /etc/hosts
}

function CheckInsideHostsFile()
{
	# 1 IP
	# 2 DNS
	grep -qE "^${1}|${2}$" /etc/hosts
}

function FinalCleaning()
{
	rm -rf "${ACTIVE_LIST}" "${PROCESS_ID_LIST}" "/tmp/${PREFIX_TEMP_DIR}.*"
}

function KeepProcessID()
{
	# 1 UNIQUE
	# 2 PROCESS ID
	printf "${1},${2}\n" >> "${PROCESS_ID_LIST}"
}

function DeleteProcessID()
{
	# 1 UNIQUE
	sed -i "/${1}/d" "${PROCESS_ID_LIST}"
}

function FetchFromMachineList()
{
	# 1 MACHINE LIST LINE NUMBER
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

	MACHINE_WORK_DIR="${DATA_DIR}/${UNIQUE}"

	# Liveness and connectivity checks
	CheckLivesViaPing ${IP} || return 1
	mkdir -p "${DATA_DIR}/${UNIQUE}"
	case "${MACHINE_TYPE,,}" in
		windows)
			ACCESS="${MACHINE_WORK_DIR}/access-file"
			CreateNTLMAccessFile "${ACCESS}" "${USER}" "${PASSWORD}" "${IP}"
			echo "${IP}" > "${MACHINE_WORK_DIR}/output"
			CheckLivesViaWinRM "${IP}" "${ACCESS}" > "${MACHINE_WORK_DIR}/output" 2>&1
			;;
		linux|vmware)
			echo "${IP}" > "${MACHINE_WORK_DIR}/output"
			CheckLivesViaSSH "${IP}" "${PORT}" "${SSH_OPTIONS}" "${USER}" "${PASSWORD}" > "${MACHINE_WORK_DIR}/output" 2>&1
			;;
		*)
			return 1
	esac

	local EXIT_CODE=${?}

	if [ ${EXIT_CODE} == 0 ]
	then
		test -f "${MACHINE_WORK_DIR}/output" && mv "${MACHINE_WORK_DIR}/output" "${MACHINE_WORK_DIR}/machine-info"
	else
		test -f "${MACHINE_WORK_DIR}/output" && mv "${MACHINE_WORK_DIR}/output" "${MACHINE_WORK_DIR}/machine-error"
	fi

	return ${EXIT_CODE}
}

function StartAudit()
{
	case "${MACHINE_TYPE,,}" in
		windows)
			StartWindowsAudit
			;;
		linux)
			StartLinuxAudit
			;;
		vmware)
			StartVMWareAudit
			;;
	esac
	
	DeleteProcessID "${UNIQUE}"
}

function StartWindowsAudit()
{
	# We trigger the commands to run on the machine from this function.
	echo ${UNIQUE}
	echo ${IP}
	echo ${HNAME}
	echo ${MACHINE_TYPE}
	echo ${PORT}
	echo ${SSH_OPTIONS}
	echo ${USER}
	echo ${PASSWORD}
	sleep 5
}

function StartLinuxAudit()
{
	# We trigger the commands to run on the machine from this function.
	echo ${UNIQUE}
	echo ${IP}
	echo ${HNAME}
	echo ${MACHINE_TYPE}
	echo ${PORT}
	echo ${SSH_OPTIONS}
	echo ${USER}
	echo ${PASSWORD}
	sleep 5
}

function StartVMWareAudit()
{
	# We trigger the commands to run on the machine from this function.
	echo ${UNIQUE}
	echo ${IP}
	echo ${HNAME}
	echo ${MACHINE_TYPE}
	echo ${PORT}
	echo ${SSH_OPTIONS}
	echo ${USER}
	echo ${PASSWORD}
	sleep 5
}

function WaitForProcessesToFinish()
{
	while true
	do
		test ! -s "${PROCESS_ID_LIST}" && break
		sleep 1
	done
}

function MainProcess()
{
	if [ "${1,,}" == "query" ]
	then
		QUERY=true
	fi

	rm -rf "${DATA_DIR}"
	mkdir -p "${DATA_DIR}"
	T=1

	while [ ${T} -le ${MACHINE_NUMBER} ]
	do
		WaitIfSystemResourceIsInsufficient
		local MACHINE_INFO=$(FetchFromMachineList "${T}")
		T=$((T+1))
		Preliminary "${MACHINE_INFO}" || continue
		test ! -z ${QUERY} && continue
		StartAudit &
		KeepProcessID "${UNIQUE}" "${!}"
        done

	WaitForProcessesToFinish
}

MainProcess $@
