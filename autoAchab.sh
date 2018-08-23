
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


###############		Get options from conf file			##################################

CONFIG_FILE='/home/neuro_admin/autoAchab/autoAchab.conf'

#we check params against regexp

UNKNOWN=$(cat  ${CONFIG_FILE} | grep -Evi "^(#.*|[A-Z0-9_]*=[a-z0-9_ \.\/\$\{\}]*)$")
if [ -n "${UNKNOWN}" ]; then
	echo "Error in config file. Not allowed lines:"
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

###############         Now we'll have a look at the content of the directories #####################

#http://moinne.com/blog/ronald/bash/list-directory-names-in-bash-shell
#--time-style is used here to ensure awk $8 will return the right thing (dir name)

SAMPLES=$(ls -l --time-style="long-iso" ${TODO_DIR} | egrep '^d' | awk '{print $8}')
for SAMPLE in ${SAMPLES}
do
	#VCF=(ls -l --time-style="long-iso" ${TODO_DIR}/${SAMPLE}  | egrep '^-'  | awk '{print $8}' | egrep '*.vcf')
	echo "[`date +'%Y-%m-%d %H:%M:%S'`] - Launching captainAchab workflow for ${SAMPLE}"
	${NOHUP} ${SH} ${CWW} -e "${CROMWELL_JAR}" -o "${OPTIONS_JSON}" -c "${CROMWELL_CONF}" -w "${CAPTAINACHAB_WDL}" -i "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json"
	if [ "$?" -eq 0 ];then
		cp "${TODO_DIR}/${SAMPLE}/captainAchab_inputs.json" "${DONE_DIR}/${SAMPLE}/CaptainAchab/"
		#put rm here
		rm -r "${TODO_DIR}/${SAMPLE}"
		echo "[`date +'%Y-%m-%d %H:%M:%S'`] -  Job finished for ${SAMPLE}"
	else
		echo "[`date +'%Y-%m-%d %H:%M:%S'`] - Error with ${SAMPLE}" 
	fi
done
