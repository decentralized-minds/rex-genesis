#### VARIABLES ####
SHELL=/usr/bin/env bash
DATA_PATH = ${HOME}/.0L


# Chain settings
CHAIN_ID = 1

ifndef SOURCE
SOURCE=${HOME}/libra
endif

ifndef V
V=previous
endif

# Account settings
ifndef ACC
ACC=$(shell toml get ${DATA_PATH}/0L.toml profile.account | tr -d '"')
endif
IP=$(shell toml get ${DATA_PATH}/0L.toml profile.ip)

# Github settings
GITHUB_TOKEN = $(shell cat ${DATA_PATH}/github_token.txt || echo NOT FOUND)
ifndef NODE_ENV
NODE_ENV = prod
endif

#REPO_ORG = decentralized-minds
REPO_ORG = decentralized-minds
REPO_NAME = rex-genesis
LAYOUT_FILE = ~/rex-genesis/set_layout.toml

# Registration params
REMOTE = 'backend=github;repository_owner=${REPO_ORG};repository=${REPO_NAME};token=${DATA_PATH}/github_token.txt;namespace=${ACC}'
LOCAL = 'backend=disk;path=${DATA_PATH}/key_store.json;namespace=${ACC}'

##### DEPENDENCIES #####
deps:
	. ./ol/util/setup.sh

bins:
# Build and install genesis tool, libra-node, and miner
	cargo run -p stdlib --release

# NOTE: stdlib is built for cli bindings
	cargo build -p libra-node -p miner -p backup-cli -p ol -p txs -p onboard --release

install:
	sudo cp -f ${SOURCE}/target/release/miner /usr/local/bin/miner
	sudo cp -f ${SOURCE}/target/release/libra-node /usr/local/bin/libra-node
	sudo cp -f ${SOURCE}/target/release/db-restore /usr/local/bin/db-restore
	sudo cp -f ${SOURCE}/target/release/db-backup /usr/local/bin/db-backup
	sudo cp -f ${SOURCE}/target/release/db-backup-verify /usr/local/bin/db-backup-verify
	sudo cp -f ${SOURCE}/target/release/ol /usr/local/bin/ol
	sudo cp -f ${SOURCE}/target/release/txs /usr/local/bin/txs
	sudo cp -f ${SOURCE}/target/release/onboard /usr/local/bin/onboard


##### PIPELINES #####
# pipelines for genesis ceremony

#### GENESIS BACKEND SETUP ####
layout:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release -- set-layout \
	--shared-backend 'backend=github;repository_owner=${REPO_ORG};repository=${REPO_NAME};token=${DATA_PATH}/github_token.txt;namespace=common' \
	--path ${LAYOUT_FILE}

root:
		cd ${SOURCE} && cargo run -p libra-genesis-tool --release -- libra-root-key \
		--validator-backend ${LOCAL} \
		--shared-backend ${REMOTE}

treasury:
		cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  treasury-compliance-key \
		--validator-backend ${LOCAL} \
		--shared-backend ${REMOTE}

#### GENESIS REGISTRATION ####

# create a new mnemonic and account
keygen:
	cd ${SOURCE} && cargo run -p onboard -- keygen

init:
	cd ${SOURCE} && cargo run -p ol -- init

mine:
	cd ${SOURCE} && cargo run -p miner -- zero

# send registration info
register:
	@echo Initializing from ${DATA_PATH}/0L.toml with account:
	@echo ${ACC}
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  init --path=${DATA_PATH} --namespace=${ACC}
# make genesis-init

	@echo the OPER initializes local accounts and submit pubkeys to github
	ACC=${ACC}-oper make oper-key

	@echo The OWNERS initialize local accounts and submit pubkeys to github, and mining proofs
	make owner-key add-proofs

	@echo OWNER *assigns* an operator.
	OPER=${ACC}-oper make assign

	@echo OPER send signed transaction with configurations for *OWNER* account
	ACC=${ACC}-oper OWNER=${ACC} IP=${IP} make reg

#### GENESIS  ####
genesis:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release -- genesis \
	--chain-id ${CHAIN_ID} \
	--shared-backend ${REMOTE} \
	--path ${DATA_PATH}/genesis.blob

node-file:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release -- files \
	--chain-id ${CHAIN_ID} \
	--validator-backend ${LOCAL} \
	--data-path ${DATA_PATH} \
	--namespace ${ACC}-oper \
	--repo ${REPO_NAME} \
	--github-org ${REPO_ORG}

