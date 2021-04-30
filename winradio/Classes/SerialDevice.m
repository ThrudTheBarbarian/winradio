//
//  SerialDevice.m
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//
#import "SerialDevice.h"

#import <CoreFoundation/CoreFoundation.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/serial/IOSerialKeys.h>
#import <IOKit/IOBSD.h>

#import <IOKit/IOTypes.h>
#import <mach/std_types.h>
#import <sys/ttycom.h>

#include <sys/ioctl.h>
#include <unistd.h>

@implementation SerialDevice
	{
	struct termios	_attrs;				// The original attributes for the port
	struct termios	_current;			// The current attributes for the port
	}

/*****************************************************************************\
|* Return a list of devices as an array
\*****************************************************************************/
+ (NSArray *) devices
	{
	NSArray * results			= nil;
	io_iterator_t iterator		= (io_iterator_t)0;
	
	kern_return_t kernResult = [self _enumerateSerialDevices:&iterator];
	if (kernResult == KERN_SUCCESS)
		{
		NSMutableArray *paths	= [NSMutableArray new];
		
		kernResult = [self _devices:paths usingIterator:iterator];
		if (kernResult == KERN_SUCCESS)
			results=  [NSArray arrayWithArray:paths];
		}
	IOObjectRelease(iterator);
	
	return results;
	}

/*****************************************************************************\
|* Initialise an instance of the class
\*****************************************************************************/
- (instancetype) initWithDevicePath:(NSString *)device
	{
	self = [super init];
	if (self)
		{
		_fd			= -1;
		_debugLevel	= 0;
		
		[self setPath:device];
		}
	return self;
	}

/*****************************************************************************\
|* Initialise an instance of the class
\*****************************************************************************/
+ (instancetype) deviceWithPath:(NSString *)devicePath
	{
	return [[SerialDevice alloc] initWithDevicePath:devicePath];
	}

/*****************************************************************************\
|* ... and destroy the instance
\*****************************************************************************/
- (void) dealloc
	{
	if (_fd >= 0)
		[self close];
	}

/*****************************************************************************\
|* Get/Set the baud rate
\*****************************************************************************/
- (BOOL) setBaudRate:(int)baudrate
	{
	struct termios options = _current;
	
	cfsetspeed(&_current, baudrate);
	if ([self _commit])
		return YES;
	
	_current = options;
	return NO;
	}
	
- (int) baudRate
	{
	return (int) cfgetospeed(&_current);
	}

/*****************************************************************************\
|* Set/Get the number of data-bits
\*****************************************************************************/
- (int) dataBits
	{
	return ((_current.c_cflag & CSIZE) >> 8) + 5;
	}

- (BOOL) setDataBits:(int)bits
	{
	_current.c_cflag &= ~CSIZE;
	switch (bits)
		{
		case 5:
			break;
		case 6:
			_current.c_cflag |= CS6;
			break;
		case 7:
			_current.c_cflag |= CS7;
			break;
		case 8:
			_current.c_cflag |= CS8;
			break;
		}
		
	return [self _commit];
	}
	
/*****************************************************************************\
|* Get/Set the parity
\*****************************************************************************/
- (BOOL) setParity:(ParityType)parityType
	{
	switch (parityType)
		{
		case PARITY_NONE:
			_current.c_cflag &= ~PARENB;
			break;
		case PARITY_EVEN:
			_current.c_cflag |= PARENB;
			_current.c_cflag &= ~PARODD;
			break;
		case PARITY_ODD:
			_current.c_cflag |= PARENB;
			_current.c_cflag |= PARODD;
			break;
		}
	return [self _commit];
	}

- (ParityType) parity
	{
	if (_current.c_cflag & PARENB)
		{
		if (_current.c_cflag & PARODD)
			return PARITY_ODD;
		return PARITY_EVEN;
		}
	else
		return PARITY_NONE;
	}

/*****************************************************************************\
|* Get/Set the number of stop-bits
\*****************************************************************************/
- (int) stopBits
	{
	if (_current.c_cflag & CSTOPB)
		return 2;
	return 1;
	}

- (BOOL) setStopBits:(int) num
	{
	BOOL ok = YES;
	
	switch (num)
		{
		case 1:
			_current.c_cflag &= ~CSTOPB;
			[self _commit];
			break;
		case 2:
			_current.c_cflag |= CSTOPB;
			[self _commit];
			break;
		default:
			NSLog(@"Cannot set %d stop-bits!", num);
			ok = NO;
			break;
		}
	return ok;
	}
	
/*****************************************************************************\
|* Send a BRK
\*****************************************************************************/
- (void) sendBreak
	{
	tcsendbreak(_fd, 0);
	}
	
