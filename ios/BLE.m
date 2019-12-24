
/*
 
 Edited by Nuttawut Malee on 10.11.18
 Copyright (c) 2013 RedBearLab
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

#import "BLE.h"
#import "BLEDefines.h"

@implementation BLE

static const int MAX_BUFFER_LENGTH = 100;

/**
 * Default services.
 */
NSDictionary *redBearLabsService;
NSDictionary *adafruitService;
NSDictionary *lairdService;
NSDictionary *blueGigaService;
NSDictionary *rongtaService;
NSDictionary *posnetService;

/*----------------------------------------------------*/
#pragma mark - Lifecycle -
/*----------------------------------------------------*/

- (instancetype)init
{
    self = [super init];
    if (self) {
        _activePeripherals = [NSMutableDictionary dictionary];
        _scannedPeripherals = [NSMutableArray new];
        _peripheralsCountToStop = NSUIntegerMax;
        
        redBearLabsService = @{@"name": @"Red Bear Labs Service",
                               @"service": @RBL_SERVICE_UUID,
                               @"read": @RBL_CHAR_TX_UUID,
                               @"write": @RBL_CHAR_RX_UUID};
        
        adafruitService = @{@"name": @"Adafruit Service",
                            @"service": @ADAFRUIT_SERVICE_UUID,
                            @"read": @ADAFRUIT_CHAR_TX_UUID,
                            @"write": @ADAFRUIT_CHAR_RX_UUID};
        
        lairdService = @{@"name": @"Laird Service",
                         @"service": @LAIRD_SERVICE_UUID,
                         @"read": @LAIRD_CHAR_TX_UUID,
                         @"write": @LAIRD_CHAR_RX_UUID};
        
        blueGigaService = @{@"name": @"Blue Giga Service",
                            @"service": @ADAFRUIT_SERVICE_UUID,
                            @"read": @ADAFRUIT_CHAR_TX_UUID,
                            @"write": @ADAFRUIT_CHAR_RX_UUID};
        
        rongtaService = @{@"name": @"Rongta Service",
                          @"service": @RONGTA_SERVICE_UUID,
                          @"read": @RONGTA_CHAR_TX_UUID,
                          @"write": @RONGTA_CHAR_RX_UUID};
        
        posnetService = @{@"name": @"POSNET Service",
                          @"service": @POSNET_SERVICE_UUID,
                          @"read": @POSNET_CHAR_TX_UUID,
                          @"write": @POSNET_CHAR_RX_UUID};
        
        _bleServices = [self servicesArrayToDictionary:[self getDefaultServices]];

        _manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBCentralManagerOptionShowPowerAlertKey]];
    }
    return self;
}

+ (BLE *)sharedInstance
{
    static BLE *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[BLE alloc] init];
    });
    return _sharedInstance;
}

/*----------------------------------------------------*/
#pragma mark - Getter/Setter -
/*----------------------------------------------------*/

- (BOOL)isCentralReady
{
    return (self.manager.state == CBCentralManagerStatePoweredOn);;
}

- (NSArray *)peripherals
{
    // Sorting peripherals by RSSI values
    NSArray *sortedArray = [_scannedPeripherals sortedArrayUsingComparator:^NSComparisonResult(CBPeripheral *a, CBPeripheral *b) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return a.RSSI < b.RSSI;
#pragma clang diagnostic pop
    }];
    return sortedArray;
}

/*----------------------------------------------------*/
#pragma mark - KVO -
/*----------------------------------------------------*/

+ (NSSet *)keyPathsForValuesAffectingCentralReady
{
    return [NSSet setWithObject:@"cbCentralManagerState"];
}

+ (NSSet *)keyPathsForValuesAffectingCentralNotReadyReason
{
    return [NSSet setWithObject:@"cbCentralManagerState"];
}

/*----------------------------------------------------*/
#pragma mark - Public Methods -
/*----------------------------------------------------*/

- (NSMutableDictionary *)peripheralToDictionary:(CBPeripheral *)peripheral
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    NSString *uuid = peripheral.identifier.UUIDString;
    NSString *name = peripheral.name;
    NSNumber *rssi = peripheral.btsAdvertisementRSSI;
    
    [result setObject:uuid forKey:@"uuid"];
    [result setObject:uuid forKey:@"id"];
    
    if (!name) {
        name = [result objectForKey:@"uuid"];
    }
    
    [result setObject:name forKey:@"name"];
    
    if (rssi) {
        [result setObject:rssi forKey:@"rssi"];
    }
    
    return result;
}