remove-key:
	make stop
	jq 'del(.["${ACC}-oper/owner")' ${DATA_PATH}/key_store.json > ${DATA_PATH}/tmp
	mv ${DATA_PATH}/tmp ${DATA_PATH}/key_store.json


########## Recipes for Genesis ##########

# OWNER does this
# Submits proofs to shared storage
add-proofs:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  mining \
	--path-to-genesis-pow ${DATA_PATH}/blocks/block_0.json \
	--shared-backend ${REMOTE}

# OPER does this
# Submits operator key to github, and creates local OPERATOR_ACCOUNT
oper-key:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  operator-key \
	--validator-backend ${LOCAL} \
	--shared-backend ${REMOTE}

# OWNER does this
# Submits operator key to github, does *NOT* create the OWNER_ACCOUNT locally
owner-key:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  owner-key \
	--validator-backend ${LOCAL} \
	--shared-backend ${REMOTE}

# OWNER does this
# Links to an operator on github, creates the OWNER_ACCOUNT locally
assign: 
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  set-operator \
	--operator-name ${OPER} \
	--shared-backend ${REMOTE}

# OPER does this
# Submits signed validator registration transaction to github.
reg:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  validator-config \
	--owner-name ${OWNER} \
	--chain-id ${CHAIN_ID} \
	--validator-address "/ip4/${IP}/tcp/6180" \
	--fullnode-address "/ip4/${IP}/tcp/6179" \
	--validator-backend ${LOCAL} \
	--shared-backend ${REMOTE}
	

## Helpers to verify the local state.
verify:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  verify \
	--validator-backend ${LOCAL}
	# --genesis-path ${DATA_PATH}/genesis.blob

verify-gen:
	cd ${SOURCE} && cargo run -p libra-genesis-tool --release --  verify \
	--validator-backend ${LOCAL} \
	--genesis-path ${DATA_PATH}/genesis.blob




#### NODE MANAGEMENT ####
start:
# run in foreground. Only for testing, use a daemon for net.
	cd ${SOURCE} && cargo run -p libra-node -- --config ${DATA_PATH}/validator.node.yaml

#### HELPERS ####
check:
	@echo data path: ${DATA_PATH}
	@echo account: ${ACC}
	@echo github_token: ${GITHUB_TOKEN}
	@echo ip: ${IP}
	@echo node path: ${DATA_PATH}
	@echo github_org: ${REPO_ORG}
	@echo github_repo: ${REPO_NAME}
	@echo env: ${NODE_ENV}
	@echo devnet mode: ${TEST}
	@echo devnet name: ${NS}
	@echo devnet mnem: ${MNEM}


fix:
ifdef TEST
	echo ${NS}
	@if test ! -d ${0L_PATH}; then \
		mkdir ${0L_PATH}; \
		mkdir ${DATA_PATH}; \
		mkdir -p ${DATA_PATH}/blocks/; \
	fi

	@if test -f ${DATA_PATH}/blocks/block_0.json; then \
		rm ${DATA_PATH}/blocks/block_0.json; \
	fi 

	@if test -f ${DATA_PATH}/0L.toml; then \
		rm ${DATA_PATH}/0L.toml; \
	fi 

# skip  genesis files with fixtures, there may be no version
ifndef SKIP_BLOB
	cp ./fixtures/genesis/${V}/genesis.blob ${DATA_PATH}/
	cp ./fixtures/genesis/${V}/genesis_waypoint ${DATA_PATH}/
endif
# skip miner configuration with fixtures
	cp ./fixtures/configs/${NS}.toml ${DATA_PATH}/0L.toml
# skip mining proof zero with fixtures
	cp ./fixtures/blocks/${NODE_ENV}/${NS}/block_0.json ${DATA_PATH}/blocks/block_0.json

endif


#### HELPERS ####
set-waypoint:
	@if test -f ${DATA_PATH}/key_store.json; then \
		jq -r '. | with_entries(select(.key|match("-oper/waypoint";"i")))[].value' ${DATA_PATH}/key_store.json > ${DATA_PATH}/client_waypoint; \
	fi

	@if test ! -f ${DATA_PATH}/key_store.json; then \
		cat ${DATA_PATH}/restore_waypoint > ${DATA_PATH}/client_waypoint; \
	fi
	@echo client_waypoint:
	@cat ${DATA_PATH}/client_waypoint


stdlib:
	cargo run --release -p stdlib
	cargo run --release -p stdlib -- --create-upgrade-payload
	sha256sum language/stdlib/staged/stdlib.mv