/*****************************************************************************\
|* open the port
\*****************************************************************************/
- (BOOL) open
	{
	BOOL ok = YES;

	_fd = open([_path fileSystemRepresentation], O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (_fd == -1)
		{
		NSLog(@"Error opening serial port %@ - %s(%d)", _path, strerror(errno), errno);
		ok = NO;
		}

	// Prevent multiple opens on the same file.
	if (ok && (ioctl(_fd, TIOCEXCL) == -1))
		{
		NSLog(@"Error setting TIOCEXCL on %@ - %s(%d)", _path, strerror(errno), errno);
		ok = NO;
		}
		
	// Now that the device is open, clear the O_NONBLOCK flag so subsequent I/O will block.
	if (ok && (fcntl(_fd, F_SETFL, 0) == -1))
		{
		NSLog(@"Error clearing O_NONBLOCK %@ - %s(%d)", _path, strerror(errno), errno);
		ok = NO;
		}
	
	// Get the current options and save them so we can restore the settings later.
	if (ok && tcgetattr(_fd, &_attrs) == -1)
		{
		NSLog(@"Error getting tty attributes %@ - %s(%d).\n", _path, strerror(errno), errno);
		ok = NO;
		}
		
	// Get the current options.
	if (ok && tcgetattr(_fd, &_current) == -1)
		{
		NSLog(@"Error getting tty attributes %@ - %s(%d).\n", _path, strerror(errno), errno);
		ok = NO;
		}
	
	
	if (ok)
		{
		// Set raw input (non-canonical) mode, with reads blocking until either
		// a single character has been received or a one second timeout expires.
		cfmakeraw(&_current);
		_current.c_cc[VMIN]			= 1;
		_current.c_cc[VTIME]		= 10;
		_current.c_cflag			= CLOCAL | CREAD;
		_current.c_oflag			= 0;
		_current.c_iflag			= 0;
		
		ok = [self _commit];
		
		if (ok)
			ok = [self setBaudRate:B9600];
		if (ok)
			ok = [self setParity:PARITY_NONE];
		if (ok)
			ok = [self setDataBits:8];
		if (ok)
			ok = [self setStopBits:1];
		
		if (!ok)
			NSLog(@"Error during open()");
		}
		
	return ok;
	}

/*****************************************************************************\
|* Close the port
\*****************************************************************************/
- (void) close
	{
	if (tcdrain(_fd) == -1)
		{
		NSLog(@"Error waiting for drain - %s(%d)", strerror(errno), errno);
		}
	
	if (fcntl(_fd, F_SETFL, fcntl(_fd, F_GETFL, 0) | O_NONBLOCK) == -1)
		{
		NSLog(@"Error clearing O_NONBLOCK %s(%d).\n", strerror(errno), errno);
		}

	if (tcsetattr(_fd, TCSANOW, &_attrs) == -1)
		{
		NSLog(@"Error resetting tty attributes - %s(%d)", strerror(errno), errno);
		}
		
	close(_fd);
	}
	
/*****************************************************************************\
|* Write a string to the serial device
\*****************************************************************************/
- (BOOL) writeString:(NSString *)string
	{
	char *str = (char *) [string UTF8String];
	int   num = (int) strlen(str);
	
	write(_fd, str, num);
	
	[self _drain];
			
	if (_debugLevel > 100)
		fprintf(stderr, "DBG> wrote '%s' (%d)\\n\n", str, num);
	return YES;
	}
	
/*****************************************************************************\
|* Write a line to the serial device
\*****************************************************************************/
- (BOOL) writeLine:(NSString *)string
	{
	BOOL crlf = ([string hasSuffix:@"\r"]) || ([string hasSuffix:@"\n"]);
	if (!crlf)
		string = [NSString stringWithFormat:@"%@\r", string];
	return [self writeString:string];
	}

/*****************************************************************************\
|* Write a character to the serial device
\*****************************************************************************/
- (BOOL) write:(uint8_t)c
	{
	int num = (int) write(_fd, &c, 1);
	[self _drain];

	if (_debugLevel > 100)
		fprintf(stderr, "DBG> wrote '%c' (%d)\\n\n", c, num);
	return (num == 1);
	}
	
/*****************************************************************************\
|* Read a line from the serial device
\*****************************************************************************/
- (NSString *) readLine
	{
	return [self readLineWithTerminator:"\r\n"];
	}

- (NSString *) readLineWithTerminator:(char *)terminator
	{
	static NSCharacterSet *cset = nil;
	if (cset == nil)
		cset = [NSCharacterSet whitespaceAndNewlineCharacterSet];
		
	NSMutableString *result = [NSMutableString new];

	int numBytes = 0;
	char c[2];
	c[0] = c[1] = '\0';
	
	do
		{
		numBytes = (int) read(_fd, &(c[0]), 1);
		if (_debugLevel > 100)
			NSLog(@"DBG> read %d bytes [%c]", numBytes, c[0]);
		if (numBytes == -1)
			{
			NSLog(@"Cannot read from serial port %@", _path);
			}
		else if (numBytes == 1)
			{
			char *terminated = strchr(terminator, c[0]);
			if (_debugLevel > 100)
				NSLog(@" = %p (%d)", terminated, c[0]);
			if (terminated != NULL)
				break;
				
			[result appendString:[NSString stringWithUTF8String:c]];
			}
		}
	while (numBytes == 1);
	
	return [result stringByTrimmingCharactersInSet:cset];
	}

/*****************************************************************************\
|* Read 'num' bytes into a buffer
\*****************************************************************************/
- (BOOL) read:(int)count into:(uint8_t *)buffer
	{
	BOOL ok					= YES;
	int numBytes 			= 0;
	
	char c[2];
	c[0] = c[1] = '\0';
	do
		{
		int charsRead = (int) read(_fd, c, 1);
		if (_debugLevel > 100)
			NSLog(@"DBG> read %d bytes [%c]", numBytes, c[0]);
		
		if (charsRead == -1)
			{
			NSLog(@"Cannot read from serial port %@", _path);
			ok = NO;
			break;
			}
			
		else if (charsRead == 1)
			{
			buffer[numBytes] = (uint8_t)c;
			numBytes ++;
			}
		}
	while (numBytes < count);
	
	return ok;
	}


#pragma mark - Private methods
/*****************************************************************************\
|* Enumerate the serial ports on the system
\*****************************************************************************/
+ (kern_return_t) _enumerateSerialDevices:(io_iterator_t *)matchingServices
	{
	kern_return_t			kernResult;
	mach_port_t				masterPort;
	
	kernResult	= IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (kernResult != KERN_SUCCESS)
		{
		NSLog(@"Error: mach master port returned %d", kernResult);
		}
	else
		{
		NSMutableDictionary * classesToMatch = (NSMutableDictionary *)
				CFBridgingRelease(IOServiceMatching(kIOSerialBSDServiceValue));
		if (classesToMatch == nil)
			NSLog(@"IOServiceMatch returned nil - no serial ports available");
		else
			{
			NSString *key = [NSString stringWithUTF8String:kIOSerialBSDTypeKey];
			NSString *val = [NSString stringWithUTF8String:kIOSerialBSDRS232Type];
			[classesToMatch setValue:val forKey:key];
			}
		
		kernResult = IOServiceGetMatchingServices(masterPort,
							(CFDictionaryRef)CFBridgingRetain(classesToMatch),
							matchingServices);
		if (kernResult != KERN_SUCCESS)
			NSLog(@"IOServiceGetMatchingServices returned %d", kernResult);
		}
		
	return kernResult;
	}

/*****************************************************************************\
|* Get the paths from a port iterator
\*****************************************************************************/
+ (kern_return_t) _devices:(NSMutableArray *)paths usingIterator:(io_iterator_t)iterator
	{
	io_object_t		deviceService	= (io_object_t)0;
	kern_return_t	kernResult		= KERN_SUCCESS;

	while ((deviceService = IOIteratorNext(iterator)))
		{
		NSString *deviceFilePath = (NSString *)
			CFBridgingRelease(IORegistryEntryCreateCFProperty(deviceService,
							  CFSTR(kIOCalloutDeviceKey),
							  kCFAllocatorDefault,
							  0));
		if (deviceFilePath == nil)
			kernResult = KERN_FAILURE;
		else
			[paths addObject:deviceFilePath];
		}
		
	(void) IOObjectRelease(deviceService);
 
	return kernResult;
	}


/*****************************************************************************\
|* Set the baud rate
\*****************************************************************************/
- (BOOL) _commit
	{
	BOOL state = YES;
	
	if (_fd < 0)
		state = NO;
	else
		{
		if (tcsetattr(_fd, TCSANOW, &_current) == -1)
			{
			NSLog(@"Error setting tty attrs %@ - %s(%d)",
										_path, strerror(errno), errno);
			state = NO;
			}
		}
		
	return state;
	}
	
/*****************************************************************************\
|* Flush the output
\*****************************************************************************/
- (void) _drain
	{
	tcdrain(_fd);
	}

@end
