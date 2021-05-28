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
ACC=$(shell toml get ${DATA_PATH}/miner.toml profile.account | tr -d '"')
endif
IP=$(shell toml get ${DATA_PATH}/miner.toml profile.ip)

# Github settings
GITHUB_TOKEN = $(shell cat ${DATA_PATH}/github_token.txt || echo NOT FOUND)
REPO_ORG = OLSF

ifeq (${TEST}, y)
REPO_NAME = dev-genesis
MNEM = $(shell cat fixtures/mnemonic/${NS}.mnem)
else
REPO_NAME = experimental-genesis
NODE_ENV = prod
endif
#experimental network is #7

# Registration params
REMOTE = 'backend=github;repository_owner=${REPO_ORG};repository=${REPO_NAME};token=${DATA_PATH}/github_token.txt;namespace=${ACC}'
LOCAL = 'backend=disk;path=${DATA_PATH}/key_store.json;namespace=${ACC}'

##### DEPENDENCIES #####
deps:
	#install rust
	curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain stable -y
	#target is Ubuntu
	sudo apt-get update
	sudo apt-get -y install build-essential cmake clang llvm libgmp-dev pkg-config libssl-dev


bins:
	#TOML cli
	cargo install toml-cli
	cargo run -p stdlib --release
	#Build and install genesis tool, libra-node, and miner
	cargo build -p miner --release && sudo cp -f ${SOURCE}/target/release/miner /usr/local/bin/miner
	cargo build -p libra-node --release && sudo cp -f ${SOURCE}/target/release/libra-node /usr/local/bin/libra-node

##### PIPELINES #####
# pipelines for genesis ceremony

#### GENESIS BACKEND SETUP ####
init-backend: 
	curl -X POST -H "Authorization: token ${GITHUB_TOKEN}" https://api.github.com/orgs/${REPO_ORG}/repos -d '{"name":"${REPO_NAME}", "private": "true", "auto_init": "true"}'

layout:
	cargo run -p libra-genesis-tool --release -- set-layout \
	--shared-backend 'backend=github;repository_owner=${REPO_ORG};repository=${REPO_NAME};token=${DATA_PATH}/github_token.txt;namespace=common' \
	--path ./util/set_layout_${NODE_ENV}.toml

root:
		cargo run -p libra-genesis-tool --release -- libra-root-key \
		--validator-backend ${LOCAL} \
		--shared-backend ${REMOTE}

treasury:
		cargo run -p libra-genesis-tool --release --  treasury-compliance-key \
		--validator-backend ${LOCAL} \
		--shared-backend ${REMOTE}

#### GENESIS REGISTRATION ####
ceremony:
	export NODE_ENV=prod && miner ceremony

register:
# export ACC=$(shell toml get ${DATA_PATH}/miner.toml profile.account)
	@echo Initializing from ${DATA_PATH}/miner.toml with account:
	@echo ${ACC}
	make init

	@echo the OPER initializes local accounts and submit pubkeys to github
	ACC=${ACC}-oper make oper-key

	@echo The OWNERS initialize local accounts and submit pubkeys to github, and mining proofs
	make owner-key add-proofs

	@echo OWNER *assigns* an operator.
	OPER=${ACC}-oper make assign

	@echo OPER send signed transaction with configurations for *OWNER* account
	ACC=${ACC}-oper OWNER=${ACC} IP=${IP} make reg

init-test:
	echo ${MNEM} | head -c -1 | cargo run -p libra-genesis-tool --  init --path=${DATA_PATH} --namespace=${ACC}

init:
	cargo run -p libra-genesis-tool --release --  init --path=${DATA_PATH} --namespace=${ACC}
# OWNER does this
# Submits proofs to shared storage
add-proofs:
	cargo run -p libra-genesis-tool --release --  mining \
	--path-to-genesis-pow ${DATA_PATH}/blocks/block_0.json \
	--shared-backend ${REMOTE}

