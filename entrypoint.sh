#!/bin/sh

set -e

if [ -z "$INPUT_KUBECONFIG" ]; then
    echo "INPUT_KUBECONFIG is not set. EKS will not be called."
else

if [ -z "$INPUT_AWS_ACCESS_KEY_ID" ]; then
  echo "INPUT_AWS_ACCESS_KEY_ID is not set. Quitting."
  exit 1
else
INPUT_AWS_ACCESS_KEY_ID=$(echo "${INPUT_AWS_ACCESS_KEY_ID}" | xargs)
fi

if [ -z "$INPUT_AWS_SECRET_ACCESS_KEY" ]; then
  echo "INPUT_AWS_SECRET_ACCESS_KEY is not set. Quitting."
  exit 1
else
INPUT_AWS_SECRET_ACCESS_KEY=$(echo "${INPUT_AWS_SECRET_ACCESS_KEY}" | xargs)
fi

# Default to us-east-1 if AWS_REGION not set.
if [ -z "$INPUT_AWS_REGION" ]; then
  AWS_REGION="us-east-2"
fi

if [[ ! $INPUT_NAMESPACE =~ ^[-_a-zA-Z0-9]*$ ]]; then
  echo "No special characters allowed in namespace"
  exit 1
fi

if [ -z "$INPUT_SERVICEACCOUNT" ]; then
    SAARG=""
else
    if [[ ! $INPUT_SERVICEACCOUNT =~ ^[-_a-zA-Z0-9]*$ ]]; then
      echo "No special characters allowed in serviceaccount"
      exit 1
    fi
    SAARG="--serviceaccount ${INPUT_SERVICEACCOUNT}"
fi

if [ ! -z "$INPUT_TASK" ]
then
  if [[ ! $INPUT_TASK =~ ^[-_a-zA-Z0-9]*$ ]]; then
    echo "No special characters allowed in task name"
    exit 1
  fi
  TASKTYPE="task"
else
  if [[ ! $INPUT_CLUSTER_TASK =~ ^[-_a-zA-Z0-9]*$ ]]; then
    echo "No special characters allowed in clustertask name"
    exit 1
  fi
  if [ ! -z "$INPUT_CLUSTER_TASK" ]
  then
    TASKTYPE="clustertask"
    INPUT_TASK=$INPUT_CLUSTER_TASK
  else
    echo "No task defined"
    exit 1
  fi
fi

if [[ ! $INPUT_ARGS =~ ^[-\.=[:space:]\:/a-zA-Z0-9]*$ ]]; then
  echo "No special characters allowed in task arguments"
  exit 1
fi

if [ -z "$INPUT_POD_TEMPLATE" ]; then
    PTARG=""
else
    echo "${INPUT_POD_TEMPLATE}" > /workdir/pod_template.yaml
    PTARG="--pod-template /workdir/pod_template.yaml"
fi

# Create a dedicated profile for this action to avoid conflicts
# with past/future actions.
aws configure --profile github_user <<-EOF > /dev/null 2>&1
${INPUT_AWS_ACCESS_KEY_ID}
${INPUT_AWS_SECRET_ACCESS_KEY}
${INPUT_AWS_REGION}
text
EOF

echo -e "\033[36mSetting up kubectl configuration\033[0m"
mkdir -p ~/.kube/
echo "${INPUT_KUBECONFIG}" > ~/.kube/config

fi

echo -e "\033[36mExecuting tkn\033[0m"
TASKRUN_NAME=$(tkn ${TASKTYPE} start ${PTARG} ${SAARG} -n ${INPUT_NAMESPACE} ${INPUT_TASK} $INPUT_ARGS --output json | jq -r ".metadata | .name")
tkn taskrun logs -f ${TASKRUN_NAME} -n ${INPUT_NAMESPACE}

# confrirm that the run succeeded: https://tekton.dev/docs/pipelines/taskruns/
TASK_STATUS=$(kubectl get tr ${TASKRUN_NAME} -n ${INPUT_NAMESPACE}  -o json | jq -r ".status | .conditions | .[] | .status")
TASK_REASON=$(kubectl get tr ${TASKRUN_NAME} -n ${INPUT_NAMESPACE}  -o json | jq -r ".status | .conditions | .[] | .reason")


if [[ $TASK_STATUS != "True" ]] || [[ $TASK_REASON != "Succeeded" ]]; then
  echo "Tekton Build Failed"
  exit 1
fi

echo -e "\033[36mCleaning up: \033[0m"
rm ./run.sh -Rf
echo -e "\033[36m  - exec ✅ \033[0m"
rm ~/.kube/config -Rf
echo -e "\033[36m  - kubeconfig ✅ \033[0m"
