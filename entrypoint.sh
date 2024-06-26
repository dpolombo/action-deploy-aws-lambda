#!/bin/bash

add_requirements() {
	if [ -f "requirements.txt" ]; then
		echo "Installing requirements..."
		pip install -r requirements.txt -t .
	fi
}

verb() {
	if ${INPUT_VERBOSE}; then
		echo "$*"
	fi
}

deploy_function() {
	echo "Deploying function ..."
	RETCODE=0
	cd "${INPUT_WORKING_DIRECTORY}" || exit
	add_requirements
	zip -r code.zip . -x \*.git\*
	verb aws lambda create-function --function-name "${INPUT_FUNCTION_NAME}" --runtime "${INPUT_RUNTIME}" \
		--timeout "${INPUT_TIMEOUT}" --memory-size "${INPUT_MEMORY}" --role "${INPUT_ROLE}" \
		--handler "${INPUT_HANDLER}" ${OPT_LAYERS} ${OPT_ENV_VARIABLES} ${OPT_VPC_CONFIG} \
		--zip-file fileb://code.zip
	aws lambda create-function --function-name "${INPUT_FUNCTION_NAME}" --runtime "${INPUT_RUNTIME}" \
		--timeout "${INPUT_TIMEOUT}" --memory-size "${INPUT_MEMORY}" --role "${INPUT_ROLE}" \
		--handler "${INPUT_HANDLER}" ${OPT_LAYERS} ${OPT_ENV_VARIABLES} ${OPT_VPC_CONFIG} \
		--zip-file fileb://code.zip
	RETCODE=$((RETCODE + $?))
	while true; do
		result=$(aws lambda get-function-configuration --function-name "${INPUT_FUNCTION_NAME}" | awk -F'"' '/LastUpdateStatus/ { print $4; }')
		if [ "$result" == "Successful" ]; then
			break
		else
			echo "Waiting for function configuration update to complete ..."
			sleep 2
		fi
	done
	if [ -n "${INPUT_TAGS}" ]; then
		echo "Tagging function..."
		FUNCTION_ARN=$(aws lambda get-function --function-name "${INPUT_FUNCTION_NAME}" | jq -r '.Configuration.FunctionArn')
		verb aws lambda tag-resource --resource "${FUNCTION_ARN}" --tags "${INPUT_TAGS}"
		aws lambda tag-resource --resource "${FUNCTION_ARN}" --tags "${INPUT_TAGS}"
		RETCODE=$((RETCODE + $?))
	fi
	[ $RETCODE -ne 0 ] && echo "ERROR : failed to create the function."
	exit $RETCODE
}

update_function() {
	echo "Updating function ..."
	RETCODE=0
	cd "${INPUT_WORKING_DIRECTORY}" || exit
	add_requirements
	zip -r code.zip . -x \*.git\*
	verb aws lambda update-function-configuration --function-name "${INPUT_FUNCTION_NAME}" --runtime "${INPUT_RUNTIME}" \
		--timeout "${INPUT_TIMEOUT}" --memory-size "${INPUT_MEMORY}" --role "${INPUT_ROLE}" \
		--handler "${INPUT_HANDLER}" ${OPT_LAYERS} ${OPT_ENV_VARIABLES} ${OPT_VPC_CONFIG}
	aws lambda update-function-configuration --function-name "${INPUT_FUNCTION_NAME}" --runtime "${INPUT_RUNTIME}" \
		--timeout "${INPUT_TIMEOUT}" --memory-size "${INPUT_MEMORY}" --role "${INPUT_ROLE}" \
		--handler "${INPUT_HANDLER}" ${OPT_LAYERS} ${OPT_ENV_VARIABLES} ${OPT_VPC_CONFIG}
	RETCODE=$((RETCODE + $?))
	verb "Tags: ${INPUT_TAGS}"
	while true; do
		result=$(aws lambda get-function-configuration --function-name "${INPUT_FUNCTION_NAME}" | awk -F'"' '/LastUpdateStatus/ { print $4; }')
		if [ "$result" == "Successful" ]; then
			break
		else
			echo "Waiting for function configuration update to complete ..."
			sleep 2
		fi
	done
	if [ -n "${INPUT_TAGS}" ]; then
		echo "Tagging function..."
		FUNCTION_ARN=$(aws lambda get-function --function-name "${INPUT_FUNCTION_NAME}" | jq -r '.Configuration.FunctionArn')
		verb aws lambda tag-resource --resource "${FUNCTION_ARN}" --tags "${INPUT_TAGS}"
		aws lambda tag-resource --resource "${FUNCTION_ARN}" --tags "${INPUT_TAGS}"
		RETCODE=$((RETCODE + $?))
	fi
	sleep 2
	verb aws lambda update-function-code --function-name "${INPUT_FUNCTION_NAME}" --zip-file fileb://code.zip
	aws lambda update-function-code --function-name "${INPUT_FUNCTION_NAME}" --zip-file fileb://code.zip
	RETCODE=$((RETCODE + $?))
	[ $RETCODE -ne 0 ] && echo "ERROR : failed to update the function."
	exit $RETCODE
}

deploy_or_update_function() {
	if [ -n "${INPUT_ENV_VARIABLES}" ]; then
		OPT_ENV_VARIABLES="--environment Variables=${INPUT_ENV_VARIABLES}"
	fi
	if [ -n "${INPUT_VPC_CONFIG}" ]; then
		OPT_VPC_CONFIG="--vpc-config ${INPUT_VPC_CONFIG}"
	fi
	if [ -n "${INPUT_LAYERS}" ]; then
		OPT_LAYERS="--layers ${INPUT_LAYERS}"
	fi
	echo "Checking function existence..."
	aws lambda get-function --function-name "${INPUT_FUNCTION_NAME}" &>/dev/null
	if [ $? != 0 ]; then
		echo "Function ${INPUT_FUNCTION_NAME} not found, running initial deployment..."
		deploy_function
	else
		echo "Function found, updating..."
		update_function
	fi
}

show_environment() {
	echo "Function name: ${INPUT_FUNCTION_NAME}"
	echo "Runtime: ${INPUT_RUNTIME}"
	echo "Memory size: ${INPUT_MEMORY}"
	echo "Timeout: ${INPUT_TIMEOUT}"
	echo "IAM role: ${INPUT_ROLE}"
	echo "Lambda handler: ${INPUT_HANDLER}"
	echo "Working directory: ${INPUT_WORKING_DIRECTORY}"
	echo "Environment variables: ${INPUT_ENV_VARIABLES}"
	echo "VPC Config: ${INPUT_VPC_CONFIG}"
	echo "Lambda layers: ${INPUT_LAYERS}"
	echo "Tags: ${INPUT_TAGS}"
	echo "Verbose: ${INPUT_VERBOSE}"
}

echo "dpolombo/action-deploy-aws-lambda@v1.8.1"
aws --version
show_environment
deploy_or_update_function
