#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Updating Chaincode contract On Delivery Network"
echo
CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
VERSION="$4"
TYPE="$5"
: ${CHANNEL_NAME:="deliverychannel"}
: ${DELAY:="5"}
: ${LANGUAGE:="node"}
: ${VERSION:=1.1}
: ${TYPE="basic"}

LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
ORGS="customer squad restaurant"
TIMEOUT=15

if [ "$TYPE" = "basic" ]; then
  CC_SRC_PATH="/opt/gopath/src/github.com/hyperledger/fabric/peer/chaincode/"
else
  CC_SRC_PATH="/opt/gopath/src/github.com/hyperledger/fabric/peer/chaincode-advanced/"
fi

echo "New Version : "$VERSION

# import utils
. scripts/utils.sh

## Install new version of chaincode on peer0 of all 3 orgs making them endorsers
echo "Updating chaincode on peer0.restaurant.delivery-network.com ..."
installChaincode 0 'restaurant' $VERSION
echo "Updating chaincode on peer0.squad.delivery-network.com ..."
installChaincode 0 'squad' $VERSION
echo "Updating chaincode on peer0.customer.delivery-network.com ..."
installChaincode 0 'customer' $VERSION

# Upgrade chaincode on the channel using peer0.iit
echo "Upgrading chaincode on channel using peer0.restaurant.delivery-network.com ..."
upgradeChaincode 0 'restaurant' $VERSION

echo
echo "========= All GOOD, Chaincode contract Is Now Updated To Version '$VERSION' =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