- (void)readActivePeripheralRSSI:(NSString *)uuid
{
    NSMutableDictionary *dict = [self getFirstPeripheralDictionary:uuid];
    
    if (dict) {
        CBPeripheral *peripheral = [dict objectForKey:@"peripheral"];
        
        if (peripheral) {
            [peripheral readRSSI];
        }
    }
}

- (void)enableReadNotification:(CBPeripheral *)peripheral
{
    NSMutableDictionary *activePeripheral = [self.activePeripherals objectForKey:peripheral.identifier.UUIDString];
    
    if (!activePeripheral) {
        NSString *message = [NSString stringWithFormat:@"Could not find active peripheral with UUID %@", peripheral.identifier.UUIDString];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_peripheral" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    CBUUID *serviceUUID = [activePeripheral objectForKey:@"service"];
    CBService *service = [self findServiceFromUUID:serviceUUID peripheral:peripheral];
    
    if (!service) {
        NSString *message = [NSString stringWithFormat:@"Could not find service with UUID %@ on peripheral with UUID %@",
                             [self CBUUIDToString:serviceUUID],
                             peripheral.identifier.UUIDString];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_service" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    CBUUID *readUUID = [activePeripheral objectForKey:@"read"];
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:readUUID service:service];
    
    if (!characteristic) {
        NSString *message = [NSString stringWithFormat:
                             @"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                             [self CBUUIDToString:readUUID],
                             [self CBUUIDToString:serviceUUID],
                             peripheral.identifier.UUIDString];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_characteristic" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
}

- (BOOL)isConnected:(NSString *)uuid
{
    NSMutableDictionary *dict = [self getFirstPeripheralDictionary:uuid];
    
    if (dict) {
        return (BOOL)[dict valueForKey:@"connected"];
    }
    
    return FALSE;
}

- (void)read:(NSString *)uuid
{
    NSMutableDictionary *activePeripheral = [self getFirstPeripheralDictionary:uuid];
    
    if (!activePeripheral) {
        NSString *message = [NSString stringWithFormat:@"Could not find active peripheral with UUID %@", uuid];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_peripheral" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    CBPeripheral *peripheral = [activePeripheral objectForKey:@"peripheral"];

    if (!peripheral) {
        NSString *message = [NSString stringWithFormat:@"Could not find active peripheral with UUID %@", uuid];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_peripheral" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    CBUUID *serviceUUID = [activePeripheral objectForKey:@"service"];
    CBService *service = [self findServiceFromUUID:serviceUUID peripheral:peripheral];

    if (!service) {
        NSString *message = [NSString stringWithFormat:
                             @"Could not find service with UUID %@ on peripheral with UUID %@",
                             [self CBUUIDToString:serviceUUID],
                             peripheral.identifier.UUIDString];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_service" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    CBUUID *readUUID = [activePeripheral objectForKey:@"read"];
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:readUUID service:service];
    
    if (!characteristic) {
        NSString *message = [NSString stringWithFormat:
                             @"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                             [self CBUUIDToString:readUUID],
                             [self CBUUIDToString:serviceUUID],
                             peripheral.identifier.UUIDString];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_characteristic" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    [peripheral readValueForCharacteristic:characteristic];
}

- (void)write:(NSString *)uuid data:(NSData *)data
{
    NSMutableDictionary *activePeripheral = [self getFirstPeripheralDictionary:uuid];
    
    if (!activePeripheral) {
        NSString *message = [NSString stringWithFormat:@"Could not find active peripheral with UUID %@", uuid];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_peripheral" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }

    CBPeripheral *peripheral = [activePeripheral objectForKey:@"peripheral"];

    if (!peripheral) {
        NSString *message = [NSString stringWithFormat:@"Could not find active peripheral with UUID %@", uuid];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_peripheral" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    NSLog(@"Write data to peripheral with UUID %@", uuid);
    
    NSInteger dataLength = data.length;
    NSData *buffer;
    CBUUID *serviceUUID = [activePeripheral objectForKey:@"service"];
    CBUUID *writeUUID = [activePeripheral objectForKey:@"write"];

    for (int i = 0; i < dataLength; i += MAX_BUFFER_LENGTH) {
        NSInteger remainLength = dataLength - i;
        NSInteger bufferLength = (remainLength > MAX_BUFFER_LENGTH) ? MAX_BUFFER_LENGTH : remainLength;
        buffer = [data subdataWithRange:NSMakeRange(i, bufferLength)];
        
        NSLog(@"Buffer data %li %i %@", (long)remainLength, i, [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding]);
        
        [self writeValue:serviceUUID characteristicUUID:writeUUID peripheral:peripheral data:buffer];
    }
}

- (void)scanForPeripheralsByInterval:(NSUInteger)interval completion:(CentralManagerDiscoverPeripheralsCallback)callback
{
    if (!self.isCentralReady) {
        NSString *message = [NSString stringWithFormat:
                             @"CoreBluetooth not correctly initialized! State = %ld (%@)",
                             (long)self.manager.state,
                             [self centralManagerStateToString:self.manager.state]];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_bluetooth_initialized" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        callback([NSMutableArray new]);
        
        return;
    }
    
    self.scanBlock = callback;
    
    [self scanForPeripheralsByServices];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(stopScanForPeripherals)
                                               object:nil];
    
    [self performSelector:@selector(stopScanForPeripherals)
               withObject:nil
               afterDelay:interval];
}

- (void)stopScanForPeripherals
{
    [self.manager stopScan];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(stopScanForPeripherals)
                                               object:nil];
    
    NSLog(@"Stopped Scanning");
    NSLog(@"Known peripherals : %lu", (unsigned long)[self.peripherals count]);
    [self printKnownPeripherals];
    
    if (self.scanBlock) {
        self.scanBlock(self.scannedPeripherals);
    }
    
    self.scanBlock = nil;
}

- (void)connectToPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Connecting to peripheral with UUID : %@", peripheral.identifier.UUIDString);
    
    CBPeripheral *activePeripheral = [peripheral copy];
    
    activePeripheral.delegate = self;
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    [dict setValue:[NSNumber numberWithBool:FALSE] forKey:@"connected"];
    [dict setObject:activePeripheral forKey:@"peripheral"];
    [dict setObject:@"" forKey:@"service"];
    [dict setObject:@"" forKey:@"read"];
    [dict setObject:@"" forKey:@"write"];

    if ([self.activePeripherals count] <= 0) {
        [dict setValue:[NSNumber numberWithBool:TRUE] forKey:@"first"];
    } else {
        [dict setValue:[NSNumber numberWithBool:FALSE] forKey:@"first"];
    }
    
    [self.activePeripherals setObject:dict forKey:activePeripheral.identifier.UUIDString];

    [self.manager connectPeripheral:activePeripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
}

- (void)disconnectFromPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Disconnecting peripheral with UUID : %@", peripheral.identifier.UUIDString);
    
    [self.manager cancelPeripheralConnection:peripheral];
}

- (void)centralManagerSetup
{
    self.manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBCentralManagerOptionShowPowerAlertKey]];
}

- (CBPeripheral *)getActivePeripheral:(NSString *)uuid
{
    NSMutableDictionary *dict = [self getFirstPeripheralDictionary:uuid];
    
    if (dict) {
        return (CBPeripheral *)[dict objectForKey:@"peripheral"];
    }
    
    return nil;
}

- (NSArray *)getDefaultServices
{
    return @[redBearLabsService, adafruitService, lairdService, blueGigaService, rongtaService, posnetService];
}

- (NSArray *)includeDefaultServices:(NSArray *)services
{
    NSMutableSet *mergedSet = [NSMutableSet setWithArray:services];
    [mergedSet unionSet:[NSSet setWithArray:[self getDefaultServices]]];
    NSArray *merged = [mergedSet allObjects];
    return merged;
}

- (BOOL)validateServices:(NSArray *)services
{
    if ([services isKindOfClass:[NSNull class]] | ([services count] <= 0) | (services == nil)) {
        return TRUE;
    }
    
    for (NSDictionary *service in services) {
        NSString *s = [service objectForKey:@"service"];
        NSString *r = [service objectForKey:@"read"];
        NSString *w = [service objectForKey:@"write"];
        
        if ([self validateCBUUIDString:s] & [self validateCBUUIDString:r] & [self validateCBUUIDString:w]) {
            continue;
        }
        
        return FALSE;
    }
    
    return TRUE;
}

- (NSDictionary *)servicesArrayToDictionary:(NSArray *)services
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    if ([services count] > 0) {
        for (NSDictionary *s in services) {
            NSMutableDictionary *obj = [[NSMutableDictionary alloc] initWithDictionary:s];
            NSString *service = [obj objectForKey:@"service"];
            [dict setObject:obj forKey:service];
        }
    }
    
    return dict;
}

- (NSArray *)servicesDictionaryToArray:(NSDictionary *)services
{
    NSMutableArray *array = [NSMutableArray array];
    
    if ([services count] > 0) {
        NSArray *keys = [services allKeys];
        
        for (NSString *key in keys) {
            NSMutableDictionary *service = [[NSMutableDictionary alloc] initWithDictionary:[services objectForKey:key]];
            [service setObject:key forKey:@"service"];
            [array addObject:service];
        }
    }
    
    return array;
}

/*----------------------------------------------------*/
#pragma mark - Private Methods -
/*----------------------------------------------------*/

-(void)scanForPeripheralsByServices
{
    // Clear all peripherals
    [self.scannedPeripherals removeAllObjects];
    
#if TARGET_OS_IPHONE
    NSMutableArray *services = [[NSMutableArray alloc] init];

    if ([self.bleServices count] > 0) {
        NSArray *keys = [self.bleServices allKeys];
        
        for (NSString *key in keys) {
            [services addObject:[CBUUID UUIDWithString:key]];
        }
    }

    [self.manager scanForPeripheralsWithServices:services options:nil];
#else
    [self.manager scanForPeripheralsWithServices:nil options:nil];
#endif
    
    NSLog(@"Scan for peripherals with services");
}

- (NSString *)centralManagerStateToString:(int)state
{
    switch(state) {
        case CBCentralManagerStateUnknown:
            return @"State unknown (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateResetting:
            return @"State resetting (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateUnsupported:
            return @"State BLE unsupported (CBCentralManagerStateResetting)";
        case CBCentralManagerStateUnauthorized:
            return @"State unauthorized (CBCentralManagerStateUnauthorized)";
        case CBCentralManagerStatePoweredOff:
            return @"State BLE powered off (CBCentralManagerStatePoweredOff)";
        case CBCentralManagerStatePoweredOn:
            return @"State powered up and ready (CBCentralManagerStatePoweredOn)";
        default:
            return @"State unknown";
    }
    
    return @"Unknown state";
}

- (void)writeValue:(CBUUID *)serviceUUID
characteristicUUID:(CBUUID *)characteristicUUID
        peripheral:(CBPeripheral *)peripheral
              data:(NSData *)data
{
    CBService *service = [self findServiceFromUUID:serviceUUID peripheral:peripheral];
    
    if (!service) {
        NSString *message = [NSString stringWithFormat:@"Could not find service with UUID %@ on peripheral with UUID %@",
                             [self CBUUIDToString:serviceUUID],
                             peripheral.identifier.UUIDString];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_service" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service];
    
    if (!characteristic) {
        NSString *message = [NSString stringWithFormat:
                             @"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                             [self CBUUIDToString:characteristicUUID],
                             [self CBUUIDToString:serviceUUID],
                             peripheral.identifier.UUIDString];
        
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_characteristic" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    NSLog(@"Write value in ble.m\n");
    NSLog(@"Buffer data %li", (long)data.length);
    
    if ((characteristic.properties & CBCharacteristicPropertyWrite) == CBCharacteristicPropertyWrite) {
        [peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
    } else if ((characteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) == CBCharacteristicPropertyWriteWithoutResponse) {
        [peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
    }
}

- (BOOL)validateCBUUIDString:(NSString *)CBUUIDString
{
    if ([CBUUIDString isKindOfClass:[NSNull class]] | [CBUUIDString isEqualToString:@""] | (CBUUIDString == nil)) {
        return FALSE;
    }
    
    return (BOOL)[CBUUID UUIDWithString:CBUUIDString];
}

- (CBCharacteristic *)findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service
{
    for (int i = 0; i < service.characteristics.count; i++) {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        
        if ([self compareCBUUID:c.UUID UUID2:UUID]) {
            return c;
        }
    }
    
    return nil;
}

- (CBService *)findServiceFromUUID:(CBUUID *)UUID peripheral:(CBPeripheral *)peripheral
{
    for (int i = 0; i < peripheral.services.count; i++) {
        CBService *s = [peripheral.services objectAtIndex:i];
        
        if ([self compareCBUUID:s.UUID UUID2:UUID]) {
            return s;
        }
    }
    
    return nil;
}

- (UInt16)swap:(UInt16)s
{
    UInt16 temp = s << 8;
    temp |= (s >> 8);
    return temp;
}

- (NSString *)CBUUIDToString:(CBUUID *)UUID
{
    NSData *data = UUID.data;
    
    if ([data length] == 2) {
        const unsigned char *tokenBytes = [data bytes];
        return [NSString stringWithFormat:@"%02x%02x", tokenBytes[0], tokenBytes[1]];
    } else if ([data length] == 16) {
        NSUUID* nsuuid = [[NSUUID alloc] initWithUUIDBytes:[data bytes]];
        return [nsuuid UUIDString];
    }
    
    return [UUID description];
}

- (UInt16)CBUUIDToInt:(CBUUID *)UUID
{
    char b[16];
    [UUID.data getBytes:b length:UUID.data.length];
    return ((b[0] << 8) | b[1]);
}

- (int)compareCBUUID:(CBUUID *)UUID1 UUID2:(CBUUID *)UUID2
{
    char b1[16];
    char b2[16];
    [UUID1.data getBytes:b1 length:UUID1.data.length];
    [UUID2.data getBytes:b2 length:UUID2.data.length];
    
    if (memcmp(b1, b2, UUID1.data.length) == 0) {
        return 1;
    } else {
        return 0;
    }
}

- (int)compareCBUUIDToInt:(CBUUID *)UUID1 UUID2:(UInt16)UUID2
{
    char b1[16];
    [UUID1.data getBytes:b1 length:UUID1.data.length];
    
    UInt16 b2 = [self swap:UUID2];
    
    if (memcmp(b1, (char *)&b2, 2) == 0) {
        return 1;
    } else {
        return 0;
    }
}

- (BOOL)UUIDSAreEqual:(NSUUID *)UUID1 UUID2:(NSUUID *)UUID2
{
    if ([UUID1.UUIDString isEqualToString:UUID2.UUIDString]) {
        return TRUE;
    } else {
        return FALSE;
    }
}

- (CBUUID *)IntToCBUUID:(UInt16)UUID
{
    char t[16];
    t[0] = ((UUID >> 8) & 0xff); t[1] = (UUID & 0xff);
    NSData *data = [[NSData alloc] initWithBytes:t length:16];
    return [CBUUID UUIDWithData:data];
}

#if TARGET_OS_IPHONE
//-- no need for iOS
#else
- (BOOL)isLECapableHardware
{
    NSString *state = @"";
    
    switch ([self.manager state]) {
        case CBCentralManagerStateUnsupported:
            state = @"The platform/hardware doesn't support Bluetooth Low Energy.";
            break;
        case CBCentralManagerStateUnauthorized:
            state = @"The app is not authorized to use Bluetooth Low Energy.";
            break;
        case CBCentralManagerStatePoweredOff:
            state = @"Bluetooth is currently powered off.";
            break;
        case CBCentralManagerStatePoweredOn:
            return TRUE;
        case CBCentralManagerStateUnknown:
        default:
            return FALSE;
    }
    
    NSLog(@"Central manager state: %@", state);
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:state];
    [alert addButtonWithTitle:@"OK"];
    [alert setIcon:[[NSImage alloc] initWithContentsOfFile:@"AppIcon"]];
    [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:nil contextInfo:nil];
    
    return FALSE;
}
#endif

- (void)printKnownPeripherals
{
    NSLog(@"List of currently known peripherals :");
    
    for (int i = 0; i < self.peripherals.count; i++) {
        CBPeripheral *peripheral = [self.peripherals objectAtIndex:i];
        NSLog(@"%d  |  %@", i, peripheral.identifier.UUIDString);
        [self printPeripheralInfo:peripheral];
    }
}

- (void)printPeripheralInfo:(CBPeripheral*)peripheral
{
    NSLog(@"------------------------------------");
    NSLog(@"Peripheral Info :");
    NSLog(@"UUID : %@", peripheral.identifier.UUIDString);
    NSLog(@"Name : %@", peripheral.name);
    NSLog(@"-------------------------------------");
}

- (NSMutableDictionary *)getFirstPeripheralDictionary:(NSString *)uuid
{
    if (([uuid length] <= 0) | [uuid isEqualToString:@""] | [uuid isKindOfClass:[NSNull class]] | (uuid == nil)) {
        for (NSString *key in self.activePeripherals) {
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[self.activePeripherals objectForKey:key]];

            if (!dict) {
                continue;
            }
            
            if ((BOOL)[dict valueForKey:@"first"]) {
                return dict;
            }
        }
        
        return nil;
    }
    
    if ([[self.activePeripherals allKeys] containsObject:uuid]) {
        return [self.activePeripherals objectForKey:uuid];
    }

    return nil;
}

/*----------------------------------------------------*/
#pragma mark - Central Manager Delegate -
/*----------------------------------------------------*/

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    self.cbCentralManagerState = (CBCentralManagerState)central.state;
    
#if TARGET_OS_IPHONE
    NSString *state = [self centralManagerStateToString:central.state];
    NSLog(@"Status of CoreBluetooth central manager changed %ld (%@)", (long)central.state, state);
    
    if (self.isCentralReady) {
        [[self delegate] didPowerOn];
    } else {
        [[self delegate] didPowerOff];
        
        if ([self.activePeripherals count] > 0) {
            for (NSString *key in self.activePeripherals) {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[self.activePeripherals objectForKey:key]];

                if (!dict) {
                    continue;
                }
                
                if ((BOOL)[dict valueForKey:@"connected"]) {
                    CBPeripheral *peripheral = [dict objectForKey:@"peripheral"];
                    [[self delegate] didConnectionLost:peripheral];
                }
            }
            
        }
    }
#else
    [self isLECapableHardware];
#endif
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Connected to %@ successful", peripheral.identifier.UUIDString);

    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[self.activePeripherals objectForKey:peripheral.identifier.UUIDString]];

    if (dict) {
        [dict setObject:peripheral forKey:@"peripheral"];
        [self.activePeripherals setObject:dict forKey:peripheral.identifier.UUIDString];
    }

    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[self.activePeripherals objectForKey:peripheral.identifier.UUIDString]];

    if (dict) {
        CBPeripheral *activePeripheral = [dict objectForKey:@"peripheral"];
        activePeripheral.delegate = nil;
        [self.activePeripherals removeObjectForKey:peripheral.identifier.UUIDString];
    }
    
    NSLog(@"Failed to connect to %@", peripheral.identifier.UUIDString);

    if (error) {
        NSString *message = [error localizedDescription];
        NSLog(@"%@", message);
        [[self delegate] didError:error];
    }

    [[self delegate] didFailToConnect:peripheral];
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                error:(NSError *)error
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[self.activePeripherals objectForKey:peripheral.identifier.UUIDString]];

    if (dict) {
        CBPeripheral *activePeripheral = [dict objectForKey:@"peripheral"];
        activePeripheral.delegate = nil;
        [self.activePeripherals removeObjectForKey:peripheral.identifier.UUIDString];
    }
    
    NSLog(@"Disconnected to %@ successful", peripheral.identifier.UUIDString);

    if (error) {
        NSString *message = [error localizedDescription];
        NSLog(@"%@", message);
        [[self delegate] didError:error];
    }
    
    [[self delegate] didConnectionLost:peripheral];
}

