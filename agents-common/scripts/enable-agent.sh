#!/bin/bash

#
# Base env variable for ARGUS related files/directories
#

PROJ_NAME=argus
BASE_CONF_DIR=/etc/${PROJ_NAME}

#
# Identify the component, action from the script file
#


basedir=`dirname $0`
if [ "${basedir}" = "." ]
then
    basedir=`pwd`
elif [ "${basedir}" = ".." ]
then
    basedir=`(cd .. ;pwd)`
fi

#
# As this script is common to all component, find the component name based on the script-name
#

COMPONENT_NAME=`basename $0 | cut -d. -f1 | sed -e 's:^disable-::' | sed -e 's:^enable-::'`

echo "${COMPONENT_NAME}" | grep 'agent' > /dev/null 2>&1

if [ $? -ne 0 ]
then
	echo "$0 : is not applicable for component [${COMPONENT_NAME}]. It is applicable only for argus agent component; Exiting ..."
	exit 0 
fi

HCOMPONENT_NAME=`echo ${COMPONENT_NAME} | sed -e 's:-agent::'`

CFG_OWNER_INF="${HCOMPONENT_NAME}:hadoop"

if [ "${HCOMPONENT_NAME}" = "hdfs" ]
then
	HCOMPONENT_NAME="hadoop"
fi

#
# Based on script name, identify if the action is enabled or disabled
#

basename $0 | cut -d. -f1 | grep '^enable-' > /dev/null 2>&1

if [ $? -eq 0 ]
then
	action=enable
else
	action=disable
fi


#
# environment variables for enable|disable scripts 
#

PROJ_INSTALL_DIR=`(cd ${basedir} ; pwd)`
SET_ENV_SCRIPT_NAME=set-${COMPONENT_NAME}-env.sh
SET_ENV_SCRIPT_TEMPLATE=${PROJ_INSTALL_DIR}/install/conf.templates/enable/${SET_ENV_SCRIPT_NAME}
DEFAULT_XML_CONFIG=${PROJ_INSTALL_DIR}/install/conf.templates/default/configuration.xml
PROJ_LIB_DIR=${PROJ_INSTALL_DIR}/lib
PROJ_INSTALL_LIB_DIR="${PROJ_INSTALL_DIR}/install/lib"
INSTALL_ARGS="${PROJ_INSTALL_DIR}/install.properties"
JAVA=java

hdir=${PROJ_INSTALL_DIR}/../../${HCOMPONENT_NAME}

#
# TEST - START
#
if [ ! -d ${hdir} ]
then
	mkdir -p ${hdir}
fi
#
# TEST - END
#
HCOMPONENT_INSTALL_DIR=`(cd ${hdir} ; pwd)`
HCOMPONENT_LIB_DIR=${HCOMPONENT_INSTALL_DIR}/lib
if [ "${HCOMPONENT_NAME}" = "knox" ]
then
	HCOMPONENT_LIB_DIR=${HCOMPONENT_INSTALL_DIR}/ext
fi
HCOMPONENT_CONF_DIR=${HCOMPONENT_INSTALL_DIR}/conf
HCOMPONENT_ARCHIVE_CONF_DIR=${HCOMPONENT_CONF_DIR}/.archive
SET_ENV_SCRIPT=${HCOMPONENT_CONF_DIR}/${SET_ENV_SCRIPT_NAME}


if [ ! -d "${HCOMPONENT_INSTALL_DIR}" ]
then
	echo "ERROR: Unable to find the install directory of component [${HCOMPONENT_NAME}]; dir [${HCOMPONENT_INSTALL_DIR}] not found."
	echo "Exiting installation."
	exit 1
fi

if [ ! -d "${HCOMPONENT_CONF_DIR}" ]
then
	echo "ERROR: Unable to find the conf directory of component [${HCOMPONENT_NAME}]; dir [${HCOMPONENT_CONF_DIR}] not found."
	echo "Exiting installation."
	exit 1
fi

if [ ! -d "${HCOMPONENT_LIB_DIR}" ]
then
	echo "ERROR: Unable to find the lib directory of component [${HCOMPONENT_NAME}];  dir [${HCOMPONENT_LIB_DIR}] not found."
	echo "Exiting installation."
	exit 1
fi

#
# Common functions used by all enable/disable scripts
#

log() {
	echo "+ `date` : $*"
}


create_jceks() {

	alias=$1
	pass=$2
	jceksFile=$3

	if [ -f "${jceksFile}" ]
	then
		jcebdir=`dirname ${jceksFile}`
		jcebname=`basename ${jceksFile}`
		archive_jce=${jcebdir}/.${jcebname}.`date '+%Y%m%d%H%M%S'`
		log "Saving current JCE file: ${jceksFile} to ${archive_jce} ..."
		cp ${jceksFile} ${archive_jce}
	fi

	tempFile=/tmp/jce.$$.out

    java -cp ":${PROJ_INSTALL_LIB_DIR}/*:" com.hortonworks.credentialapi.buildks create "${alias}" -value "${pass}" -provider "jceks://file${jceksFile}" > ${tempFile} 2>&1

	if [ $? -ne 0 ]
	then
		echo "Unable to store password in non-plain text format. Error: [`cat ${tempFile}`]"
		echo "Exiting agent installation"
		rm -f ${tempFile}
		exit 0
	fi
	
	rm -f ${tempFile}
}

