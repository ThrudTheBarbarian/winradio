//
//  SerialDevice.h
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <termios.h>

#import "DeviceProtocol.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum
	{
	PARITY_NONE	= 	(IGNPAR),
	PARITY_EVEN	=	(PARENB),
	PARITY_ODD  =	((PARENB)|(PARODD))
	} ParityType;

@interface SerialDevice : NSObject <DeviceProtocol>

+ (NSArray *) devices;

- (instancetype) initWithDevicePath:(NSString *)devicePath;
+ (instancetype) deviceWithPath:(NSString *) devicePath;

- (BOOL) open;
- (void) close;

- (BOOL) writeLine:(NSString *)line;
- (BOOL) write:(uint8_t)c;
- (BOOL) writeString:(NSString *)s;

- (NSString *) readLine;
- (NSString *) readLineWithTerminator:(char *)c;
- (BOOL) read:(int)bytes into:(uint8_t *)buffer;

- (void) sendBreak;

- (BOOL) setBaudRate:(int)baudrate;
- (int) baudRate;

- (int) dataBits;
- (BOOL) setDataBits:(int)bits;

- (BOOL) setParity:(ParityType)parityType;
- (ParityType) parity;

- (int) stopBits;
- (BOOL) setStopBits:(int) num;

@property (assign, nonatomic) int			debugLevel;
@property (copy, nonatomic) NSString *		path;
@property (assign, readonly) int			fd;
@end

NS_ASSUME_NONNULL_END