-(void)centralManager:(CBCentralManager *)central
didDiscoverPeripheral:(CBPeripheral *)peripheral
    advertisementData:(NSDictionary *)advertisementData
                 RSSI:(NSNumber *)RSSI
{
    if (!self.scannedPeripherals) {
        // Initiate peripherals with a new peripheral
        self.scannedPeripherals = [[NSMutableArray alloc] initWithObjects:peripheral, nil];
    } else {
        // Replace a duplicate peripheral
        for (int i = 0; i < self.scannedPeripherals.count; i++) {
            CBPeripheral *p = [self.scannedPeripherals objectAtIndex:i];
            [p bts_setAdvertisementData:advertisementData RSSI:RSSI];
            
            if ((p.identifier == NULL) || (peripheral.identifier) == NULL) {
                continue;
            }
            
            if ([self UUIDSAreEqual:p.identifier UUID2:peripheral.identifier]) {
                [self.scannedPeripherals replaceObjectAtIndex:i withObject:peripheral];
                NSLog(@"Updating duplicate UUID (%@) peripheral", peripheral.identifier.UUIDString);
                return;
            }
        }
        
        // Add a new peripheral
        [self.scannedPeripherals addObject:peripheral];
        NSLog(@"Adding new UUID (%@) peripheral", peripheral.identifier.UUIDString);
    }
    
    NSLog(@"didDiscoverPeripheral");
    
    if ([self.scannedPeripherals count] >= self.peripheralsCountToStop) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(stopScanForPeripherals)
                                                   object:nil];
        [self stopScanForPeripherals];
    }
}

