//
//  Radio.h
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DeviceProtocol.h"
NS_ASSUME_NONNULL_BEGIN

typedef enum
	{
	RADIO_RUN				= 0x03,
	RADIO_PREPARE			= 0x06,
	RADIO_INITIALISED		= 0x07,
	ENABLE_POWER			= 0x08,
	GET_POWER				= 0x0A,
	GET_RADIO_READY			= 0x0D,
	UNMUTE_RADIO			= 0x50,
	MUTE_RADIO				= 0x51,
	ENABLE_ATTENUATION		= 0x56,
	DISABLE_ATTENUATION		= 0x57,
	GET_VOLUME				= 0x89
	} RadioCommand;

typedef enum
	{
	RIF_USVERSION			= 0x00000001,	// set if hardware is US version
	RIF_DSP					= 0x00000002,	// set if DSP is present
	RIF_LSBUSB				= 0x00000004	,	// set if receiver as CW/LSB/USB instead of SSB
	RIF_CWIFSHIFT			= 0x00000008	,	// set if receiver uses IFShift in CW (not BFOOffset)
	RIF_AGC					= 0x00000100	,	// set if receiver supports AGC on/off
	RIF_IFGAIN				= 0x00000200		// set if receiver has manual IF gain control
	} FeatureFlags;

typedef enum
	{
	RHV_1000a				= 0x0100	,		// older WR-1000 series
	RHV_1000b				= 0x010a	,		// current WR-1000 series
	RHV_1500				= 0x0132,
	RHV_1550				= 0x0137	,		// new WR-1550 receiver
	RHV_3000				= 0x0200	,		// Spectrum Monitor series
	RHV_3100				= 0x020a,
	RHV_3150				= 0x020f	,		// new WR-3150 receiver
	RHV_3200				= 0x0214,
	RHV_3500				= 0x0232,
	RHV_3700				= 0x0246,
	RHV_2000				= 0x0300
	} RadioVersion;

typedef enum
	{
	RMD_CW					= 0,
	RMD_AM					= 1,
	RMD_FMN					= 2,
	RMD_FMW					= 3,
	RMD_LSB					= 4,
	RMD_USB					= 5,
	RMD_FMM					= 6,				// 50kHz FM
	RMD_FM6					= 7				// 6kHz FMN 
	} RadioMode;

typedef enum
	{
	RHI_ISA					= 0,
	RHI_SERIAL				= 1
	} RadioInterface;
	
@class SerialDevice;
@class Settings;

@interface Radio : NSObject

- (instancetype) initWithDevice:(NSString *)device;

/*****************************************************************************\
|* Set the power status
\*****************************************************************************/
- (BOOL) setPower:(BOOL)powerFlag;

/*****************************************************************************\
|* Update the mute status
\*****************************************************************************/
- (BOOL) updateMute;

@property (strong, nonatomic) id<DeviceProtocol> device;
@property (strong, nonatomic) Settings * settings;
@end

NS_ASSUME_NONNULL_END
