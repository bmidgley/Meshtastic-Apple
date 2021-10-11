import Foundation
import CoreData
import CoreBluetooth
import SwiftUI

//---------------------------------------------------------------------------------------
// Meshtastic BLE Device Manager
//---------------------------------------------------------------------------------------
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @ObservedObject private var meshData : MeshData
    @ObservedObject private var messageData : MessageData
    
    @Published private var centralManager: CBCentralManager!
    @Published var connectedPeripheral: Peripheral!
    @Published var connectedNode: NodeInfoModel!
    @Published var lastConnectedNode: String
    @Published var lastConnectionError: String
    
    @Published var isSwitchedOn = false
    @Published var peripherals = [Peripheral]()
    @Published private var broadcastNodeId: UInt32 = 4294967295
    
    /* Meshtastic Service Details */
    var TORADIO_characteristic: CBCharacteristic!
    var FROMRADIO_characteristic: CBCharacteristic!
    var FROMNUM_characteristic: CBCharacteristic!
    
    let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
    let FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")
    
    /* init BLEManager */
    override init() {
        self.meshData = MeshData()
        self.messageData = MessageData()
        self.lastConnectedNode = ""
        self.lastConnectionError = ""
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        centralManager.delegate = self
        meshData.load()
        messageData.load()
    }

    // called when bluetooth is enabled/disabled for the app
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
         if central.state == .poweredOn {
             isSwitchedOn = true
         }
         else {
             isSwitchedOn = false
         }
    }
    
    // Scan for nearby BLE devices using the Meshtastic BLE service ID
    func startScanning() {
        
        if isSwitchedOn {
            peripherals.removeAll()
            centralManager.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: nil)
            print("Scanning Started")
        }
    }
        
    // Stop Scanning For BLE Devices
    func stopScanning() {
        
        if centralManager.isScanning {
            
            self.centralManager.stopScan()
            print("Stopped Scanning")
        }
    }
    
    //  Disconnect Device function
    func disconnectDevice(){
        
        if connectedPeripheral != nil && connectedPeripheral.peripheral.state == CBPeripheralState.connected {
            
            self.centralManager?.cancelPeripheralConnection(connectedPeripheral.peripheral)
        } else {
            connectedNode = nil
            connectedPeripheral = nil
        }
    }
    
    // Connect to a Device via UUID
    func connectToDevice(id: String) {
        
        connectedPeripheral = peripherals.filter({ $0.peripheral.identifier.uuidString == id }).first
        
        if connectedPeripheral != nil {
            
            lastConnectedNode = connectedPeripheral.peripheral.identifier.uuidString
            self.centralManager?.connect(connectedPeripheral!.peripheral)
            print("Connected to: \(connectedPeripheral.peripheral.name ?? "Unknown")")
        }
        else {
            print("Connection failed connectedPeripheral is nil")
        }
    }
    
    // Connect to a specific peripheral
    func connectTo(peripheral: CBPeripheral) {
        
        if connectedPeripheral.peripheral.state == CBPeripheralState.connected {
            self.disconnectDevice()
        }
        connectedPeripheral.peripheral = peripheral
        self.centralManager?.connect(connectedPeripheral!.peripheral)
        print("Connected to: \(connectedPeripheral.peripheral.name ?? "Unknown")")
    }
    
    // Called each time a peripheral is discovered
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
            
        peripheral.delegate = self
        
        var peripheralName: String = peripheral.name ?? "Unknown"
        
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            peripheralName = name
        }
        
        let newPeripheral = Peripheral(id: peripheral.identifier.uuidString, name: peripheralName, rssi: RSSI.intValue, peripheral: peripheral, myInfo: nil)

        peripherals.append(newPeripheral)
        print("Adding peripheral: \(peripheralName)");
    }
    
    // called when a peripheral is connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        peripheral.delegate = self
        peripheral.discoverServices([meshtasticServiceCBUUID])
        print("Peripheral connected: " + peripheral.name!)
        startScanning()
    }
    
    // Send Broadcast Message
    public func sendMessage(message: String) -> Bool
    {
        var success = false
        
        // Return false if we are not properly connected to a device, handle retry logic in the view for now
        if connectedPeripheral == nil || connectedPeripheral!.peripheral.state != CBPeripheralState.connected || self.connectedNode == nil {
            
            if connectedPeripheral != nil && self.connectedNode == nil {
                self.disconnectDevice()
                // Lets disconnect and then reconnect a second later when the message retry happens
            }
            success = false
        }
        else if message.count < 1 {
            // Don's send an empty message
            success = false
        }
        else {

            let messageModel = MessageModel(messageId: 0, messageTimeStamp: UInt32(Date().timeIntervalSince1970), fromUserId: self.connectedNode.num, toUserId: broadcastNodeId, fromUserLongName: self.connectedNode.user.longName, toUserLongName: "Broadcast", fromUserShortName: self.connectedNode.user.shortName, toUserShortName: "BC", receivedACK: false, messagePayload: message, direction: "OUT")
            let dataType = PortNum.textMessageApp
            let payloadData: Data = message.data(using: String.Encoding.utf8)!
        
            var dataMessage = DataMessage()
            dataMessage.payload = payloadData
            dataMessage.portnum = dataType
            
            var meshPacket = MeshPacket()
            meshPacket.to = broadcastNodeId
            meshPacket.decoded = dataMessage
            meshPacket.wantAck = true
            
            var toRadio: ToRadio!
            toRadio = ToRadio()
            toRadio.packet = meshPacket

            let binaryData: Data = try! toRadio.serializedData()
            if (connectedPeripheral!.peripheral.state == CBPeripheralState.connected)
            {
                connectedPeripheral.peripheral.writeValue(binaryData, for: TORADIO_characteristic, type: .withResponse)
                messageData.messages.append(messageModel)
                messageData.save()
                success = true
            }
        }
        return success
    }

    // Disconnect Peripheral Event
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        // Start a Scan so the disconnected peripheral is moved to the peripherals[]
        self.startScanning()
        
        if let e = error {
         print("Central disconnected because \(e)")
            let errorCode = (e as NSError).code
            
            if errorCode == 6 { // The connection has timed out unexpectedly.
                // Happens when device is manually reset / powered off
                connectedPeripheral = nil
                connectedNode = nil
                
            }
            else if errorCode == 7 { // The specified device has disconnected from us.
             
                // Check if the peripheral is still visible and then reconnect
                connectedPeripheral = nil
                connectedNode = nil
            }
            else if errorCode == 14 { // Peer error that may require forgetting device in settings
                lastConnectionError = (e as NSError).description
                // Check if the peripheral is still visible and then reconnect
                connectedPeripheral = nil
                connectedNode = nil
            }

        } else {
            
            print("Central disconnected! (no error)")
            connectedPeripheral = nil
            connectedNode = nil
        }
        
        
        
        print("Peripheral disconnected: " + peripheral.name!)
        
    }
    
    // Discover Services Event
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if let e = error {
         print("Discover Services error \(e)")
       //let errorCode = (e as NSError).code
            
        }
        
        guard let services = peripheral.services else { return }
                
        for service in services
        {
            print("Service discovered: " + service.uuid.uuidString)
            
            if (service.uuid == meshtasticServiceCBUUID)
            {
                print ("Meshtastic service OK")
                peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID], for: service)
            }
        }
    }
    
    // Discover Characteristics Event
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        if let e = error {
            
            print("Discover Characteristics error \(e)")
        }
        
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
        
        switch characteristic.uuid
        {
            case TORADIO_UUID:
                print("TORADIO characteristic OK")
                TORADIO_characteristic = characteristic
                var toRadio: ToRadio = ToRadio()
                toRadio.wantConfigID = 32168
                let binaryData: Data = try! toRadio.serializedData()
                peripheral.writeValue(binaryData, for: characteristic, type: .withResponse)
                break
            
            case FROMRADIO_UUID:
                print("FROMRADIO characteristic OK")
                FROMRADIO_characteristic = characteristic
                peripheral.readValue(for: FROMRADIO_characteristic)
                break
            
            case FROMNUM_UUID:
                print("FROMNUM (Notify) characteristic OK")
                FROMNUM_characteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                break
            
            default:
                break
        }
        
      }
    }
    
    // Data Read / Update Characteristic Event
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        if let e = error {
            
            print("didUpdateValueFor Characteristic error \(e)")
        }
        
        switch characteristic.uuid
        {
            case FROMNUM_UUID:
                peripheral.readValue(for: FROMNUM_characteristic)
                //let byteArrayFromData: [UInt8] = [UInt8](characteristic.value!)
                //let stringFromByteArray = String(data: Data(_: byteArrayFromData), encoding: .ascii)
                //print(stringFromByteArray)
                //print(characteristic.value?. ?? "no value")
    
                
            case FROMRADIO_UUID:
                if (characteristic.value == nil || characteristic.value!.isEmpty)
                {
                    return
                }
            print(characteristic.value ?? "no value")
                
               // print(characteristic.value?.hexDescription ?? "no value")
                var decodedInfo = FromRadio()
                
                decodedInfo = try! FromRadio(serializedData: characteristic.value!)
                //print("Print DecodedInfo")
                //print(decodedInfo)
                
                if decodedInfo.myInfo.myNodeNum != 0
                {

                    // Create a MyInfoModel
                    let myInfoModel = MyInfoModel(
                        myNodeNum: decodedInfo.myInfo.myNodeNum,
                        hasGps: decodedInfo.myInfo.hasGps_p,
                        numBands: decodedInfo.myInfo.numBands,
                        maxChannels: decodedInfo.myInfo.maxChannels,
                        firmwareVersion: decodedInfo.myInfo.firmwareVersion,
                        messageTimeoutMsec: decodedInfo.myInfo.messageTimeoutMsec,
                        minAppVersion: decodedInfo.myInfo.minAppVersion)
                    
                    // Save it to the connected nodeInfo
                    if connectedPeripheral != nil {
                        connectedPeripheral.myInfo = myInfoModel
                        // Save it to the connected node
                        connectedNode = meshData.nodes.first(where: {$0.num == myInfoModel.id})
                        
                    }
                    // Since the data is from the device itself we save all myInfo objects since they are always the most update
                    if connectedNode != nil && connectedNode.myInfo == nil {
                        connectedNode.myInfo = myInfoModel
                        let nodeIndex = meshData.nodes.firstIndex(where: { $0.id == decodedInfo.myInfo.myNodeNum })
                        meshData.nodes.remove(at: nodeIndex!)
                        meshData.nodes.append(connectedNode)
                        meshData.save()
                        print("Saved a myInfo for \(decodedInfo.myInfo.myNodeNum)")                           // connectedNode.update(from: connectedNode.data)
                    }
                    meshData.save()
                }
                
                if decodedInfo.nodeInfo.num != 0 {
                    
                    print("Save a nodeInfo")

                    if meshData.nodes.contains(where: {$0.id == decodedInfo.nodeInfo.num}) {
                        
                        // Found a matching node lets update it
                        let nodeMatch = meshData.nodes.first(where: { $0.id == decodedInfo.nodeInfo.num })
                        if nodeMatch?.lastHeard ?? 0 < decodedInfo.nodeInfo.lastHeard {
                            // The data coming from the device is newer
                            
                            let nodeIndex = meshData.nodes.firstIndex(where: { $0.id == decodedInfo.nodeInfo.num })
                            meshData.nodes.remove(at: nodeIndex!)
                            meshData.save()
                        }
                        else {
                            
                            // Data is older than what the app already has
                            return
                        }
                    }

                    meshData.nodes.append(
                        NodeInfoModel(
                            num: decodedInfo.nodeInfo.num,
                            user: NodeInfoModel.User(
                                id: decodedInfo.nodeInfo.user.id,
                                longName: decodedInfo.nodeInfo.user.longName,
                                shortName: decodedInfo.nodeInfo.user.shortName,
                                //macaddr: decodedInfo.nodeInfo.user.macaddr,
                                hwModel: String(describing: decodedInfo.nodeInfo.user.hwModel)
                                    .uppercased()),
                            
                            position: NodeInfoModel.Position(
                                latitudeI: decodedInfo.nodeInfo.position.latitudeI,
                                longitudeI: decodedInfo.nodeInfo.position.longitudeI,
                                altitude: decodedInfo.nodeInfo.position.altitude,
                                batteryLevel: decodedInfo.nodeInfo.position.batteryLevel,
                                time: decodedInfo.nodeInfo.position.time),
                            
                            lastHeard: decodedInfo.nodeInfo.lastHeard,
                            snr: decodedInfo.nodeInfo.snr)
                    )
                    meshData.save()
            }
            // Handle assorted app packets
            if decodedInfo.packet.id  != 0 {
                
                print("Handle a Packet")
                do {
                    // Text Message App - Primary Broadcast Channel
                    if decodedInfo.packet.decoded.portnum == PortNum.textMessageApp {
                             
                        if let messageText = String(bytes: decodedInfo.packet.decoded.payload, encoding: .utf8) {
                            
                            print("Message Text: \(messageText)")

                            let fromUser = meshData.nodes.first(where: { $0.id == decodedInfo.packet.from })

                            var toUserLongName: String = "Broadcast"
                            var toUserShortName: String = "BC"

                            if decodedInfo.packet.to != broadcastNodeId {

                            let toUser = meshData.nodes.first(where: { $0.id == decodedInfo.packet.from })
                            toUserLongName = toUser?.user.longName ?? "Unknown"
                            toUserShortName = toUser?.user.shortName ?? "???"
                        }
                            
                        // Add the received message to the local messages list / file and save
                        messageData.messages.append(
                            MessageModel(
                                messageId: decodedInfo.packet.id,
                                messageTimeStamp: decodedInfo.packet.rxTime,
                                fromUserId: decodedInfo.packet.from,
                                toUserId: decodedInfo.packet.to,
                                fromUserLongName: fromUser?.user.longName ?? "Unknown",
                                toUserLongName: toUserLongName,
                                fromUserShortName: fromUser?.user.shortName ?? "???",
                                toUserShortName: toUserShortName,
                                receivedACK: decodedInfo.packet.decoded.wantResponse,
                                messagePayload: messageText,
                                direction: "IN")
                        )
                        messageData.save()
                            
                        // Create an iOS Notification for the received message and schedule it immediately
                        let manager = LocalNotificationManager()
                            
                        manager.notifications = [
                            Notification(
                                id: ("notification.id.\(decodedInfo.packet.id)"),
                                title: "\(fromUser?.user.longName ?? "Unknown")",
                                subtitle: "AKA \(fromUser?.user.shortName ?? "???")",
                                content: messageText)
                        ]
                        manager.schedule()
                    }
                }
                else if  decodedInfo.packet.decoded.portnum == PortNum.nodeinfoApp {

                    var updatedNode = meshData.nodes.first(where: {$0.id == decodedInfo.packet.from })

                    if updatedNode != nil {
                        updatedNode!.snr = decodedInfo.packet.rxSnr
                        updatedNode!.lastHeard = decodedInfo.packet.rxTime
                        //updatedNode!.update(from: updatedNode!.data)
                        let nodeIndex = meshData.nodes.firstIndex(where: { $0.id == decodedInfo.packet.from })
                        meshData.nodes.remove(at: nodeIndex!)
                        meshData.nodes.append(updatedNode!)
                        meshData.save()
                        print("Updated NodeInfo SNR and Time from Packet For: \(updatedNode!.user.longName)")
                    }
                }
                else if  decodedInfo.packet.decoded.portnum == PortNum.positionApp {

                    var updatedNode = meshData.nodes.first(where: {$0.id == decodedInfo.packet.from })

                    if updatedNode != nil {
                        updatedNode!.snr = decodedInfo.packet.rxSnr
                        updatedNode!.lastHeard = decodedInfo.packet.rxTime
                        //updatedNode!.update(from: updatedNode!.data)
                        let nodeIndex = meshData.nodes.firstIndex(where: { $0.id == decodedInfo.packet.from })
                        meshData.nodes.remove(at: nodeIndex!)
                        meshData.nodes.append(updatedNode!)
                        meshData.save()

                        print("Updated Position SNR and Time from Packet For: \(updatedNode!.user.longName)")
                    }
                        print("Postion Payload")
                        print(try decodedInfo.packet.jsonString())
                }
                         else if  decodedInfo.packet.decoded.portnum == PortNum.adminApp {
                             
                             print("Admin App Packet")
                             print(try decodedInfo.packet.jsonString())
                         }
                         else if  decodedInfo.packet.decoded.portnum == PortNum.routingApp {
                             
                             print("Routing App Packet")
                             //print(try decodedInfo.packet.jsonString())
                         }
                         else
                         {
                             print("Other App Packet")
                             print(try decodedInfo.packet.jsonString())
                         }
                        
                    } catch {
                        fatalError("Failed to decode json")
                    }
                }
                
                if decodedInfo.configCompleteID != 0 {
                    print("Config Complete: \(decodedInfo)")

                }
                
            default:
                print("Unhandled Characteristic UUID: \(characteristic.uuid)")
        }
        peripheral.readValue(for: FROMRADIO_characteristic)
    }
}