# OPER does this
# Submits operator key to github, and creates local OPERATOR_ACCOUNT
oper-key:
	cargo run -p libra-genesis-tool --release --  operator-key \
	--validator-backend ${LOCAL} \
	--shared-backend ${REMOTE}

# OWNER does this
# Submits operator key to github, does *NOT* create the OWNER_ACCOUNT locally
owner-key:
	cargo run -p libra-genesis-tool --release --  owner-key \
	--validator-backend ${LOCAL} \
	--shared-backend ${REMOTE}

# OWNER does this
# Links to an operator on github, creates the OWNER_ACCOUNT locally
assign: 
	cargo run -p libra-genesis-tool --release --  set-operator \
	--operator-name ${OPER} \
	--shared-backend ${REMOTE}

# OPER does this
# Submits signed validator registration transaction to github.
reg:
	cargo run -p libra-genesis-tool --release --  validator-config \
	--owner-name ${OWNER} \
	--chain-id ${CHAIN_ID} \
	--validator-address "/ip4/${IP}/tcp/6180" \
	--fullnode-address "/ip4/${IP}/tcp/6179" \
	--validator-backend ${LOCAL} \
	--shared-backend ${REMOTE}
	

## Helpers to verify the local state.
verify:
	cargo run -p libra-genesis-tool --release --  verify \
	--validator-backend ${LOCAL}
	# --genesis-path ${DATA_PATH}/genesis.blob

verify-gen:
	cargo run -p libra-genesis-tool --release --  verify \
	--validator-backend ${LOCAL} \
	--genesis-path ${DATA_PATH}/genesis.blob


#### GENESIS  ####
build-gen:
	cargo run -p libra-genesis-tool --release -- genesis \
	--chain-id ${CHAIN_ID} \
	--shared-backend ${REMOTE} \
	--path ${DATA_PATH}/genesis.blob

genesis:
	cargo run -p libra-genesis-tool --release -- files \
	--chain-id ${CHAIN_ID} \
	--validator-backend ${LOCAL} \
	--data-path ${DATA_PATH} \
	--namespace ${ACC}-oper \
	--repo ${REPO_NAME} \
	--github-org ${REPO_ORG}


#### NODE MANAGEMENT ####
start:
# run in foreground. Only for testing, use a daemon for net.
	cargo run -p libra-node -- --config ${DATA_PATH}/node.yaml

daemon:
# your node's custom libra-node.service lives in ~/.0L. Take the template from libra/util and edit for your needs.
	sudo cp -f ~/.0L/libra-node.service /lib/systemd/system/

	@if test -d ~/logs; then \
		echo "WIPING SYSTEMD LOGS"; \
		sudo rm -rf ~/logs*; \
	fi 

	sudo mkdir ~/logs
	sudo touch ~/logs/node.log
	sudo chmod 777 ~/logs
	sudo chmod 777 ~/logs/node.log

	sudo systemctl daemon-reload
	sudo systemctl stop libra-node.service
	sudo systemctl start libra-node.service
	sudo sleep 2
	sudo systemctl status libra-node.service &
	sudo tail -f ~/logs/node.log

#### TEST SETUP ####

