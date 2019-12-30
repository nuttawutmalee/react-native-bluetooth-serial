/*
 
 Created by Nuttawut Malee on 10.11.18.
 Copyright © 2016 Nuttawut Malee. All rights reserved.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

#import "RCTBluetoothSerial.h"

@implementation RCTBluetoothSerial


RCT_EXPORT_MODULE();

@synthesize bridge = _bridge;

/*----------------------------------------------------*/
#pragma mark - Lifecycle -
/*----------------------------------------------------*/

- (instancetype)init
{
    self = [super init];
    if (self) {
        _buffers = [NSMutableDictionary dictionary];
        _delimiters = [NSMutableDictionary dictionary];
        _connectionPromises = [NSMutableDictionary dictionary];
        _doesHaveListeners = FALSE;
        
        _ble = [BLE sharedInstance];
        [_ble setDelegate:self];
    }
    return self;
}

- (dispatch_queue_t)methodQueue
{
    // run all module methods in main thread
    // if we don't no timer callbacks got called
    return dispatch_get_main_queue();
}

// + (BOOL)requiresMainQueueSetup
// {
//     return NO;
// }

/*----------------------------------------------------*/
#pragma mark - React Native Methods Available in Javascript -
/*----------------------------------------------------*/

- (NSDictionary *)constantsToExport
{
    return @{@"DEFAULT_SERVICES":[self.ble getDefaultServices]};
}

