#! /bin/bash

###########################################################################
#########														###########
#########		AutoAchabParall									###########
######### @uthor : D Baux	david.baux<at>chu-montpellier.fr	###########
######### Date : 22/07/2025										###########
#########														###########
###########################################################################

###########################################################################
###########
########### 	Script to automate captainAchab WDL workflow
########### 	to annotate VCFs
###########		see https://github.com/mobidic/MobiDL
###########
###########################################################################


####	This script is meant to be croned
####	must check the Todo directory
####	and launch captainAchab
####	This version treats all folders in parallel
####	therefore be careful
####	either use a job scheduler with cromwell or singularity
####	or ensure you won't break your server with too many samples

##############		If any option is given, print help message	##################################
VERSION=20260321
usage() {
	echo 'This script automates MobiDL captainAchab workflows.'
	echo 'Program: AutoAchabparall'
	echo 'Version: ${VERSION}'
	echo 'Contact: Baux David <david.baux@chu-montpellier.fr>'
	echo 'Usage : bash AutoAchabparall.sh --config <path to conf file> [-v 4]'
	echo '	Mandatory arguments :'
	echo '		* -c|--config		<path to conf file>: default: ./autoDL.conf'
	echo '	Optional arguments :'
	echo '		* -v | --verbosity	<integer> : decrease or increase verbosity level (ERROR : 1 | WARNING : 2 | INFO : 3 (default) | DEBUG : 5)'
	echo '	General arguments :'
	echo '		* -h: 			show this help message and exit'
	echo ''
	exit
}
# USAGE="
# Program: AutoAchabParall
# Version: ${VERSION}
# Contact: Baux David <david.baux@chu-montpellier.fr>

# Usage: This script is meant to be croned
# 	Should be executed once per minute
# "

# if [ $# -ne 0 ]; then
# 	echo "${USAGE}"
# 	echo "Error Message : Arguments provided"
# 	echo ""
# 	exit 1
# fi

RED='\033[0;31m'
LIGHTRED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
# -- Script log

VERBOSITY=3
# -- Log variables

ERROR=1
WARNING=2
INFO=3
DEBUG=4
# -- Log functions got from cww.sh -- simplified here

error() { log "${ERROR}" "[${RED}error${NC}]" "$1" ; }
warning() { log "${WARNING}" "[${YELLOW}warn${NC}]" "$1" ; }
info() { log "${INFO}" "[${BLUE}info${NC}]" "$1" ; }
debug() { log "${DEBUG}" "[${LIGHTRED}debug${NC}]" "$1" ; }


###############		Get options from conf file			##################################
# CONFIG_FILE='/bioinfo/softs/MobiDL_conf/autoAchabParall.conf'
ONCFIG_FILE='./autoAchabParall.conf'

###############		Parse command line			##################################
while [ "$1" != "" ];do
	case $1 in
		-c | --config)	shift
			CONFIG_FILE=$1			
			;;
		-v | --verbosity) shift 
			# Check if verbosity level argument is an integer before assignment 
			if ! [[ "$1" =~ ^[0-9]+$ ]]
			then 
				error "\"$1\" must be an integer !"
				echo " "
				usage 
			else 
				VERBOSITY=$1
			fi 
			;;
		-h | --help)	usage
			exit
			;;
		* )	usage
			exit 1
	esac
	shift
done

if [ ! -f "${CONFIG_FILE}" ]; then
    error "Config file ${CONFIG_FILE} not found!"
fi

# we check the params against a regexp
UNKNOWN=$(cat  ${CONFIG_FILE} | grep -Evi "^(#.*|[A-Z0-9_]*=[a-z0-9_ \.\/\$\{\}-]*)$")
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

debug "CONFIG FILE: ${CONFIG_FILE}"

###############		functions for admin tasks