clear:
	if test ${DATA_PATH}/key_store.json; then \
		cd ${DATA_PATH} && rm -rf libradb *.yaml *.blob *.json db *.toml; \
	fi
	if test -d ${DATA_PATH}/blocks; then \
		rm -f ${DATA_PATH}/blocks/*.json; \
	fi

fixture-stdlib:
	make stdlib
	cp language/stdlib/staged/stdlib.mv fixtures/stdlib/fresh_stdlib.mv

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

	@if test -f ${DATA_PATH}/miner.toml; then \
		rm ${DATA_PATH}/miner.toml; \
	fi 

# skip  genesis files with fixtures, there may be no version
ifndef SKIP_BLOB
	cp ./fixtures/genesis/${V}/genesis.blob ${DATA_PATH}/
	cp ./fixtures/genesis/${V}/genesis_waypoint ${DATA_PATH}/
endif
# skip miner configuration with fixtures
	cp ./fixtures/configs/${NS}.toml ${DATA_PATH}/miner.toml
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

client: set-waypoint
ifeq (${TEST}, y)
	 echo ${MNEM} | cargo run -p cli -- -u http://localhost:8080 --waypoint $$(cat ${DATA_PATH}/client_waypoint) --chain-id ${CHAIN_ID}
else
	cargo run -p cli -- -u http://localhost:8080 --waypoint $$(cat ${DATA_PATH}/client_waypoint) --chain-id ${CHAIN_ID}
endif

test: set-waypoint
	cargo run -p cli -- -u http://localhost:8080 --waypoint "$$(cat ${DATA_PATH}/client_waypoint)" --chain-id ${CHAIN_ID}


stdlib:
	cargo run --release -p stdlib
	cargo run --release -p stdlib -- --create-upgrade-payload
	sha256sum language/stdlib/staged/stdlib.mv
  
keygen:
	cd ${DATA_PATH} && miner keygen

miner-genesis:
	cd ${DATA_PATH} && NODE_ENV=${NODE_ENV} miner genesis

reset: stop clear fixtures init keys genesis daemon

remove-keys:
	make stop
	jq 'del(.["${ACC}-oper/owner", "${ACC}-oper/operator"])' ${DATA_PATH}/key_store.json > ${DATA_PATH}/tmp
	mv ${DATA_PATH}/tmp ${DATA_PATH}/key_store.json

wipe: 
	history -c
	shred ~/.bash_history
	srm ~/.bash_history

stop:
	sudo service libra-node stop


##### DEVNET TESTS #####
# Quickly start a devnet with fixture files. To do a full devnet setup see 'devnet-reset' below

devnet: stop clear fix devnet-keys devnet-yaml start
# runs a smoke test from fixtures. Uses genesis blob from fixtures, assumes 3 validators, and test settings.
# This will work for validator nodes alice, bob, carol, and any fullnodes; 'eve'

devnet-keys: 
	@printf '${MNEM}' | cargo run -p miner -- init --skip-miner

devnet-yaml:
	cargo run -p miner -- genesis

devnet-onboard: clear fix
	#starts config for a new miner "eve", uses the devnet github repo for ceremony
	cargo r -p miner -- init --skip-miner <<< $$'${MNEM}'
	cargo r -p miner -- genesis

devnet-previous: stop clear 
# runs a smoke test from fixtures. Uses genesis blob from fixtures, assumes 3 validators, and test settings.
	V=previous make fix devnet-keys devnet-yaml start


### FULL DEVNET RESET ####

devnet-reset: devnet-reset-ceremony genesis start
# Tests the full genesis ceremony cycle, and rebuilds all genesis and waypoints.

devnet-reset-ceremony:
# note: this uses the NS in local env to create files i.e. alice or bob
# as a operator/owner pair.
	SKIP_BLOB=y make clear fix
	echo ${MNEM} | head -c -1 | make register

devnet-reset-onboard: clear 
# fixtures needs a file that works
	SKIP_BLOB=y fix
# starts config for a new miner "eve", uses the devnet github repo for ceremony
	cargo r -p miner -- val-wizard --chain-id 1 --github-org OLSF --repo dev-genesis --rebuild-genesis --skip-mining

#### GIT HELPERS FOR DEVNET AUTOMATION ####
devnet-save-genesis: get-waypoint
	echo $$WAY > ${DATA_PATH}/genesis_waypoint
	rsync -a ${DATA_PATH}/genesis* ${SOURCE}/fixtures/genesis/${V}/
	git add ${SOURCE}/fixtures/genesis/${V}/
	git commit -a -m "save genesis fixtures to ${V}"
	git push

devnet-hard:
	git reset --hard origin/${V} 

devnet-pull:
# must be on a branch
	git fetch && git checkout ${V} -f && git pull

devnet-fn:
	cargo run -p miner -- fn-wizard --path ~/.0L/
