
#!/bin/bash

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

###############		function for admin tasks

admin() 
	mkdir "$1"
	cp "$2" "$1"
	cp "$3" "$1"
	cp "$4" "$1"
}


###############         Now we'll have a look at the content of the directories #####################

#http://moinne.com/blog/ronald/bash/list-directory-names-in-bash-shell
#--time-style is used here to ensure awk $8 will return the right thing (dir name)

SAMPLES=$(ls -l --time-style="long-iso" ${TODO_DIR} | egrep '^d' | awk '{print $8}')
for SAMPLE in ${SAMPLES}
do
	#VCF=(ls -l --time-style="long-iso" ${TODO_DIR}/${SAMPLE}  | egrep '^-'  | awk '{print $8}' | egrep '*.vcf')
	LOG_FILE="${TODO_DIR}/${SAMPLE}/autoAchab.log"
	touch ${LOG_FILE}
	echo ""
	info "Launching captainAchab workflow for ${SAMPLE}, to follow check:"
	info "tail -f ${LOG_FILE}"
	${NOHUP} ${SH} ${CWW} -e "${CROMWELL_JAR}" -o "${OPTIONS_JSON}" -c "${CROMWELL_CONF}" -w "${CAPTAINACHAB_WDL}" -i "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" >${LOG_FILE} 2>&1
	if [ "$?" -eq 0 ];then
		admin "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin" "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" "${TODO_DIR}/${SAMPLE}/disease.txt" "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin" "${LOG_FILE}"
		#mkdir "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin"
		#cp "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin"
		#cp "${TODO_DIR}/${SAMPLE}/disease.txt" "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin"
		#cp "${LOG_FILE}" "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin"
		#put rm here
		rm -r "${TODO_DIR}/${SAMPLE}"
		info "Genuine Job finished for ${SAMPLE}"
	else
		#relaunch in nodb no cache mode
		warning "First attempt failed, relaunching ${SAMPLE} in nodb, nocache mode"
		info "to follow, check:"
		info "tail -f ${LOG_FILE}"
		${NOHUP} ${SH} ${CWW} -e "${CROMWELL_JAR}" -o "${OPTIONS_JSON}" -c "${CROMWELL_CONF_NODB_NOCACHE}" -w "${CAPTAINACHAB_WDL}" -i "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json"  >>${LOG_FILE} 2>&1
		if [ "$?" -eq 0 ];then
			admin "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin" "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" "${TODO_DIR}/${SAMPLE}/disease.txt" "${DONE_DIR}/${SAMPLE}/CaptainAchab/admin" "${LOG_FILE}"
			#put rm here
			rm -r "${TODO_DIR}/${SAMPLE}"
			info "Relaunched Job finished for ${SAMPLE}"
		else
			mv "${TODO_DIR}/${SAMPLE}" "${ERROR_DIR}"
			error "${SAMPLE} was not treated correctly - Please contact an Admin to check log file at ${ERROR_DIR}/${SAMPLE}/autoAchab.log"
			exit 1
		fi
	fi
done
