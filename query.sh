#!/bin/bash

IP_LIST="/root/ip-liste"
ACCESS_FILE="/root/erisim-domain"
WORK_DIR="/var/lib/taliaoppy/workdir"

STR_SUCCESS="Success"
STR_ERROR="ERROR"



function CPUUsage()
{
	cat <(grep 'cpu ' /proc/stat) <(sleep 1 && grep 'cpu ' /proc/stat) | awk -v RS="" '{printf "%.0f\n", ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5)}'
}

function MemoryInfo()
{
	case ${1} in
		Total|total|TOTAL)
			awk '/MemTotal/ {print int($2*0.1)}' /proc/meminfo;;
		Available|available|AVAILABLE)
			awk '/MemAvailable/ {print $2}' /proc/meminfo;;
	esac
}

function WaitIfSystemResourceIsInsufficient()
{
	while true
	do
		if [ $(MemoryInfo Available) -gt $(MemoryInfo Total) -a $(CPUUsage) -lt 90 ]
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

function ScanMachine()
{
	test -z ${MACHINE} && continue
	rm -rf "${WORK_DIR}/${MACHINE}"
	mkdir -p "${WORK_DIR}/${MACHINE}"
	ansible "${MACHINE}" -T 2 -m win_shell -a 'whoami;hostname;(Get-WmiObject win32_operatingsystem).caption;systeminfo | findstr "Domain";echo $PSVersionTable' -i "${ACCESS_FILE}" > "${WORK_DIR}/${MACHINE}/output"
	if [ ${?} == 0 ]
	then
		mv "${WORK_DIR}/${MACHINE}/output" "${WORK_DIR}/${MACHINE}/success"
		ColorEcho "GREEN" "${MACHINE}\t${STR_SUCCESS}"
	else
		mv "${WORK_DIR}/${MACHINE}/output" "${WORK_DIR}/${MACHINE}/error"
		ColorEcho "RED" "${MACHINE}\t${STR_ERROR}"
	fi
}

for MACHINE in $(cat "${IP_LIST}")
do
	WaitIfSystemResourceIsInsufficient
	ScanMachine &
done