#
# If there is a set-argus-${COMPONENT}-env.sh, install it
#
dt=`date '+%Y%m%d-%H%M%S'`

if [ -f "${SET_ENV_SCRIPT_TEMPLATE}" ]
then
	#
	# If the setenv script already exists, move it to the archive folder
	#
	if [ -f "${SET_ENV_SCRIPT}" ]
	then
		if [ ! -d "${HCOMPONENT_ARCHIVE_CONF_DIR}" ]
		then
			mkdir -p ${HCOMPONENT_ARCHIVE_CONF_DIR}
		fi
		log "Saving current ${SET_ENV_SCRIPT_NAME} to ${HCOMPONENT_ARCHIVE_CONF_DIR} ..."
		mv ${SET_ENV_SCRIPT} ${HCOMPONENT_ARCHIVE_CONF_DIR}/${SET_ENV_SCRIPT_NAME}.${dt}
	fi
	
	if [ "${action}" = "enable" ]
	then
		cp ${SET_ENV_SCRIPT_TEMPLATE} ${SET_ENV_SCRIPT}
		if [ -f ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh ]
		then

			grep 'xasecure-.*-env.sh' ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh > /dev/null 2>&1
			if [ $? -eq 0 ]
			then
				ts=`date '+%Y%m%d%H%M%S'`
				grep -v 'xasecure-.*-env.sh' ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh > ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh.${ts} 
				if [ $? -eq 0 ]
				then
					log "Removing old reference to xasecure setenv source ..."
					cat ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh.${ts} > ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh
					rm -f ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh.${ts}
				fi
			fi

			grep "[ \t]*.[ \t]*${SET_ENV_SCRIPT}" ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh  > /dev/null
			if [ $? -ne 0 ]
			then
				log "Appending sourcing script, ${SET_ENV_SCRIPT_NAME} in the file: ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh "
				cat >> ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh <<!
if [ -f ${SET_ENV_SCRIPT} ]
then
	.  ${SET_ENV_SCRIPT}
fi
!
			else
				log "INFO: ${SET_ENV_SCRIPT_NAME} is being sourced from file: ${HCOMPONENT_CONF_DIR}/${HCOMPONENT_NAME}-env.sh "
			fi
		fi
	fi
fi

#
# Run, the enable|disable ${COMPONENT} configurations 
#

