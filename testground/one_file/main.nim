import std/strutils, std/random
import testground_sdk, chronos, stew/byteutils

testground(client):
  let
    # wait for setup
    myId = await client.signalAndWait("setup", client.testInstanceCount)
    # here we are using this id to generate our local ip
    # TODO find where to redirect calls to codex
    myIp = client.testSubnet.split('.')[0..1].join(".") & ".1." & $myId
    serverIp = client.testSubnet.split('.')[0..1].join(".") & ".1.1"
  #setting network parameters
  await client.updateNetworkParameter(
    NetworkConf(
      network: "default",
      ipv4: some myIp & "/24",
      enable: true,
      # signal when done
      callback_state: "network_setup",
      callback_target: some client.testInstanceCount,
      routing_policy: "accept_all",
    )
  )

  # wait for everyone to reach the state with proper networking setup
  await client.waitForBarrier("network_setup", client.testInstanceCount)

  # TODO change this to upload a file
  randomize()
  await client.publish("rands", AwesomeStruct(rand: rand(100)))
  let randomValues = client.subscribe("rands", AwesomeStruct)
  for _ in 0 ..< 2:
    echo await randomValues.popFirst()

  # read parameters from the composition or command line flags
  let
    payload = client.param(string, "payload")
    count = client.param(int, "count")
    printResult = client.param(bool, "printResult")

  if myId == 1: # server
    let server = createStreamServer(initTAddress(myIp & ":5050"), flags = {ReuseAddr})
    # We are ready for clients
    discard await client.signalAndWait("ready", client.testInstanceCount)
    let connection = await server.accept()

    for _ in 0 ..< count:
      doAssert (await connection.write(payload.toBytes())) == payload.len
    connection.close()

  else: # client
    # wait for the server to be started
    discard await client.signalAndWait("ready", client.testInstanceCount)
    let connection = await connect(initTAddress(serverIp & ":5050"))
    var buffer = newSeq[byte](payload.len)

    for _ in 0 ..< count:
      # TODO change this to download file and check contents
      await connection.readExactly(addr buffer[0], payload.len)
      doAssert string.fromBytes(buffer) == payload
    connection.close()

  if printResult:
    client.recordMessage("Hourray " & $myId & "!")
