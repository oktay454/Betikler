#!/bin/bash

DOMAIN="TEST.LOCAL"
DC_USER="domain.admin"
DC_PASS="Passw0rd!"
STANDALONE_USER="administrator" # Even if it is in the administrator group, there is an authorization problem other than the Administrator user.
STANDALONE_PASS="Passw0rd!"

VAR_DIR="/usr/local/healt-audit"
DATA_DIR="/var/lib/healt-audit"
SSH_KEY="${DATA_DIR}/ssh-key/healt-audit-priv-key"
PSSCRIPS="${VAR_DIR}/psscripts"

#LINUX_LIST="${DATA_DIR}/linux-list"
#VMWARE_LIST="${DATA_DIR}/vmware-list"
#STANDALONE_LIST="${DATA_DIR}/standalone-list"
#DOMAIN_LIST="${DATA_DIR}/domain-list"

ACCESS_DOMAIN="${DATA_DIR}/access-domain"
ACCESS_STANDALONE="${DATA_DIR}/access-standalone"
MACHINE_LIST="${DATA_DIR}/machine-list"

ACTIVE_LIST="/tmp/healt-audit.active"
PROCESS_IDS_LIST="/tmp/healt-audit.ids"
PREFIX_TEMP_DIR="healt-audit"

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
	ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no root@${1} -- "${2}"
}

function CopyFilesViaWinRM()
{
	ansible "${1}" -m win_copy -a "src=${3} dest=${4}" -i ${2}
}

function CopyFilesViaSSH()
{
	test -z ${4} && local SSH_PORT=22
	scp -P ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no root@${1} "${2}" "${3}"
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
	ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o StrictHostKeyChecking=no root@${1} -- whoami 2>&1 > /dev/null

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
	rm -rf "${ACTIVE_LIST}" "${ProcessIDsList}" "/tmp/${PREFIX_TEMP_DIR}.*"
}

function KeepProcessID()
{
	printf "${1},${2}\n" >> "${ProcessIDsList}"
}

function DeleteProcessID()
{
	sed -i "d/${1}$/g" "${ProcessIDsList}"
}

function Preliminary()
{
	# Makine bilgilerini edinme
	IP="$(awk -F "," '{print $1}' <<< ${1})"
	HNAME="$(awk -F "," '{print $2}' <<< ${1})"
	MACHINE_TYPE="$(awk -F "," '{print $3}' <<< ${1})"
	PORT="$(awk -F "," '{print $4}' <<< ${1})"

	# Canlılık ve bağlantı denetimleri
	CheckLivesViaPing ${IP} || return 1
	case "${MACHINE_TYPE}" in
		domain|stanalone)
			CheckLivesViaWinRM "${HNAME}";;
		linux|vmware)
			CheckLivesViaSSH "${IP}" "${PORT}";;
		*)
			return 1
	esac

	CheckInsideHostsFile "${IP}" "${HNAME}" || AddHostsFile "${IP}" "${HNAME}"
	
	case "${MACHINE_TYPE}" in
		domain)
			CreateNTLMAccessFile "${ACCESS_DOMAIN}" "${DC_USER}" "${DC_PASS}"
			AddToList "${HNAME}" "${ACCESS_DOMAIN}"
			ACCESS="${ACCESS_DOMAIN}"
			;;
		standalone)
			CreateNTLMAccessFile "${ACCESS_STANDALONE}" "${STANDALONE_USER}" "${STANDALONE_PASS}"
			AddToList "${HNAME}" "${ACCESS_STANDALONE}"
			ACCESS="${ACCESS_STANDALONE}"
			;;
		*)
			return 1
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
	# Makinede çalışacak komutları bu işlevden tetikliyoruz.
	
	#İşlev bittiğinde PID kaydını silmesi için.
	DeleteProcessID "${HNAME}"
}

function StartLinuxAudit()
{
	# Makinede çalışacak komutları bu işlevden tetikliyoruz.
	
	#İşlev bittiğinde PID kaydını silmesi için.
	DeleteProcessID "${HNAME}"
}

function StartVMWareAudit()
{
	# Makinede çalışacak komutları bu işlevden tetikliyoruz.
	
	#İşlev bittiğinde PID kaydını silmesi için.
	DeleteProcessID "${HNAME}"
}

function WaitForProcessesToFinish()
{
	while true
	do
		test ! -s "${ProcessIDsList}" && break
		sleep 1
	done
}

function MainProcess()
{
	for MACHINE_INFO in $(cat ${MACHINE_LIST})
	do
		Preliminary "${MACHINE_INFO}" || continue
		StartAudit
		WaitForProcessesToFinish
	done
}

MainProcess