admin() {
	#if sample_dir ne json sampleid
	# SAMPLE_OUT=$(awk -F"[ ,\"]" '/captainAchab.sampleID/{print $7}' "$4")
	# ADMIN_DIR="${DONE_DIR}/${SAMPLE_OUT}/$1"
	ADMIN_DIR="${DONE_DIR}/$1"
	mkdir -p "${ADMIN_DIR}"
	"${RSYNC}" -az --no-g --chmod=ugo=rwX --exclude '*.vcf' "$2" "${ADMIN_DIR}"
	chmod -R 777 "${DONE_DIR}/$3"
}

success() {
	# success exit code - selfexpl - (Genuine|Relaunched) - ${SAMPLE} - selfexpl
	if [ "$1" -eq 0 ];then
		info "$3 Job finished for $4"
		admin "$2" "${TODO_DIR}/${SAMPLE}/" "$4" "$5"
		exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1
		rm -rf "${TODO_DIR}/$4"
		# weirdly sometimes the dir remains from Cluster
		if [ -d "${TODO_DIR}/$4" ]; then
			rmdir "${TODO_DIR}/$4"
		fi

	else
		error "$4 was not treated correctly - Please contact an Admin to check log file at ${ERROR_DIR}/$4/autoAchab.log"
		"${RSYNC}" -az --no-g --chmod=ugo=rwX  "${TODO_DIR}/$4" "${ERROR_DIR}"
		exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1
		if [ "$?" -eq 0 ];then
			rm -rf "${TODO_DIR}/$4"
			# weirdly sometimes the dir remains from Cluster
			if [ -d "${TODO_DIR}/$4" ]; then
				rmdir "${TODO_DIR}/$4"
			fi
		fi
		"${RSYNC}" -az --no-g --chmod=ugo=rwX  "${DONE_DIR}/$4" "${ERROR_DIR}/$4"
		chmod -R 777 "${ERROR_DIR}/$4"
		rm -rf "${DONE_DIR}/$4"
		# weirdly sometimes the dir remains from Cluster
		if [ -d "${DONE_DIR}/$4" ]; then
			rmdir "${DONE_DIR}/$4"
		fi
		exit 1
	fi
}

launch() {
	# launch $SAMPLE - conf - $LOG_FILE - (Genuine|Relaunched)
	if [ "${ACHABILARITY}" -eq 0 ];then
		# we activate the default gatkEnv here
		source "${CONDABIN}activate" "${GATK_ENV}"
		"${NOHUP}" "${CWW}" -e "${CROMWELL_JAR}" -o "${OPTIONS_JSON}" -c "$2" -w "${CAPTAINACHAB_WDL}" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		# success "$?" "CaptainAchab/admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
		success "$?" "admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
		conda deactivate
		# success exit code - selfexpl - (Genuine|Relaunched) - ${SAMPLE} - selfexpl
	else
		"${SINGULARITY}" run -B "${ANNOVAR_PATH}:/media" -B "${DATA_MOUNT_POINT}:/mnt" ${ACHABILARITY_SIMG} -o "${OPTIONS_JSON}" -c "$2" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		# success "$?" "CaptainAchab/admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
		success "$?" "admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
	fi
}

treat_sample() {
	# ${SAMPLE}
	##############		log file

	LOG_FILE="${TODO_DIR}/${SAMPLE}/autoAchab.log"
	touch ${LOG_FILE}
	exec 1>>${LOG_FILE} 2>&1
	VCF=$(ls -l --time-style="long-iso" "${TODO_DIR}/${SAMPLE}" | egrep '^-' | awk '{print $8}' | egrep '*.vcf')
	if [ -f "${TODO_DIR}/${SAMPLE}/${VCF}" ] && [ -f "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" ] && [ -f "${TODO_DIR}/${SAMPLE}/disease.txt" ];then
		echo ""
		info "Launching captainAchab workflow for ${SAMPLE}, to follow check:"
		info "tail -f ${LOG_FILE}"
		launch "${SAMPLE}" "${CROMWELL_CONF}" "${LOG_FILE}" "Genuine"
	else
		error "Folder incomplete or error in file names for sample ${SAMPLE}"
		${RSYNC} -az --no-g --chmod=ugo=rwX  "${TODO_DIR}/${SAMPLE}" "${ERROR_DIR}"
		if [ "$?" -eq 0 ];then
			exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1
			rm -rf "${TODO_DIR}/${SAMPLE}"
			# weirdly sometimes the dir remains from Cluster
			if [ -d "${TODO_DIR}/${SAMPLE}" ]; then
				rmdir "${TODO_DIR}/${SAMPLE}"
			fi			
		fi
	fi
}