/*----------------------------------------------------*/
#pragma mark - Peripheral Delegate -
/*----------------------------------------------------*/

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
             error:(NSError *)error
{
    if (error) {
        NSString *message = @"Characteristic discovery unsuccessful!";
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_characteristic_discovery" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    NSLog(@"Characteristics of service with UUID : %@ found\n", [self CBUUIDToString:service.UUID]);
    
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[self.activePeripherals objectForKey:peripheral.identifier.UUIDString]];
    
    if (dict) {
        CBPeripheral *activePeripheral = [dict objectForKey:@"peripheral"];
        
        if (activePeripheral) {
            [self enableReadNotification:activePeripheral];
            [[self delegate] didConnect:activePeripheral];
            [dict setValue:[NSNumber numberWithBool:TRUE] forKey:@"connected"];
            [self.activePeripherals setObject:dict forKey:peripheral.identifier.UUIDString];
            
            NSLog(@"Connection with %@ completed", peripheral.identifier.UUIDString);
            
            return;
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error
{
    if (error) {
        NSString *message = @"Update value for characteristic unsuccessful!";
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_characteristic_update" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    NSMutableDictionary *activePeripheral = [self getFirstPeripheralDictionary:peripheral.identifier.UUIDString];
    
    if (!activePeripheral) {
        NSString *message = [NSString stringWithFormat:@"Could not find active peripheral with UUID %@", peripheral.identifier.UUIDString];
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_peripheral" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    static unsigned char buffer[512];
    NSInteger dataLength;
    CBPeripheral *readUUID = [activePeripheral objectForKey:@"read"];

    if ([characteristic.UUID isEqual:readUUID]) {
        dataLength = characteristic.value.length;
        [characteristic.value getBytes:buffer length:dataLength];
        [[self delegate] didReceiveData:peripheral.identifier.UUIDString data:buffer length:dataLength];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSString *message = @"Service discovery unsuccessful!";
        NSLog(@"%@", message);
        
        NSError *error = [NSError errorWithDomain:@"no_service_discovery" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [[self delegate] didError:error];
        
        return;
    }
    
    NSLog(@"Service discovery for %@ successful", peripheral.identifier.UUIDString);

    NSMutableDictionary *activePeripheral = [[NSMutableDictionary alloc] initWithDictionary:[self.activePeripherals objectForKey:peripheral.identifier.UUIDString]];

    for (CBService *service in peripheral.services) {
        NSString *uuid = [self CBUUIDToString:service.UUID];
        NSDictionary *dict = [self.bleServices objectForKey:uuid];

        if (dict) {
            NSString *name = [dict objectForKey:@"name"];
            
            if (name) {
                NSLog(@"Discovered service : %@", name);
            }
            
            CBUUID *readCharacteristic = [CBUUID UUIDWithString:[dict objectForKey:@"read"]];
            CBUUID *writeCharacteristic = [CBUUID UUIDWithString:[dict objectForKey:@"write"]];
            
            if (activePeripheral) {
                [activePeripheral setObject:service.UUID forKey:@"service"];
                [activePeripheral setObject:readCharacteristic forKey:@"read"];
                [activePeripheral setObject:writeCharacteristic forKey:@"write"];
                [self.activePeripherals setObject:activePeripheral forKey:peripheral.identifier.UUIDString];
            }
            
            [peripheral discoverCharacteristics:@[readCharacteristic, writeCharacteristic] forService:service];
            
            break;
        }
    }
}

@end
