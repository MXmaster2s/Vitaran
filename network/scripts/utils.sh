# This is a collection of bash functions used by different scripts

ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/delivery-network.com/orderers/orderer.delivery-network.com/msp/tlscacerts/tlsca.delivery-network.com-cert.pem
PEER0_CUSTOMER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/customer.delivery-network.com/peers/peer0.customer.delivery-network.com/tls/ca.crt
PEER0_SQUAD_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/squad.delivery-network.com/peers/peer0.squad.delivery-network.com/tls/ca.crt
PEER0_RESTAURANT_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/restaurant.delivery-network.com/peers/peer0.restaurant.delivery-network.com/tls/ca.crt

# verify the result of the end-to-end test
verifyResult() {
  if [ "$1" -ne 0 ]; then
    echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
    echo "========= ERROR !!! FAILED to execute Delivery Network Bootstrap ==========="
    echo
    exit 1
  fi
}

# Set OrdererOrg.Admin globals
setOrdererGlobals() {
  CORE_PEER_LOCALMSPID="OrdererMSP"
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/delivery-network.com/orderers/orderer.delivery-network.com/msp/tlscacerts/tlsca.delivery-network.com-cert.pem
  CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/delivery-network.com/users/Admin@delivery-network.com/msp
}

setGlobals() {
  PEER=$1
  ORG=$2
  if [ "$ORG" == 'customer' ]; then
    CORE_PEER_LOCALMSPID="customerMSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_CUSTOMER_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/customer.delivery-network.com/users/Admin@customer.delivery-network.com/msp
    if [ "$PEER" -eq 0 ]; then
      CORE_PEER_ADDRESS=peer0.customer.delivery-network.com:7051
    else
      CORE_PEER_ADDRESS=peer1.customer.delivery-network.com:8051
    fi
  elif [ "$ORG" == 'squad' ]; then
    CORE_PEER_LOCALMSPID="squadMSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_SQUAD_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/squad.delivery-network.com/users/Admin@squad.delivery-network.com/msp
    if [ "$PEER" -eq 0 ]; then
      CORE_PEER_ADDRESS=peer0.squad.delivery-network.com:13051
    fi
    if [ "$PEER" -eq 1 ]; then
      CORE_PEER_ADDRESS=peer1.squad.delivery-network.com:14051
    fi
  elif [ "$ORG" == 'restaurant' ]; then
    CORE_PEER_LOCALMSPID="restaurantMSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_RESTAURANT_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/restaurant.delivery-network.com/users/Admin@restaurant.delivery-network.com/msp
    if [ "$PEER" -eq 0 ]; then
      CORE_PEER_ADDRESS=peer0.restaurant.delivery-network.com:11051
    else
      CORE_PEER_ADDRESS=peer1.restaurant.delivery-network.com:12051
    fi
  else
    echo "================== ERROR !!! ORG Unknown =================="
  fi
}

updateAnchorPeers() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer channel update -o orderer.delivery-network.com:7050 -c "$CHANNEL_NAME" -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx >&log.txt
    res=$?
    set +x
  else
    set -x
    peer channel update -o orderer.delivery-network.com:7050 -c "$CHANNEL_NAME" -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls "$CORE_PEER_TLS_ENABLED" --cafile $ORDERER_CA >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Anchor peer update failed"
  echo "===================== Anchor peers updated for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME' ===================== "
  sleep "$DELAY"
  echo
}

## Sometimes Join takes time hence RETRY at least 5 times
joinChannelWithRetry() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"

  set -x
  peer channel join -b "$CHANNEL_NAME".block >&log.txt
  res=$?
  set +x
  cat log.txt
  if [ $res -ne 0 -a "$COUNTER" -lt "$MAX_RETRY" ]; then
    COUNTER=$(expr "$COUNTER" + 1)
    echo "peer${PEER}.${ORG} failed to join the channel, Retry after $DELAY seconds"
    sleep "$DELAY"
    joinChannelWithRetry "$PEER" "$ORG"
  else
    COUNTER=1
  fi
  verifyResult $res "After $MAX_RETRY attempts, peer${PEER}.${ORG} has failed to join channel '$CHANNEL_NAME' "
}