###############         Now we'll have a look at the content of the directories #####################

# http://moinne.com/blog/ronald/bash/list-directory-names-in-bash-shell
# --time-style is used here to ensure awk $8 will return the right thing (dir name)

SAMPLES=$(ls -l --time-style="long-iso" ${TODO_DIR} | egrep '^d' | grep -v 'eaDir' | awk '{print $8}')
# debug "Samples: --${SAMPLES}--"
i=0
if [ "${SAMPLES}" != '' ];then
	for SAMPLE in ${SAMPLES}
	do
		# debug "${SAMPLE}"
		((i=i+1))
		DONE_DIR=$(awk -F"[ ,\"]" '/captainAchab.outDir/{print $7}' "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json")
		if [ $i = 10 ];then
			treat_sample "${SAMPLE}"
			i=0
		else
			treat_sample "${SAMPLE}" &
		fi
	done
fi
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
####	This version treats all folders in parallel
####	therefore be careful
####	either use a job scheduler with cromwell or singularity
####	or ensure you won't break your server with too many samples

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

# -- Log functions got from cww.sh -- simplified here

error() { log "[error]" "$1" ; }
warning() { log "[warn]" "$1" ; }
info() { log "[info]" "$1" ; }
debug() { log "[debug]" "$1" ; }

# -- Print log 

echoerr() { echo -e "$@" 1>&2 ; }

log() {
	echoerr "[`date +'%Y-%m-%d %H:%M:%S'`] $1 - autoAchab version : ${VERSION} - $2"
}



###############		Get options from conf file			##################################

CONFIG_FILE='./autoAchabParall.conf'

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
	#if sample_dir ne json sampleid
	SAMPLE_OUT=$(awk -F"[ ,\"]" '/captainAchab.sampleID/{print $7}' "$4")
	ADMIN_DIR="${DONE_DIR}/${SAMPLE_OUT}/$1"
	mkdir "${ADMIN_DIR}"
	"${RSYNC}" -az --exclude '*.vcf' "$2" "${ADMIN_DIR}" 
	#cp "$2" "${ADMIN_DIR}"
	#cp "$3" "${ADMIN_DIR}"
	#cp "$4" "${ADMIN_DIR}"
	#rm -r "${DONE_DIR}/${SAMPLE_OUT}/CaptainAchab/disease/"
	chmod -R 777 "${DONE_DIR}/$3"
}

success() {
	#OLDOLDOLDOLDsuccess exit code -"${DONE_DIR}/$1/CaptainAchab/admin" - "${TODO_DIR}/$1/captainAchab_inputs.json" - "${TODO_DIR}/$1/disease.txt" - ${LOG_FILE} - (Genuine|Relaunched) - ${SAMPLE}
	#success exit code -"${DONE_DIR}/$1/CaptainAchab/admin" - (Genuine|Relaunched) - ${SAMPLE}
	if [ "$1" -eq 0 ];then
		info "$3 Job finished for $4"
		#admin "$2" "$3" "$4" "$5" "$7"
		admin "$2" "${TODO_DIR}/${SAMPLE}/" "$4" "$5"
		#admin "CaptainAchab/admin" "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" "${TODO_DIR}/${SAMPLE}/disease.txt" "${LOG_FILE}" "${SAMPLE}"
		exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1 
		rm -rf "${TODO_DIR}/$4"
	else
		error "$4 was not treated correctly - Please contact an Admin to check log file at ${ERROR_DIR}/$4/autoAchab.log"
		"${RSYNC}" -az "${TODO_DIR}/$4" "${ERROR_DIR}"
		exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1 
		if [ "$?" -eq 0 ];then
			rm -rf "${TODO_DIR}/$4"
		fi
		"${RSYNC}" -az "${DONE_DIR}/$4" "${ERROR_DIR}/$4"
		chmod -R 777 "${ERROR_DIR}/$4"
		rm -rf "${DONE_DIR}/$4"
		exit 1
	fi
}

