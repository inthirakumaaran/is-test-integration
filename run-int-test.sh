#----------------------------------------------------------------------------
#  Copyright (c) 2020 WSO2, Inc. http://www.wso2.org
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#----------------------------------------------------------------------------
#!/bin/bash

set -o xtrace; set -e

TESTGRID_DIR=/opt/testgrid/workspace
INFRA_JSON='infra.json'

PRODUCT_REPOSITORY=$1
PRODUCT_REPOSITORY_BRANCH=$2
PRODUCT_NAME="wso2$3"
PRODUCT_VERSION=$4
GIT_USER=$5
GIT_PASS=$6
TEST_MODE=$7
TEST_GROUP=$8
PRODUCT_REPOSITORY_NAME=$(echo $PRODUCT_REPOSITORY | rev | cut -d'/' -f1 | rev | cut -d'.' -f1)
PRODUCT_REPOSITORY_PACK_DIR="$TESTGRID_DIR/$PRODUCT_REPOSITORY_NAME/modules/distribution/target"
INT_TEST_MODULE_DIR="$TESTGRID_DIR/$PRODUCT_REPOSITORY_NAME/modules/integration"

# CloudFormation properties
CFN_PROP_FILE="${TESTGRID_DIR}/cfn-props.properties"

JDK_TYPE=$(grep -w "JDK_TYPE" ${CFN_PROP_FILE} | cut -d"=" -f2)
DB_TYPE=$(grep -w "DB_TYPE" ${CFN_PROP_FILE} | cut -d"=" -f2)
PRODUCT_PACK_NAME=$(grep -w "REMOTE_PACK_NAME" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_VERSION=$(grep -w "CF_DB_VERSION" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_PASSWORD=$(grep -w "CF_DB_PASSWORD" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_USERNAME=$(grep -w "CF_DB_USERNAME" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_HOST=$(grep -w "CF_DB_HOST" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_PORT=$(grep -w "CF_DB_PORT" ${CFN_PROP_FILE} | cut -d"=" -f2)
CF_DB_NAME=$(grep -w "SID" ${CFN_PROP_FILE} | cut -d"=" -f2)
PRODUCT_PACK_LOCATION=$(grep -w "PRODUCT_PACK_LOCATION" ${CFN_PROP_FILE} | cut -d"=" -f2)

function log_info(){
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
}

function log_error(){
    echo "[ERROR][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
    exit 1
}

function install_jdk(){
    jdk_name=$1

    mkdir -p /opt/${jdk_name}
    jdk_file=$(jq -r '.jdk[] | select ( .name == '\"${jdk_name}\"') | .file_name' ${INFRA_JSON})
    wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdk/$jdk_file.tar.gz
    tar -xzf "$jdk_file.tar.gz" -C /opt/${jdk_name} --strip-component=1

    export JAVA_HOME=/opt/${jdk_name}
    echo $JAVA_HOME
}

function export_db_params(){
    db_name=$1

    export WSO2SHARED_DB_DRIVER=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .driver' ${INFRA_JSON})
    export WSO2SHARED_DB_URL=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2SHARED_DB") | .url' ${INFRA_JSON})
    export WSO2SHARED_DB_USERNAME=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2SHARED_DB") | .username' ${INFRA_JSON})
    export WSO2SHARED_DB_PASSWORD=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2SHARED_DB") | .password' ${INFRA_JSON})
    export WSO2SHARED_DB_VALIDATION_QUERY=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .validation_query' ${INFRA_JSON})
    
    export WSO2IDENTITY_DB_DRIVER=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .driver' ${INFRA_JSON})
    export WSO2IDENTITY_DB_URL=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2IDENTITY_DB") | .url' ${INFRA_JSON})
    export WSO2IDENTITY_DB_USERNAME=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2IDENTITY_DB") | .username' ${INFRA_JSON})
    export WSO2IDENTITY_DB_PASSWORD=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .database[] | select ( .name == "WSO2IDENTITY_DB") | .password' ${INFRA_JSON})
    export WSO2IDENTITY_DB_VALIDATION_QUERY=$(jq -r '.jdbc[] | select ( .name == '\"${db_name}\"' ) | .validation_query' ${INFRA_JSON})
    
}

source /etc/environment

log_info "Clone Product repository"
if [ ! -d $PRODUCT_REPOSITORY_NAME ];
then
    git clone https://${GIT_USER}:${GIT_PASS}@$PRODUCT_REPOSITORY --branch $PRODUCT_REPOSITORY_BRANCH --single-branch
fi

log_info "Exporting JDK"
install_jdk ${JDK_TYPE}

# mv $TESTGRID_DIR/$PRODUCT_PACK_NAME $TESTGRID_DIR/new/$PRODUCT_PACK_NAME
pwd
cd $TESTGRID_DIR && wget -q https://integration-testgrid-resources.s3.us-east-1.amazonaws.com/iam-release-packs/$PRODUCT_PACK_NAME.zip
unzip -q $PRODUCT_PACK_NAME.zip -d $TESTGRID_DIR
ls $TESTGRID_DIR/$PRODUCT_PACK_NAME
rm $PRODUCT_PACK_NAME.zip

db_file=$(jq -r '.jdbc[] | select ( .name == '\"${DB_TYPE}\"') | .file_name' ${INFRA_JSON})
wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdbc/${db_file}.jar  -P $TESTGRID_DIR/${PRODUCT_PACK_NAME}/repository/components/lib

sed -i "s|DB_HOST|${CF_DB_HOST}|g" ${INFRA_JSON}
sed -i "s|DB_USERNAME|${CF_DB_USERNAME}|g" ${INFRA_JSON}
sed -i "s|DB_PASSWORD|${CF_DB_PASSWORD}|g" ${INFRA_JSON}
sed -i "s|DB_NAME|${DB_NAME}|g" ${INFRA_JSON}

export_db_params ${DB_TYPE}

# delete if the folder is available
rm -rf $$PRODUCT_REPOSITORY_PACK_DIR
mkdir -p $PRODUCT_REPOSITORY_PACK_DIR
log_info "Copying product pack to Repository"
zip -r $TESTGRID_DIR/$PRODUCT_NAME-$PRODUCT_VERSION-.zip $TESTGRID_DIR/$PRODUCT_PACK_NAME

echo "Copying pack to target"
mv $TESTGRID_DIR/$PRODUCT_PACK_NAME.zip $PRODUCT_REPOSITORY_PACK_DIR/$PRODUCT_PACK_NAME.zip
ls $PRODUCT_REPOSITORY_PACK_DIR
log_info "install pack into local maven Repository"

log_info "Navigating to integration test module directory"
ls $INT_TEST_MODULE_DIR
cd $INT_TEST_MODULE_DIR
ls /opt/testgrid/workspace/product-is/modules/integration/tests-integration/tests-backend/../../../distribution/target/

log_info "Running Maven clean install"
mvn clean install -fae -B -Dcarbon.home=$PRODUCT_REPOSITORY_PACK_DIR -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn


# Add the command to start the server here