installChaincode() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"
  VERSION=${3:-1.0}
  set -x
  peer chaincode install -n contract -v "${VERSION}" -l "${LANGUAGE}" -p "${CC_SRC_PATH}" >&log.txt
  res=$?
  set +x
  cat log.txt
  verifyResult $res "Chaincode installation on peer${PEER}.${ORG} has failed"
  echo "===================== Chaincode is installed on peer${PEER}.${ORG} ===================== "
  echo
}

instantiateChaincode() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"
  VERSION=${3:-1.0}

  # while 'peer chaincode' command can get the orderer endpoint from the peer
  # (if join was successful), let's supply it directly as we know it using
  # the "-o" option
  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode instantiate -o orderer.delivery-network.com:7050 -C "$CHANNEL_NAME" -n contract -l "${LANGUAGE}" -v "${VERSION}" -c '{"Args":["org.delivery-network.contract:instantiate"]}' -P "OR ('restaurantMSP.member','squadMSP.member','customerMSP.member')">&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode instantiate -o orderer.delivery-network.com:7050 --tls "$CORE_PEER_TLS_ENABLED" --cafile $ORDERER_CA -C $CHANNEL_NAME -n contract -l ${LANGUAGE} -v ${VERSION} -c '{"Args":["org.delivery-network.contract:instantiate"]}' -P "OR ('restaurantMSP.member','squadMSP.member','customerMSP.member')">&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode instantiation on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode is instantiated on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

upgradeChaincode() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  VERSION=${3:-1.0}

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode upgrade -o orderer.delivery-network.com:7050 -C $CHANNEL_NAME -n contract -l ${LANGUAGE} -v ${VERSION} -p ${CC_SRC_PATH} -c '{"Args":["org.delivery-network.com.contract:instantiate"]}' -P "OR ('restaurantMSP.member','squadMSP.member','customerMSP.member')" >&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode upgrade -o orderer.delivery-network.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n contract -l ${LANGUAGE} -v ${VERSION} -p ${CC_SRC_PATH} -c '{"Args":["org.delivery-network.com.contract:instantiate"]}' -P "OR ('restaurantMSP.member','squadMSP.member','customerMSP.member')" >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode upgrade on peer${PEER}.${ORG} has failed"
  echo "===================== Chaincode is upgraded on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

chaincodeQuery() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  EXPECTED_RESULT=$3
  echo "===================== Querying on peer${PEER}.${ORG} on channel '$CHANNEL_NAME'... ===================== "
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while
    test "$(($(date +%s) - starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
    sleep $DELAY
    echo "Attempting to Query peer${PEER}.${ORG} ...$(($(date +%s) - starttime)) secs"
    set -x
    peer chaincode query -C $CHANNEL_NAME -n contract -c '{"Args":["org.delivery-network.contract:instantiate"]}' >&log.txt
    res=$?
    set +x
    test $res -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
    # removed the string "Query Result" from peer chaincode query command
    # result. as a result, have to support both options until the change
    # is merged.
    test $rc -ne 0 && VALUE=$(cat log.txt | egrep '^[0-9]+$')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0; then
    echo "===================== Query successful on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  else
    echo "!!!!!!!!!!!!!!! Query result on peer${PEER}.${ORG} is INVALID !!!!!!!!!!!!!!!!"
    echo "================== ERROR !!! FAILED to query Chaincode on Delivery Network =================="
    echo
    exit 1
  fi
}

# chaincodeInvoke <peer> <org> ...
# Accepts as many peer/org pairs as desired and requests endorsement from each
chaincodeInvoke() {
  parsePeerConnectionParameters $@
  res=$?
  verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  # while 'peer chaincode' command can get the orderer endpoint from the
  # peer (if join was successful), let's supply it directly as we know
  # it using the "-o" option
  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode invoke -o orderer.delivery-network.com:7050 -C $CHANNEL_NAME -n contract $PEER_CONN_PARMS -c '{"Args":["org.delivery-network.contract:createRestaurant","0001","Mummys Yummy Food","connect@food.com"]}' >&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode invoke -o orderer.delivery-network.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n contract $PEER_CONN_PARMS -c '{"Args":["org.delivery-network.contract:createRestaurant","0001","Mummys Yummy Food","connect@food.com"]}' >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Invoke execution on $PEERS failed "
  echo "===================== Invoke transaction successful on $PEERS on channel '$CHANNEL_NAME' ===================== "
  echo
}