launch() {
	#launch $SAMPLE - conf - $LOG_FILE - (Genuine|Relaunched)
	if [ "${ACHABILARITY}" -eq 0 ];then
		"${NOHUP}" "${SH}" "${CWW}" -e "${CROMWELL_JAR}" -o "${OPTIONS_JSON}" -c "$2" -w "${CAPTAINACHAB_WDL}" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		#success "$?" "CaptainAchab/admin" "${TODO_DIR}/$1/captainAchab_inputs.json" "${TODO_DIR}/$1/disease.txt" "$3" "$4" "$1"
		#success exit code - selfexpl - selfexpl - selfexpl - ${LOG_FILE} - (Genuine|Relaunched) - ${SAMPLE}
		success "$?" "CaptainAchab/admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
		#success exit code - selfexpl - (Genuine|Relaunched) - ${SAMPLE} - selfexpl
	else
		"${NOHUP}" "${SINGULARITY}" run -B "${ANNOVAR_PATH}:/media" -B "${DATA_MOUNT_POINT}:/mnt" ${ACHABILARITY_SIMG} -o "${OPTIONS_JSON}" -c "$2" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		success "$?" "CaptainAchab/admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
	fi
}

treat_sample() {
	#${SAMPLE}
	##############		log file

	LOG_FILE="${TODO_DIR}/${SAMPLE}/autoAchab.log"
	touch ${LOG_FILE}
	#exec &>${LOG_FILE}
	exec 1>>${LOG_FILE} 2>&1
	VCF=$(ls -l --time-style="long-iso" "${TODO_DIR}/${SAMPLE}" | egrep '^-' | awk '{print $8}' | egrep '*.vcf')	
	if [ -f "${TODO_DIR}/${SAMPLE}/${VCF}" ] && [ -f "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" ] && [ -f "${TODO_DIR}/${SAMPLE}/disease.txt" ];then 	
		echo ""
		info "Launching captainAchab workflow for ${SAMPLE}, to follow check:"
		info "tail -f ${LOG_FILE}"
		launch "${SAMPLE}" "${CROMWELL_CONF_NODB_NOCACHE}" "${LOG_FILE}" "Genuine"
	else
		error "Folder incomplete or error in file names for sample ${SAMPLE}"
		#exec 1 >> "${ERROR_DIR}/autoAchabError.log" 2>&1
		#mv "${TODO_DIR}/${SAMPLE}" "${ERROR_DIR}"
		${RSYNC} -az "${TODO_DIR}/${SAMPLE}" "${ERROR_DIR}"
		if [ "$?" -eq 0 ];then
			exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1 
			rm -r "${TODO_DIR}/${SAMPLE}"
		fi
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
		treat_sample "${SAMPLE}" &
		##############		log file

		#LOG_FILE="${TODO_DIR}/${SAMPLE}/autoAchab.log"
		#touch ${LOG_FILE}
		#exec &>${LOG_FILE}
		#VCF=$(ls -l --time-style="long-iso" "${TODO_DIR}/${SAMPLE}" | egrep '^-' | awk '{print $8}' | egrep '*.vcf')	
		#if [ -f "${TODO_DIR}/${SAMPLE}/${VCF}" ] && [ -f "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" ] && [ -f "${TODO_DIR}/${SAMPLE}/disease.txt" ];then 	
		#	echo ""
		#	info "Launching captainAchab workflow for ${SAMPLE}, to follow check:"
		#	info "tail -f ${LOG_FILE}"
		#	launch "${SAMPLE}" "${CROMWELL_CONF}" "${LOG_FILE}" "Genuine"
		#else
		#	error "Folder incomplete or error in file names for sample ${SAMPLE}"
		#	mv "${TODO_DIR}/${SAMPLE}" "${ERROR_DIR}"
		#fi
	done
fi