RCT_EXPORT_METHOD(requestEnable:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Apple does not support programmatically requesting enable central manager
    NSString *message = @"Require enable bluetooth service; Apple does not support this function";
    NSError *error = [NSError errorWithDomain:@"no_support" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
    [self onError:message];
    reject(@"", message, error);
}

RCT_EXPORT_METHOD(enable:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Apple does not support programmatically enabling central manager
    NSString *message = @"Enable bluetooth service; Apple does not support this function";
    NSError *error = [NSError errorWithDomain:@"no_support" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
    [self onError:message];
    reject(@"", message, error);
}

RCT_EXPORT_METHOD(disable:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Apple does not support programmatically disabling central manager
    NSString *message = @"Disable bluetooth service; Apple does not support this function";
    NSError *error = [NSError errorWithDomain:@"no_support" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
    [self onError:message];
    reject(@"", message, error);
}

RCT_EXPORT_METHOD(isEnabled:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Short delay so CBCentralManger can spin up bluetooth
    [NSTimer scheduledTimerWithTimeInterval:(float)0.2
                                     target:self
                                   selector:@selector(bluetoothPowerStateTimer:)
                                   userInfo:resolve
                                    repeats:NO];
}

RCT_EXPORT_METHOD(list:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"List peripherals");
    
    [self.ble scanForPeripheralsByInterval:(float)3.0 completion:^(NSMutableArray *peripherals) {
        NSMutableArray *result = [self getPeripheralList:peripherals];
        resolve(result);
    }];
}

RCT_EXPORT_METHOD(listUnpaired:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Apple does not support programmatically enabling central manager
    NSString *message = @"List unpaired peripherals; Apple does not support this function";
    [self onError:message];
    resolve([NSMutableArray new]);
}

RCT_EXPORT_METHOD(cancelDiscovery:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Cancel discovery called");
    [self.ble stopScanForPeripherals];
    resolve((id)kCFBooleanTrue);
}

RCT_EXPORT_METHOD(pairDevice:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Apple does not support programmatically pairing.
    NSString *message = @"Pair to peripheral (UUID : %@); Apple does not support this function";
    NSError *error = [NSError errorWithDomain:@"no_support" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
    [self onError:message];
    reject(@"", message, error);
}

RCT_EXPORT_METHOD(unpairDevice:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Apple does not support programmatically unpairing.
    NSString *message = @"Unpair to peripheral (UUID : %@); Apple does not support this function";
    NSError *error = [NSError errorWithDomain:@"no_support" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
    [self onError:message];
    reject(@"", message, error);
}

RCT_EXPORT_METHOD(connect:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Connect to peripheral");
    
    // Disconnect from selected active peripheral
    NSMutableDictionary *dict = [self.ble.activePeripherals objectForKey:uuid];
    
    if (dict) {
        CBPeripheral *peripheral = [dict objectForKey:@"peripheral"];
        
        if (peripheral) {
            if (peripheral.state == CBPeripheralStateConnected) {
                [self.ble disconnectFromPeripheral:peripheral];
            }
        }
    }
    
    NSMutableDictionary *promises = [NSMutableDictionary dictionary];
    [promises setObject:resolve forKey:@"resolver"];
    [promises setObject:reject forKey:@"rejector"];
    
    [self.connectionPromises setObject:promises forKey:uuid];

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(findBLEPeripheralByUUID:completion:)
                                               object:nil];
    
    [self findBLEPeripheralByUUID:uuid completion:^(CBPeripheral *peripheral) {
        if (peripheral) {
            NSLog(@"Connecting to device (UUID : %@)", peripheral.identifier.UUIDString);

            if (![[self.delimiters allKeys] containsObject:peripheral.identifier.UUIDString]) {
                [self.delimiters setValue:[[NSMutableString alloc] initWithString:@""] forKey:peripheral.identifier.UUIDString];
            }
            
            if (![[self.buffers allKeys] containsObject:peripheral.identifier.UUIDString]) {
                [self.buffers setValue:[[NSMutableString alloc] init] forKey:peripheral.identifier.UUIDString];
            }

            [self.ble connectToPeripheral:peripheral];
        } else {
            NSString *message = [NSString stringWithFormat:@"Could not find peripheral %@.", uuid];
            NSError *err = [NSError errorWithDomain:@"wrong_uuid" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
            [self onError:message];
            reject(@"wrong_uuid", message, err);
        }
    }];
}

RCT_EXPORT_METHOD(disconnect:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Disconnect from peripheral");
    
    CBPeripheral *activePeripheral = [self.ble getActivePeripheral:uuid];
    
    // Disconnect from selected active peripheral
    if (activePeripheral) {
        if (activePeripheral.state == CBPeripheralStateConnected) {
            [self.ble disconnectFromPeripheral:activePeripheral];
        }
    }

    resolve((id)kCFBooleanTrue);
}

RCT_EXPORT_METHOD(disconnectAll:(RCTPromiseResolveBlock)resolve rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Disconnect from all peripherals");
    
    NSMutableDictionary *peripherals = [[NSMutableDictionary alloc] initWithDictionary:self.ble.activePeripherals];
    
    if ([peripherals count] > 0) {
        NSArray *keys = [peripherals allKeys];
        
        for (NSString *key in keys) {
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[peripherals objectForKey:key]];
            
            if (dict) {
                CBPeripheral *p = [dict objectForKey:@"peripheral"];
                
                if (p) {
                    if (p.state == CBPeripheralStateConnected) {
                        [self.ble disconnectFromPeripheral:p];
                    }
                }
            }
        }
    }

    resolve((id)kCFBooleanTrue);
}

RCT_EXPORT_METHOD(isConnected:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    if ([self.ble isConnected:uuid]) {
        resolve((id)kCFBooleanTrue);
    } else {
        resolve((id)kCFBooleanFalse);
    }
}

RCT_EXPORT_METHOD(withDelimiter:(NSString *)delimiter
                  uuid:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSMutableString *deviceUUID = nil;

    if (![delimiter isKindOfClass:[NSNull class]] | (uuid == nil)) {
        NSMutableString *newDelimiter = [[NSMutableString alloc] initWithString:delimiter];
        NSLog(@"Set delimiter to %@ for UUID : %@", newDelimiter, uuid);
        
        if ([uuid isKindOfClass:[NSNull class]] | (uuid == nil)) {
            CBPeripheral *activePeripheral = [self.ble getActivePeripheral:uuid];
            
            if (activePeripheral) {
                [self.delimiters setValue:newDelimiter forKey:activePeripheral.identifier.UUIDString];
                [deviceUUID setString:activePeripheral.identifier.UUIDString];
            }
        } else {
            [self.delimiters setValue:newDelimiter forKey:uuid];
            [deviceUUID setString:uuid];
        }
    }
    
    resolve(deviceUUID);
}

RCT_EXPORT_METHOD(clear:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSMutableString *activeUUID = nil;
    
    if ([uuid isKindOfClass:[NSNull class]] | (uuid == nil)) {
        CBPeripheral *activePeripheral = [self.ble getActivePeripheral:uuid];
        
        if (activePeripheral) {
            [activeUUID setString:activePeripheral.identifier.UUIDString];
        }
    } else {
        [activeUUID setString:uuid];
    }
    
    if ([[self.buffers allKeys] containsObject:activeUUID]) {
        NSMutableString *buffer = [self.buffers valueForKey:activeUUID];
        long end = [buffer length] - 1;
        NSRange truncate = NSMakeRange(0, end);
        [buffer deleteCharactersInRange:truncate];
        [self.buffers setValue:buffer forKey:activeUUID];
    }

    resolve((id)kCFBooleanTrue);
}

RCT_EXPORT_METHOD(available:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSMutableString *activeUUID = nil;
    
    if ([uuid isKindOfClass:[NSNull class]] | (uuid == nil)) {
        CBPeripheral *activePeripheral = [self.ble getActivePeripheral:uuid];
        
        if (activePeripheral) {
            [activeUUID setString:activePeripheral.identifier.UUIDString];
        }
    } else {
        [activeUUID setString:uuid];
    }

    NSNumber *bufferLength = 0;
    
    if ([[self.buffers allKeys] containsObject:activeUUID]) {
        NSMutableString *buffer = [self.buffers valueForKey:uuid];
        bufferLength = [NSNumber numberWithInteger:[buffer length]];
    }

    resolve(bufferLength);
}

RCT_EXPORT_METHOD(setAdapterName:(NSString *)name
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    // Apple does not support programmatically adapter name setter.
    NSString *message = @"Cannot set adapter name in iOS";
    NSError *error = [NSError errorWithDomain:@"no_support" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
    [self onError:message];
    reject(@"", message, error);
}

RCT_EXPORT_METHOD(setServices:(NSArray *)services
                  includeDefaultServices:(BOOL)includeDefault
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    if ([self.ble validateServices:services]) {
        NSMutableArray *mutableServices = [[NSMutableArray alloc] initWithArray:services];

        if (includeDefault) {
            mutableServices = [[NSMutableArray alloc] initWithArray:[self.ble includeDefaultServices:mutableServices]];
        }
        
        [self.ble setBleServices:[self.ble servicesArrayToDictionary:mutableServices]];
        
        NSArray *services = [self.ble servicesDictionaryToArray:self.ble.bleServices];
        resolve(services);
    } else {
        NSString *message = @"Invalid array of service objects";
        NSError *error = [NSError errorWithDomain:@"invalid_parameter" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
        [self onError:message];
        reject(@"", message, error);
    }
}

RCT_EXPORT_METHOD(getServices:(RCTPromiseResolveBlock)resolve rejector:(RCTPromiseRejectBlock)reject)
{
    NSArray *services = [self.ble servicesDictionaryToArray:self.ble.bleServices];
    resolve(services);
}

RCT_EXPORT_METHOD(restoreServices:(RCTPromiseResolveBlock)resolve rejector:(RCTPromiseRejectBlock)reject)
{
    [self.ble setBleServices:[self.ble servicesArrayToDictionary:[self.ble getDefaultServices]]];
    NSArray *services = [self.ble servicesDictionaryToArray:self.ble.bleServices];
    resolve(services);
}

RCT_EXPORT_METHOD(writeToDevice:(NSString *)message
                  uuid:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Write to device : %@", message);

    NSData *data = [[NSData alloc] initWithBase64EncodedString:message options:NSDataBase64DecodingIgnoreUnknownCharacters];

    if ([data length] > 0) {
        [self.ble write:uuid data:data];
    } else {
        NSLog(@"Data was null");
    }

    resolve((id)kCFBooleanTrue);
}

RCT_EXPORT_METHOD(readFromDevice:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Read from active device");
    NSString *message = @"";
    
    NSMutableString *activeUUID = nil;
    
    if ([uuid isKindOfClass:[NSNull class]] | (uuid == nil)) {
        CBPeripheral *activePeripheral = [self.ble getActivePeripheral:uuid];
        
        if (activePeripheral) {
            [activeUUID setString:activePeripheral.identifier.UUIDString];
        }
    } else {
        [activeUUID setString:uuid];
    }

    if ([[self.buffers allKeys] containsObject:activeUUID]) {
        NSMutableString *buffer = [self.buffers valueForKey:activeUUID];
        long end = [buffer length] - 1;
        message = [buffer substringToIndex:end];
        NSRange entireString = NSMakeRange(0, end);
        [buffer deleteCharactersInRange:entireString];
        [self.buffers setValue:buffer forKey:activeUUID];
    }

    resolve(message);
}

RCT_EXPORT_METHOD(readUntilDelimiter:(NSString *)delimiter
                  uuid:(NSString *)uuid
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejector:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Read until delimiter : %@", delimiter);
    NSString *message = [self readUntil:uuid delimiter:delimiter];
    resolve(message);
}

/*----------------------------------------------------*/
#pragma mark - Private Methods -
/*----------------------------------------------------*/

- (void)findBLEPeripheralByUUID: (NSString *)uuid
                     completion:(RCTBluetoothSerialPeripheralCallback)callback
{
    NSLog(@"Scanning for BLE Peripherals: %@", uuid);
    
    // Scan for peripherals.
    // If the uuid is null or blank, scan and
    // connect to the first available device.
    [self.ble scanForPeripheralsByInterval:(float)3.0 completion:^(NSMutableArray *peripherals) {
        CBPeripheral *peripheral = nil;
        
        if ([peripherals count] < 1) {
            [self onError:@"Did not find any BLE peripherals"];
        } else {
            if (([uuid length] <= 0) | [uuid isEqualToString:@""] | [uuid isKindOfClass:[NSNull class]] | (uuid == nil)) {
                // First device found
                peripheral = [peripherals objectAtIndex:0];
            } else {
                // Device by UUID
                for (CBPeripheral *p in self.ble.peripherals) {
                    if ([uuid isEqualToString:p.identifier.UUIDString]) {
                        peripheral = p;
                        break;
                    }
                }
            }
        }
        
        if (callback) {
            callback(peripheral);
        }
    }];
}

- (NSMutableArray *)getPeripheralList:(NSMutableArray *)peripherals
{
    NSMutableArray *result = [NSMutableArray array];
    
    if ([peripherals count] > 0) {
        for (int i = 0; i < peripherals.count; i++) {
            CBPeripheral *peripheral = [self.ble.peripherals objectAtIndex:i];
            NSMutableDictionary *dict = [self.ble peripheralToDictionary:peripheral];
            [result addObject:dict];
        }
    }
    
    return result;
}

- (NSString *)readUntil:(NSString *)uuid delimiter:(NSString *)delimiter
{
    NSMutableString *activeUUID = nil;

    if ([uuid isKindOfClass:[NSNull class]] | (uuid == nil)) {
        CBPeripheral *activePeripheral = [self.ble getActivePeripheral:uuid];
        
        if (activePeripheral) {
            [activeUUID setString:activePeripheral.identifier.UUIDString];
        }
    } else {
        [activeUUID setString:uuid];
    }
    
    NSString *message = @"";
    
    if ([[self.buffers allKeys] containsObject:activeUUID]) {
        NSMutableString *buffer = [self.buffers valueForKey:activeUUID];
        NSRange range = [buffer rangeOfString:delimiter];
        
        if (range.location != NSNotFound) {
            long end = range.location + range.length;
            message = [buffer substringToIndex:end];
            NSRange truncate = NSMakeRange(0, end);
            [buffer deleteCharactersInRange:truncate];
            [self.buffers setValue:buffer forKey:activeUUID];
        }
    }

    return message;
}

- (void)onError:(NSString *)message
{
    NSLog(@"%@", message);
    
    if (self.doesHaveListeners) {
        [self sendEventWithName:@"error" body:@{@"message":message}];
    }
}

/*----------------------------------------------------*/
#pragma mark - Timers -
/*----------------------------------------------------*/

- (void)bluetoothPowerStateTimer:(NSTimer *)timer
{
    RCTPromiseResolveBlock resolve = [timer userInfo];
    
    if (self.ble.isCentralReady) {
        resolve((id)kCFBooleanTrue);
    } else {
        resolve((id)kCFBooleanFalse);
    }
}

/*----------------------------------------------------*/
#pragma mark - BLE Delegate -
/*----------------------------------------------------*/

- (void)didPowerOn
{
    if (self.doesHaveListeners) {
        [self sendEventWithName:@"bluetoothEnabled" body:nil];
    }
}

- (void)didPowerOff
{
    if (self.doesHaveListeners) {
        [self sendEventWithName:@"bluetoothDisabled" body:nil];
    }
}

- (void)didConnect:(CBPeripheral *)peripheral
{
    NSMutableDictionary *device = [self.ble peripheralToDictionary:peripheral];
    NSString *message = [NSString stringWithFormat:@"Connected to BLE peripheral (UUID : %@)", peripheral.identifier.UUIDString];
    
    NSLog(@"%@", message);
    
    if (self.doesHaveListeners) {
        [self sendEventWithName:@"connectionSuccess" body:@{@"message":message, @"device":device}];
    }
    
    if ([[self.connectionPromises allKeys] containsObject:peripheral.identifier.UUIDString]) {
        NSMutableDictionary *dict = [self.connectionPromises objectForKey:peripheral.identifier.UUIDString];
        RCTPromiseResolveBlock resolver = [dict objectForKey:@"resolver"];
        
        if (resolver) {
            resolver(device);
        }
    }
}

- (void)didFailToConnect:(CBPeripheral *)peripheral
{
    NSMutableDictionary *device = [self.ble peripheralToDictionary:peripheral];
    NSString *message = [NSString stringWithFormat:@"Unable to connect to BLE peripheral (UUID : %@)", peripheral.identifier.UUIDString];

    NSLog(@"%@", message);
    
    if (self.doesHaveListeners) {
        [self sendEventWithName:@"connectionFailed" body:@{@"message":message, @"device":device}];
    }
    
    if ([[self.connectionPromises allKeys] containsObject:peripheral.identifier.UUIDString]) {
        NSMutableDictionary *dict = [self.connectionPromises objectForKey:peripheral.identifier.UUIDString];
        RCTPromiseRejectBlock reject = [dict objectForKey:@"rejector"];
        
        if (reject) {
            NSError *err = [NSError errorWithDomain:@"fail_to_connect" code:500 userInfo:@{NSLocalizedDescriptionKey:message}];
            reject(@"wrong_uuid", message, err);
        }
    }
}

- (void)didConnectionLost:(CBPeripheral *)peripheral
{
    NSMutableDictionary *device = [self.ble peripheralToDictionary:peripheral];
    NSString *message = [NSString stringWithFormat:@"BLE peripheral (UUID : %@) connection lost", peripheral.identifier.UUIDString];
    
    NSLog(@"%@", message);
    
    if (self.doesHaveListeners) {
        [self sendEventWithName:@"connectionLost" body:@{@"message":message, @"device":device}];
    }

    [self.connectionPromises removeObjectForKey:peripheral.identifier.UUIDString];
}

- (void)didReceiveData:(NSString *)uuid data:(unsigned char *)data length:(NSInteger)length
{
    NSLog(@"Received data from peripheral UUID : %@", uuid);
    
    NSData *d = [NSData dataWithBytes:data length:length];
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    
    if (s) {
        NSLog(@"Received %@", s);
        
        // Append buffers
        if ([[self.buffers allKeys] containsObject:uuid]) {
            NSMutableString *buffer = [self.buffers valueForKey:uuid];
            [buffer appendString:s];
            [self.buffers setValue:buffer forKey:uuid];
        }
            
        NSMutableString *delimiter = [[NSMutableString alloc] initWithString:@""];

        if ([[self.delimiters allKeys] containsObject:uuid]) {
            [delimiter setString:[self.delimiters valueForKey:uuid]];
        }
            
        NSLog(@"Read until delimiter : %@", delimiter);
            
        NSString *message = [self readUntil:uuid delimiter:delimiter];

        if ([message length] > 0) {
            if (self.doesHaveListeners) {
                [self sendEventWithName:@"read" body:@{@"id":uuid, @"data":message}];
                [self sendEventWithName:@"data" body:@{@"id":uuid, @"data":message}];
            }
        }
    } else {
        [self onError:@"Error converting received data into a string"];
    }
}

- (void)didError:(NSError *)error
{
    NSString *message = [error localizedDescription];
    [self onError:message];
}

/*----------------------------------------------------*/
#pragma mark - RCT Event Emitter -
/*----------------------------------------------------*/

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"bluetoothEnabled", @"bluetoothDisabled", @"connectionSuccess", @"connectionFailed", @"connectionLost", @"read", @"data", @"error"];
}

- (void)startObserving
{
    self.doesHaveListeners = TRUE;
}

- (void)stopObserving
{
    self.doesHaveListeners = FALSE;
}

@end
