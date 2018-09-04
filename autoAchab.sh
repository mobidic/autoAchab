#!/bin/sh

###########################################################################
#########							###########
#########		AutoAchab				###########
######### @uthor : D Baux	david.baux<at>inserm.fr		###########
######### Date : 22/08/2018					###########
#########							###########
###########################################################################

###########################################################################
###########
########### 	Script to automate captainAchab WDL workflow
########### 	to annotate VCFs
###########	see https://github.com/mobidic/MobiDL
###########
###########################################################################


####	This script is meant to be croned
####	must check the Todo directory
####	and launch captainAchab


##############		If any option is given, print help message	##################################
VERSION=1.0
USAGE="
Program: AutoAchab
Version: ${VERSION}
Contact: Baux David <david.baux@inserm.fr>

Usage: This script is meant to be croned
	Should be executed once per minute

"


if [ $# -ne 0 ]; then
	echo "${USAGE}"
	echo "Error Message : Arguments provided"
	echo ""
	exit 1
fi

RED='\033[0;31m'
LIGHTRED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -- Log functions got from cww.sh -- simplified here

error() { log "[${RED}error${NC}]" "$1" ; }
warning() { log "[${YELLOW}warn${NC}]" "$1" ; }
info() { log "[${BLUE}info${NC}]" "$1" ; }
debug() { log "[${LIGHTRED}debug${NC}]" "$1" ; }

# -- Print log 

echoerr() { echo -e "$@" 1>&2 ; }

log() {
	echoerr "[`date +'%Y-%m-%d %H:%M:%S'`] $1 - autoAchab version : ${VERSION} - $2"
}



###############		Get options from conf file			##################################

CONFIG_FILE='/home/neuro_admin/autoAchab/autoAchab.conf'

#we check params against regexp

UNKNOWN=$(cat  ${CONFIG_FILE} | grep -Evi "^(#.*|[A-Z0-9_]*=[a-z0-9_ \.\/\$\{\}]*)$")
if [ -n "${UNKNOWN}" ]; then
	error "Error in config file. Not allowed lines:"
	echo ${UNKNOWN}
	exit 1
fi

source ${CONFIG_FILE}

###############		1st check whether another instance of the script is running	##################

RESULT=$(ps x | grep -v grep | grep -c ${SERVICE})
#echo `ps x | grep -v grep |grep ${SERVICE} `
#echo "Result: ${RESULT}"

if [ "${RESULT}" -gt 3 ]; then
	exit 0
fi


###############		functions for admin tasks

admin() { 
	mkdir "$1"
	cp "$2" "$1"
	cp "$3" "$1"
	cp "$4" "$1"
	chmod -R 777 "${DONE_DIR}/$5"
}

success() {
	#success exit code -"${DONE_DIR}/$1/CaptainAchab/admin" - "${TODO_DIR}/$1/captainAchab_inputs.json" - "${TODO_DIR}/$1/disease.txt" - ${LOG_FILE} - (Genuine|Relaunched) - ${SAMPLE}
	if [ "$1" -eq 0 ];then
		info "$6 Job finished for $7"
		admin "$2" "$3" "$4" "$5" "$7"
		#admin "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin" "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" "${TODO_DIR}/${SAMPLE}/disease.txt" "${LOG_FILE}" "${SAMPLE}"
		rm -r "${TODO_DIR}/$7"
	elif [ "$6" == "Genuine" ];then
		warning "First attempt failed, relaunching $7 in nodb, nocache mode"
		info "to follow, check:"
		info "tail -f $5"
		launch "$7" "${CROMWELL_CONF_NODB_NOCACHE}" "$5" "Relaunched"
		#launch $SAMPLE - conf - $LOG_FILE - (Genuine|Relaunched)
	elif [ "$6" == "Relaunched" ];then
		#mv "${TODO_DIR}/$7" "${ERROR_DIR}"
		error "$7 was not treated correctly - Please contact an Admin to check log file at ${ERROR_DIR}/$7/autoAchab.log"
		"${RSYNC}" -az "${TODO_DIR}/$7" "${ERROR_DIR}"
		if [ "$?" -eq 0 ];then
			rm -r "${TODO_DIR}/$7"
		fi
		chmod -R 777 "${ERROR_DIR}/$7"
		rm -r "${DONE_DIR}/$7"
		exit 1
	fi
}

launch() {
	#launch $SAMPLE - conf - $LOG_FILE - (Genuine|Relaunched)
	if [ "${ACHABILARITY}" -eq 0 ];then
		"${NOHUP}" "${SH}" "${CWW}" -e "${CROMWELL_JAR}" -o "${OPTIONS_JSON}" -c "$2" -w "${CAPTAINACHAB_WDL}" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		success "$?" "${DONE_DIR}/$1/CaptainAchab/admin" "${TODO_DIR}/$1/captainAchab_inputs.json" "${TODO_DIR}/$1/disease.txt" "$3" "$4" "$1"
		#success exit code - selfexpl - selfexpl - selfexpl - ${LOG_FILE} - (Genuine|Relaunched) - ${SAMPLE}
	else
		"${NOHUP}" "${SINGULARITY}" run -B "${ANNOVAR_PATH}:/media" -B "${DATA_MOUNT_POINT}:/mnt" ${ACHABILARITY_SIMG} -o "${OPTIONS_JSON}" -c "$2" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		success "$?" "${DONE_DIR}/$1/CaptainAchab/admin" "${TODO_DIR}/$1/captainAchab_inputs.json" "${TODO_DIR}/$1/disease.txt" "$3" "$4" "$1"
	fi
}

###############         Now we'll have a look at the content of the directories #####################

#http://moinne.com/blog/ronald/bash/list-directory-names-in-bash-shell
#--time-style is used here to ensure awk $8 will return the right thing (dir name)

SAMPLES=$(ls -l --time-style="long-iso" ${TODO_DIR} | egrep '^d' | awk '{print $8}')
#debug "Samples: --${SAMPLES}--"
if [ "${SAMPLES}" != '' ];then
	for SAMPLE in ${SAMPLES}
	do
		##############		log file

		LOG_FILE="${TODO_DIR}/${SAMPLE}/autoAchab.log"
		touch ${LOG_FILE}
		exec &>${LOG_FILE}
		VCF=$(ls -l --time-style="long-iso" "${TODO_DIR}/${SAMPLE}" | egrep '^-' | awk '{print $8}' | egrep '*.vcf')	
		if [ -f "${TODO_DIR}/${SAMPLE}/${VCF}" ] && [ -f "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" ] && [ -f "${TODO_DIR}/${SAMPLE}/disease.txt" ];then 	
			echo ""
			info "Launching captainAchab workflow for ${SAMPLE}, to follow check:"
			info "tail -f ${LOG_FILE}"
			launch "${SAMPLE}" "${CROMWELL_CONF}" "${LOG_FILE}" "Genuine"
		else
			error "Folder incomplete or error in file names for sample ${SAMPLE}"
			mv "${TODO_DIR}/${SAMPLE}" "${ERROR_DIR}"
		fi
	done
fi
