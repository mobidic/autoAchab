#! /bin/bash

###########################################################################
#########														###########
#########		AutoAchabParall									###########
######### @uthor : D Baux	david.baux<at>chu-montpellier.fr	###########
######### Date : 22/08/2018										###########
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
VERSION=1.1
USAGE="
Program: AutoAchabParall
Version: ${VERSION}
Contact: Baux David <david.baux@chu-montpellier.fr>

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
CONFIG_FILE='/mnt/Bioinfo/Softs/src/IURC/MobiDL_conf/autoAchabParall.conf'
# CONFIG_FILE='./autoAchabParall.conf'

# we check the params against a regexp
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
	"${RSYNC}" -az --no-g --chmod=ugo=rwX --exclude '*.vcf' "$2" "${ADMIN_DIR}"
	#cp "$2" "${ADMIN_DIR}"
	#cp "$3" "${ADMIN_DIR}"
	#cp "$4" "${ADMIN_DIR}"
	#rm -r "${DONE_DIR}/${SAMPLE_OUT}/CaptainAchab/disease/"
	chmod -R 777 "${DONE_DIR}/$3"
}

success() {
	# success exit code - selfexpl - (Genuine|Relaunched) - ${SAMPLE} - selfexpl
	if [ "$1" -eq 0 ];then
		info "$3 Job finished for $4"
		admin "$2" "${TODO_DIR}/${SAMPLE}/" "$4" "$5"
		exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1
		rm -rf "${TODO_DIR}/$4"
	else
		error "$4 was not treated correctly - Please contact an Admin to check log file at ${ERROR_DIR}/$4/autoAchab.log"
		"${RSYNC}" -az --no-g --chmod=ugo=rwX  "${TODO_DIR}/$4" "${ERROR_DIR}"
		exec 1>>"${ERROR_DIR}/autoAchabError.log" 2>&1
		if [ "$?" -eq 0 ];then
			rm -rf "${TODO_DIR}/$4"
		fi
		"${RSYNC}" -az --no-g --chmod=ugo=rwX  "${DONE_DIR}/$4" "${ERROR_DIR}/$4"
		chmod -R 777 "${ERROR_DIR}/$4"
		rm -rf "${DONE_DIR}/$4"
		exit 1
	fi
}

launch() {
	# launch $SAMPLE - conf - $LOG_FILE - (Genuine|Relaunched)
	if [ "${ACHABILARITY}" -eq 0 ];then
		# we activate the default gatkEnv here
		source "${CONDABIN}activate" "${GATK_ENV}" 
		"${NOHUP}" "${CWW}" -e "${CROMWELL_JAR}" -o "${OPTIONS_JSON}" -c "$2" -w "${CAPTAINACHAB_WDL}" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		success "$?" "CaptainAchab/admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
		conda deactivate
		# success exit code - selfexpl - (Genuine|Relaunched) - ${SAMPLE} - selfexpl
	else
		"${SINGULARITY}" run -B "${ANNOVAR_PATH}:/media" -B "${DATA_MOUNT_POINT}:/mnt" ${ACHABILARITY_SIMG} -o "${OPTIONS_JSON}" -c "$2" -i "${TODO_DIR}/$1/captainAchab_inputs.json" >>"$3" 2>&1
		success "$?" "CaptainAchab/admin" "$4" "$1" "${TODO_DIR}/$1/captainAchab_inputs.json"
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
		fi
	fi
}


###############         Now we'll have a look at the content of the directories #####################

# http://moinne.com/blog/ronald/bash/list-directory-names-in-bash-shell
# --time-style is used here to ensure awk $8 will return the right thing (dir name)

SAMPLES=$(ls -l --time-style="long-iso" ${TODO_DIR} | egrep '^d' | grep -v 'eaDir' | awk '{print $8}')
# debug "Samples: --${SAMPLES}--"
if [ "${SAMPLES}" != '' ];then
	for SAMPLE in ${SAMPLES}
	do
		# debug "${SAMPLE}"
		DONE_DIR=$(awk -F"[ ,\"]" '/captainAchab.outDir/{print $7}' "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json")
		treat_sample "${SAMPLE}" &
	done
fi
