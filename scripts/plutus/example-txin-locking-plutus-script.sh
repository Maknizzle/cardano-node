#!/usr/bin/env bash

# Unoffiical bash strict mode.
# See: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -e
set -o pipefail

if [ "$1" == "guessinggame" ]; then
 # NB: This plutus script uses a "typed" redeemer and "typed" datum.
 plutusscriptinuse=scripts/plutus/scripts/typed-guessing-game-redeemer-42-datum-42.plutus
 # This datum hash is the hash of the typed 42
 scriptdatumhash="e68306b4087110b0191f5b70638b9c6fc1c3eb335275e40d110779d71aa86083"
 plutusrequiredspace=700000000
 plutusrequiredtime=700000000
 #50000000000
 datumfilepath=scripts/plutus/data/typed-42.datum
 redeemerfilepath=scripts/plutus/data/typed-42.redeemer
 echo "Guessing game Plutus script in use. The datum and redeemer must be equal to 42."
 echo "Script at: $plutusscriptinuse"

elif [ "$1" == "" ]; then
 plutusscriptinuse=scripts/plutus/scripts/untyped-always-succeeds-txin.plutus
 # This datum hash is the hash of the untyped 42
 scriptdatumhash="9e1199a988ba72ffd6e9c269cadb3b53b5f360ff99f112d9b2ee30c4d74ad88b"
 plutusrequiredspace=70000000
 plutusrequiredtime=70000000
 datumfilepath=scripts/plutus/data/42.datum
 redeemerfilepath=scripts/plutus/data/42.redeemer
 echo "Always succeeds Plutus script in use. Any datum and redeemer combination will succeed."
 echo "Script at: $plutusscriptinuse"
fi


# Step 1: Create a tx ouput with a datum hash at the script address. In order for a tx ouput to be locked
# by a plutus script, it must have a datahash. We also need collateral tx inputs so we split the utxo
# in order to accomodate this.


plutusscriptaddr=$(cardano-cli address build --payment-script-file $plutusscriptinuse  --testnet-magic 42)

mkdir -p example/work

utxovkey=example/shelley/utxo-keys/utxo1.vkey
utxoskey=example/shelley/utxo-keys/utxo1.skey

utxoaddr=$(cardano-cli address build --testnet-magic 42 --payment-verification-key-file $utxovkey)

cardano-cli query utxo --address $utxoaddr --cardano-mode --testnet-magic 42 --out-file example/work/utxo.json

txin=$(jq -r 'keys[]' example/work/utxo.json)
lovelaceattxin=$(jq -r ".[\"$txin\"].value.lovelace" example/work/utxo.json)
lovelaceattxindiv2=$(expr $lovelaceattxin / 2)

cardano-cli transaction build-raw \
  --alonzo-era \
  --fee 0 \
  --tx-in $txin \
  --tx-out "$plutusscriptaddr+$lovelaceattxindiv2" \
  --tx-out-datum-hash "$scriptdatumhash" \
  --tx-out "$utxoaddr+$lovelaceattxindiv2" \
  --out-file example/work/create-datum-output.body

cardano-cli transaction sign \
  --tx-body-file example/work/create-datum-output.body \
  --testnet-magic 42 \
  --signing-key-file $utxoskey\
  --out-file example/work/create-datum-output.tx

# SUBMIT
cardano-cli transaction submit --tx-file example/work/create-datum-output.tx --testnet-magic 42
echo "Pausing for 5 seconds..."
sleep 5

# Step 2
# After "locking" the tx output at the script address, we can now can attempt to spend
# the "locked" tx output below.

cardano-cli query utxo --address $plutusscriptaddr --testnet-magic 42 --out-file example/work/plutusutxo.json
plutusutxotxin=$(jq -r 'keys[]' example/work/plutusutxo.json)

cardano-cli query utxo --address $utxoaddr --cardano-mode --testnet-magic 42 --out-file example/work/utxo.json
txinCollateral=$(jq -r 'keys[]' example/work/utxo.json)

cardano-cli query protocol-parameters --testnet-magic 42 --out-file example/pparams.json

dummyaddress=addr_test1vpqgspvmh6m2m5pwangvdg499srfzre2dd96qq57nlnw6yctpasy4

lovelaceatplutusscriptaddr=$(jq -r ".[\"$plutusutxotxin\"].value.lovelace" example/work/plutusutxo.json)

txfee=$(expr $plutusrequiredtime + $plutusrequiredtime)
spendable=$(expr $lovelaceatplutusscriptaddr - $plutusrequiredtime - $plutusrequiredtime)

cardano-cli transaction build-raw \
  --alonzo-era \
  --fee "$txfee" \
  --tx-in $plutusutxotxin \
  --tx-in-collateral $txinCollateral \
  --tx-out "$dummyaddress+$spendable" \
  --tx-in-script-file $plutusscriptinuse \
  --tx-in-datum-file "$datumfilepath"  \
  --protocol-params-file example/pparams.json\
  --tx-in-redeemer-file "$redeemerfilepath" \
  --tx-in-execution-units "($plutusrequiredtime, $plutusrequiredspace)" \
  --out-file example/work/test-alonzo.body

cardano-cli transaction sign \
  --tx-body-file example/work/test-alonzo.body \
  --testnet-magic 42 \
  --signing-key-file example/shelley/utxo-keys/utxo1.skey \
  --out-file example/work/alonzo.tx

# SUBMIT example/work/alonzo.tx
echo "Submit the tx with plutus script and wait 5 seconds..."
cardano-cli transaction submit --tx-file example/work/alonzo.tx --testnet-magic 42
sleep 5
echo ""
echo "Querying UTxO at $dummyaddress. If there is ADA at the address the Plutus script successfully executed!"
echo ""
cardano-cli query utxo --address "$dummyaddress"  --testnet-magic 42