if [ -d "${PROJ_INSTALL_DIR}/install/conf.templates/${action}" ]
then


	INSTALL_CP="${PROJ_INSTALL_LIB_DIR}/*" 
	if [ "${action}" = "enable" ]
	then
		for cf in ${PROJ_INSTALL_DIR}/install/conf.templates/${action}/*.xml
		do
			cfb=`basename ${cf}`
			if [ -f "${HCOMPONENT_CONF_DIR}/${cfb}" ]
			then
				log "Saving ${HCOMPONENT_CONF_DIR}/${cfb} to ${HCOMPONENT_CONF_DIR}/.${cfb}.${dt} ..."
				cp ${HCOMPONENT_CONF_DIR}/${cfb} ${HCOMPONENT_CONF_DIR}/.${cfb}.${dt}
			fi
			cp ${cf} ${HCOMPONENT_CONF_DIR}/
			chown ${CFG_OWNER_INF} ${HCOMPONENT_CONF_DIR}/${cfb}
		done
	fi

	for f in ${PROJ_INSTALL_DIR}/install/conf.templates/${action}/*.cfg
	do
		if [ -f "${f}" ]
		then
			fn=`basename $f`
        	orgfn=`echo $fn | sed -e 's:-changes.cfg:.xml:'`
        	fullpathorgfn="${HCOMPONENT_CONF_DIR}/${orgfn}"
        	if [ ! -f ${fullpathorgfn} ]
        	then
				if [ -f ${DEFAULT_XML_CONFIG} ]
				then
					log "Creating default file from [${DEFAULT_XML_CONFIG}] for [${fullpathorgfn}] .."
					cp ${DEFAULT_XML_CONFIG} ${fullpathorgfn}
				else
        			echo "ERROR: Unable to find ${fullpathorgfn}"
        			exit 1
				fi
        	fi
			archivefn="${HCOMPONENT_CONF_DIR}/.${orgfn}.${dt}"
        	newfn="${HCOMPONENT_CONF_DIR}/.${orgfn}-new.${dt}"
			log "Saving current config file: ${fullpathorgfn} to ${archivefn} ..."
            cp ${fullpathorgfn} ${archivefn}
			if [ $? -eq 0 ]
			then
				${JAVA} -cp "${INSTALL_CP}" com.xasecure.utils.install.XmlConfigChanger -i ${archivefn} -o ${newfn} -c ${f} -p  ${INSTALL_ARGS}
				if [ $? -eq 0 ]
                then
                	diff -w ${newfn} ${fullpathorgfn} > /dev/null 2>&1
                    if [ $? -ne 0 ]
                    then
                    	cp ${newfn} ${fullpathorgfn}
                    fi
               	else
				    echo "ERROR: Unable to make changes to config. file: ${fullpathorgfn}"
                    echo "exiting ...."
                    exit 1
				fi
			else
				echo "ERROR: Unable to save config. file: ${fullpathorgfn}  to ${archivefn}"
                echo "exiting ...."
                exit 1
			fi
		fi
	done
fi

#
# Create library link
#

if [ "${action}" = "enable" ]
then

	if [ -d "${PROJ_LIB_DIR}" ]
	then
		dt=`date '+%Y%m%d%H%M%S'`
		dbJar=`grep '^SQL_CONNECTOR_JAR' ${INSTALL_ARGS} | awk -F= '{ print $2 }'`
		for f in ${PROJ_LIB_DIR}/*.jar ${dbJar}
		do
			if [ -f "${f}" ]
			then	
				bn=`basename $f`
				if [ -f ${HCOMPONENT_LIB_DIR}/${bn} ]
				then
					log "Saving lib file: ${HCOMPONENT_LIB_DIR}/${bn} to ${HCOMPONENT_LIB_DIR}/.${bn}.${dt} ..."
					mv ${HCOMPONENT_LIB_DIR}/${bn} ${HCOMPONENT_LIB_DIR}/.${bn}.${dt}
				fi
				if [ ! -f ${HCOMPONENT_LIB_DIR}/${bn} ]
				then
					ln -s ${f} ${HCOMPONENT_LIB_DIR}/${bn}
				fi
			fi
		done
	fi

	#
	# Encrypt the password and keep it secure in Credential Provider API
	#
	
	CredFile=`grep '^CREDENTIAL_PROVIDER_FILE' ${INSTALL_ARGS} | awk -F= '{ print $2 }'`
	
	if ! [ `echo ${CredFile} | grep '^/.*'` ]
	then
  	echo "ERROR:Please enter the Credential File Store with proper file path"
  	exit 1
	fi
	
	pardir=`dirname ${CredFile}`
	
	if [ ! -d "${pardir}" ]
	then
		mkdir -p "${pardir}" 
	
		if [ $? -ne 0 ]
		then
    		echo "ERROR: Unable to create credential store file path"
			exit 1
		fi
		chmod go+rx "${pardir}"
	fi

	#
	# Generate Credential Provider file and Credential for Audit DB access.
	#
	
	
	auditCredAlias="auditDBCred"
	
	auditdbCred=`grep '^XAAUDIT.DB.PASSWORD' ${INSTALL_ARGS} | awk -F= '{ print $2 }'`
	
	create_jceks "${auditCredAlias}"  "${auditdbCred}"  "${CredFile}"
	
	
	#
	# Generate Credential Provider file and Credential for SSL KEYSTORE AND TRUSTSTORE
	#
	
	
	sslkeystoreAlias="sslKeyStore"
	
	sslkeystoreCred=`grep '^SSL_KEYSTORE_PASSWORD' ${INSTALL_ARGS} | awk -F= '{ print $2 }'`
	
	create_jceks "${sslkeystoreAlias}" "${sslkeystoreCred}" "${CredFile}"
	
	
	ssltruststoreAlias="sslTrustStore"
	
	ssltruststoreCred=`grep '^SSL_TRUSTSTORE_PASSWORD' ${INSTALL_ARGS} | awk -F= '{ print $2 }'`
	
	create_jceks "${ssltruststoreAlias}" "${ssltruststoreCred}" "${CredFile}"
	
	chown ${CFG_OWNER_INF} ${CredFile}
	
fi

#
# Knox specific configuration
#
#

if [ "${HCOMPONENT_NAME}" = "knox" ]
then
	if [ "${action}" = "enable" ]
	then
		authFrom="AclsAuthz"
		authTo="XASecurePDPKnox"
	else
		authTo="AclsAuthz"
		authFrom="XASecurePDPKnox"
	fi

	dt=`date '+%Y%m%d%H%M%S'`
	for fn in `ls ${HCOMPONENT_CONF_DIR}/topologies/*.xml 2> /dev/null`
	do
  		if [ -f "${fn}" ]
  		then
    		dn=`dirname ${fn}`
    		bn=`basename ${fn}`
    		bf=${dn}/.${bn}.${dt}
    		echo "backup of ${fn} to ${bf} ..."
    		cp ${fn} ${bf}
    		echo "Updating topology file: [${fn}] ... " 
    		cat ${fn} | sed -e "s-<name>${authFrom}</name>-<name>${authTo}</name>-" > ${fn}.${dt}.new
    		if [ $? -eq 0 ]
    		then
        		cat ${fn}.${dt}.new > ${fn}
        		rm ${fn}.${dt}.new
    		fi 
  		fi
	done
fi


#
# Set notice to restart the ${HCOMPONENT_NAME}
#

echo "ARGUS Plugin for ${HCOMPONENT_NAME} has been ${action}d. Please restart ${HCOMPONENT_NAME} to ensure that changes are effective."

exit 0