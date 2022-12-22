#!/bin/bash

DOMAIN="TEST.LOCAL"
DC_USER="domain.admin"
DC_PASS="Passw0rd!"
STANDALONE_USER="administrator" # Even if it is in the administrator group, there is an authorization problem other than the Administrator user.
STANDALONE_PASS="Passw0rd!"

APP_NAME="health-audit"

VAR_DIR="/usr/local/${APP_NAME}"
DATA_DIR="/var/lib/${APP_NAME}"
SSH_KEY="${DATA_DIR}/ssh-key/${APP_NAME}-priv-key"
PSSCRIPS="${VAR_DIR}/psscripts"

ACCESS_DOMAIN="${DATA_DIR}/access-domain"
ACCESS_STANDALONE="${DATA_DIR}/access-standalone"
MACHINE_LIST="${DATA_DIR}/machine-list"
MACHINE_NUMBER="$(cat "${MACHINE_LIST}" | wc -l)"

ACTIVE_LIST="/tmp/${APP_NAME}.active"
PROCESS_ID_LIST="/tmp/${APP_NAME}.ids"
PREFIX_TEMP_DIR="${APP_NAME}"

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
EOF
}

function RunCommandViaWinRM()
{
	ansible "${1}" -m win_shell -a "${3}" -i ${2}
}

function RunCommandViaSSH()
{
	test -z ${3} && local SSH_PORT=22
	ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=yes "${4}" root@${1} -- "${2}"
}

function CopyFilesViaWinRM()
{
	ansible "${1}" -m win_copy -a "src=${3} dest=${4}" -i ${2}
}

function CopyFilesViaSSH()
{
	test -z ${4} && local SSH_PORT=22
	scp -P ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=yes "${5}" root@${1} "${2}" "${3}"
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
	ansible "${1}" -m win_shell -a "whoami" -i "${2}" 2>&1 > /dev/null
}

function CheckLivesWithSSH()
{
	test -z ${2} && local SSH_PORT=22
	ssh -p ${SSH_PORT} -i "${SSH_KEY}" - -o StrictHostKeyChecking=yes "${3}" root@${1} -- whoami 2>&1 > /dev/null

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
	sed -i "d/${1}$/g" "${PROCESS_ID_LIST}"
}

function FetchFromMachineList()
{
	sed -n ${1}p "${MACHINE_LIST}"
}

function Preliminary()
{
	# Obtaining machine information
	IP="$(awk -F "," '{print $1}' <<< ${1})"
	HNAME="$(awk -F "," '{print $2}' <<< ${1})"
	MACHINE_TYPE="$(awk -F "," '{print $3}' <<< ${1})"
	PORT="$(awk -F "," '{print $4}' <<< ${1})"
	SSH_OPTIONS="$(awk -F "," '{print $5}' <<< ${1})"

	# Liveness and connectivity checks
	CheckLivesViaPing ${IP} || return 1
	case "${MACHINE_TYPE}" in
		domain|stanalone)
			CheckLivesViaWinRM "${HNAME}";;
		linux|vmware)
			CheckLivesViaSSH "${IP}" "${PORT}" "${SSH_OPTIONS}";;
		*)
			return 1
	esac

	CheckInsideHostsFile "${IP}" "${HNAME}" || AddHostsFile "${IP}" "${HNAME}"
	
	case "${MACHINE_TYPE}" in
		domain)
			ACCESS="${ACCESS_DOMAIN}"
			test -f "${ACCESS}" || CreateNTLMAccessFile "${ACCESS}" "${DC_USER}" "${DC_PASS}"
			AddToList "${HNAME}" "${ACCESS}"
			;;
		standalone)
			ACCESS="${ACCESS_STANDALONE}"
			test -f "${ACCESS}" || CreateNTLMAccessFile "${ACCESS}" "${STANDALONE_USER}" "${STANDALONE_PASS}"
			AddToList "${HNAME}" "${ACCESS}"
			;;
		*)
			;;
	esac
}

function StartAudit()
{
	case "${MACHINE_TYPE}" in
		domain|standalone)
			StartWindowsAudit "${HNAME}" "${MACHINE_TYPE}" &
			KeepProcessID "${HNAME}" "${!}"
			;;
		linux)
			StartLinuxAudit "${IP}" &
			KeepProcessID "${HNAME}" "${!}"
			;;
		vmware)
			StartVMWareAudit "${IP}" &
			KeepProcessID "${HNAME}" "${!}"
			;;
	esac
}

function StartWindowsAudit()
{
	# We trigger the commands to run on the machine from this function.


	# To clear the PID register when the function is finished.
	DeleteProcessID "${HNAME}"
}

function StartLinuxAudit()
{
	# We trigger the commands to run on the machine from this function.


	# To clear the PID register when the function is finished.
	DeleteProcessID "${HNAME}"
}

function StartVMWareAudit()
{
	# We trigger the commands to run on the machine from this function.


	# To clear the PID register when the function is finished.
	DeleteProcessID "${HNAME}"
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
	rm -rf "${DATA_DIR}" "${ACCESS_DOMAIN}" "${ACCESS_STANDALONE}"
	mkdir -p "${DATA_DIR}"
	T=1

	while [ ${T} -le ${MACHINE_NUMBER} ]
	do
		Preliminary "$(FetchFromMachineList ${T})" || [[ T=$((T+1)) && continue ]]
		StartAudit
		T=$((T+1))
	done
	
	WaitForProcessesToFinish
}

MainProcess
