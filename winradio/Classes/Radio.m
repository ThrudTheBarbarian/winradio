//
//  Radio.m
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import "Radio.h"
#import "Settings.h"
#import "SettingsFactory.h"
#import "SerialDevice.h"

#import <sys/ttycom.h>
#include <sys/time.h>

#import "defines.h"

#define RFQ_X10		0x80000000L		// frequency x10 multiplier, ie. 2-20 GHz

static const struct
	{
	int X; int Y; int W1; int W2;
	} BFO[3] = {
		{ -13000, 500, -11900, 3800 },	/*  series I receivers */
		{ -13000, 500, -16500, 3500 },	/*  series II receivers */
		{ -13000, 500, -14200, 1200 }};	/*  series II with SSB filter */


@implementation Radio

/*****************************************************************************\
|* Initialise with a device name
\*****************************************************************************/
- (instancetype) initWithDevice:(NSString *)device
	{
	if (self = [super init])
		{
		SettingsFactory *factory	= [SettingsFactory sharedInstance];
		_settings 					= [factory settingsForRadio:device];
		if ([_settings isInUse])
			{
			self = nil;
			}
		else
			{
			[_settings setIsInUse:YES];
			if ([_settings isSerial])
				[self _initAsSerial];
			}
		}
	return self;
	}


/*****************************************************************************\
|* Set the power status
\*****************************************************************************/
- (BOOL) setPower:(BOOL)powerFlag
	{
	_settings.curPower = powerFlag;

	/*************************************************************************\
	|* mute or un-mute receiver if serially connected
	\*************************************************************************/
	if (_settings.radioInfo->hwInterface == RHI_SERIAL)
		return [self updateMute];
	return YES;
	}

/*****************************************************************************\
|* Update the mute status
\*****************************************************************************/
- (BOOL) updateMute
	{
	BOOL isMuted 	= _settings.curMuted;
	BOOL isPowered 	= _settings.curPower;
	BOOL isSerial	= _settings.radioInfo->hwInterface == RHI_SERIAL;
	BOOL wasMuted 	= _settings.lastMuted;
	
	/*************************************************************************\
	|* only update mute status when it actually changes (minimises noise)
	\*************************************************************************/
	if ((isMuted || (!isPowered && (isSerial))) ^ wasMuted)
		{
		_settings.lastMuted = !_settings.lastMuted;

		if (_settings.lastMuted)
			return [self _write:MUTE_RADIO];
		else
			return [self _write:UNMUTE_RADIO];
		}
	return TRUE;
	}

- (BOOL) setMute:(BOOL)yn
	{
	_settings.curMuted = yn;
	return [self updateMute];
	}

- (BOOL) getMute
	{
	return _settings.curMuted;
	}

/*****************************************************************************\
|* Handle BFO offset
\*****************************************************************************/
- (BOOL) setBFOOffset:(int)bfo
	{
	/*************************************************************************\
	|* check BFO parameter and whether the function is supported
	\*************************************************************************/
	int maxBfo 			= _settings.radioInfo->maxBFO;
	BOOL useIfShift		= _settings.radioInfo->features & RIF_CWIFSHIFT;
	if ((bfo < -maxBfo) || (bfo > maxBfo) || useIfShift)
		return NO;

	_settings.curBfo = bfo;

	if (_settings.radioInfo->hwVer >= RHV_1500)
		{
		if (_settings.curMode != RMD_CW)
			return TRUE;

		int B = bfo - (BFO[0].X - BFO[0].W1 - BFO[0].W2) / 2;
		if (_settings.actualFreq < _settings.ifxOverFreq)
			B -= _settings.freqError;
		else
			B += _settings.freqError;

		return [self _setBfo1500:B];
		}

	if (_settings.wantedFreq < _settings.ifxOverFreq)
		return [self _setBfo1500:-bfo - _settings.freqError];
	else
		return [self _setBfo1500:bfo + _settings.freqError];
	}

- (int) getBFOOffset
	{
	return _settings.curBfo;
	}


/*****************************************************************************\
|* Handle IF shift
\*****************************************************************************/
- (BOOL) setIFShift:(int)ifShift
	{
	long A, B=0;
	double f;

	/*************************************************************************\
	|* check for IF shift support
	\*************************************************************************/
	BOOL useIfShift		= _settings.radioInfo->features & RIF_LSBUSB;
	if (!useIfShift)
		return NO;

	/*************************************************************************\
	|* check supplied parameter
	\*************************************************************************/
	int max				= _settings.radioInfo->maxIFShift;
	if ((ifShift < - max) || (ifShift > max))
		return NO;

	_settings.curIfShift = ifShift;

	int hwVer	= _settings.radioInfo->hwVer;
	
	int bci;	/*  BFO constant index */
	if ((hwVer <= RHV_1500) || ((hwVer >= RHV_3000) && (hwVer <= RHV_3100)))
		bci = 0;
	else
		{
		if (hwVer >= RHV_3150)
			bci = 1;
		else
			bci = 2;
		}
		
	BOOL belowIFXOver = _settings.wantedFreq < _settings.ifxOverFreq;

	/*  establish frequency and BFO to perform desired IF shift */
	switch (_settings.curMode)
		{
		case RMD_CW:
			A = (BFO[bci].X + BFO[bci].W1 + BFO[bci].W2) / 2;
			if (belowIFXOver)
				A = -A;
			A += ifShift;
			B = -(BFO[bci].X - BFO[bci].W1 - BFO[bci].W2) / 2;
			break;
			
		case RMD_LSB:
			if (belowIFXOver)
				A = -BFO[bci].X - BFO[bci].Y - BFO[bci].W2;
			else
				A = BFO[bci].W1 - BFO[bci].Y;
			A -= ifShift;
			break;
		
		case RMD_USB:
			if (belowIFXOver)
				A = BFO[bci].Y - BFO[bci].W1;
			else
				A = BFO[bci].X + BFO[bci].Y + BFO[bci].W2;
			A += ifShift;
			break;
			
		default:
			return TRUE;
		}

	/*  adjust the RX frequency */
	if (![self _setFreq1000:(_settings.wantedFreq + A) actualFreq:&f])
		return NO;

	_settings.freqError = (int)(f - (_settings.wantedFreq + A) + 0.5);

	if (_settings.curMode == RMD_CW)
		{
		if (belowIFXOver)
			B -= _settings.freqError + ifShift;
		else
			B += _settings.freqError + ifShift;
		}
	else
		{
		if (belowIFXOver)
			B = -A - _settings.freqError - BFO[bci].X;
		else
			B = A + _settings.freqError - BFO[bci].X;
		}

	/*  set the BFO */
	return [self _setBfo1500:(int)B];
	}

- (int) getIFShift
	{
	return _settings.curIfShift;
	}

/*****************************************************************************\
|* Handle attenuation
\*****************************************************************************/
- (BOOL) setAttenuation:(BOOL)yn
	{
	_settings.curAttenuation = yn;
	return [self _write:yn ? ENABLE_ATTENUATION : DISABLE_ATTENUATION];
	}

- (BOOL) getAttenuation
	{
	return _settings.curAttenuation;
	}

/*****************************************************************************\
|* Handle mode
\*****************************************************************************/
- (BOOL) setMode:(int)mode
	{
	if ((mode < 0) || (mode >= _settings.radioInfo->numModes))
		return NO;

	return [self _setMode1000:mode];
	}

- (int) getMode
	{
	return _settings.curMode;
	}

/*****************************************************************************\
|* Handle frequency
\*****************************************************************************/
- (BOOL) setFrequency:(uint32_t)freq
	{
	double dFreq = (freq & RFQ_X10) ? 10.0 * (freq & 0x7fffffffL) : freq;

	/*  check to make sure frequency is within valid range */
	if ((dFreq < _settings.radioInfo->minFreq) ||
		((dFreq / 1e3) > _settings.radioInfo->maxFreqkHz))
		return NO;

	/*  check for US restricted frequencies */
	if ((_settings.radioInfo->features & RIF_USVERSION) &&
		(((dFreq > 825e6) && (dFreq < 849e6)) ||
		 ((dFreq > 870e6) && (dFreq < 894e6))))
		return NO;

	_settings.freq 			= freq;
	_settings.wantedFreq	= dFreq;

	/*  if in a mode that uses IF-shift, call SetIFShift to set the frequency */
	int mode 	= _settings.curMode;
	int ifshift	= _settings.radioInfo->features & RIF_CWIFSHIFT;
	if ((mode == RMD_LSB) || (mode == RMD_USB) || ((mode == RMD_CW) && ifshift))
		return [self setIFShift:_settings.curIfShift];

	double f;
	if ([self _setFreq1000:dFreq actualFreq:&f])
		{
		_settings.freqError = (int)(f - dFreq + 0.5);
		if (mode == RMD_CW)	/*  update BFO to compensate for freq error */
			return [self setBFOOffset:_settings.curBfo];
		}
	else
		{
		_settings.freqError = 0;
		return NO;
		}

	return YES;
	}
	
- (uint32_t) getFrequency
	{
	return _settings.freq;
	}


#pragma mark - Private methods

/*****************************************************************************\
|* Initialise a serial device
\*****************************************************************************/
- (BOOL) _initAsSerial
	{
	_device = [SerialDevice deviceWithPath:[_settings deviceName]];
	if (_device == nil)
		return NO;
	
	[self _reset];
	
	return YES;
	}

/*****************************************************************************\
|* Reset the radio
\*****************************************************************************/
- (BOOL) _reset
	{
	_settings.refFreq = 12800000L;
	
	uint8_t byte;
	if ([self _write:RADIO_INITIALISED] && [self _read:&byte] && (byte == 1))
		{
		/*********************************************************************\
		|* We have already been initialised
		\*********************************************************************/
		_settings.curPower 	= [self _readPowered];
		_settings.curVolume	= [self _readVolume];
		if ([self _readSettings])
			return YES;	// All done
		}

	if (![self _performReset])
		return NO;

	/*************************************************************************\
	|* initialize RadioSettings structure
	\*************************************************************************/
	_settings.wantedFreq 		= 10e6;
	_settings.actualFreq 		= 10e6;
	_settings.freq 				= 10000000;
	_settings.curMode 			= RMD_AM;
	_settings.freqError 		= 0;
	_settings.curVolume 		= 5;
	_settings.curAttenuation	= NO;
	_settings.curMuted 			= NO;
	_settings.curPower 			= YES;
	_settings.curBfo 			= 0;
	_settings.curIfShift 		= 0;
	_settings.initVolume 		= YES;
	_settings.lastMuted			= NO;

	[self _initializeRadio];
	return TRUE;
	}

/*****************************************************************************\
|* Initialise the radio
\*****************************************************************************/
- (void) _initializeRadio
	{
	/*************************************************************************\
	|* make sure the radio is ready
	\*************************************************************************/
	for (int i=0; i<8; i++)
		{
		long timeout = [self _getTickCount] + 200;	/*  200 ms */
		do
			{
			uint8_t a, b;
			[self _write:GET_RADIO_READY];
			if ([self _read:&a] && [self _read:&b] && (a == 0x55) && (b == 0xaa))
				break;
			}
			while ([self _getTickCount]  - timeout < 0);
		}

	BOOL oMute = _settings.curMuted;
	_settings.radioInfo->hwVer = RHV_1000b;
	
	/*************************************************************************\
	|* Prevents SetPower() from programming the PLL
	\*************************************************************************/
	[self setPower:YES];
	[self _delay:300];

	_settings.lastMuted = NO;
	[self setMute:YES];
	[self _initialiseRadioByHardware:YES];
	[self setBFOOffset:_settings.curBfo];
	[self setIFShift:_settings.curIfShift];
	[self setAttenuation:_settings.curAttenuation];
	[self setMute:oMute];
	[self setMode:_settings.curMode];
	[self setFrequency:_settings.freq];

	[self _write:RADIO_PREPARE];
	[self _write:RADIO_RUN];
	}


/*****************************************************************************\
|* Speed up comms
\*****************************************************************************/
- (void) _setBaudRate
    {
    #ifdef WRSERIAL_115200 /* PB 115200 supported on all models ? */
        [self _write:SET_BAUDRATE];
        [self _write:1];
        SetBaudRate(hRadio, 115200);
    #endif
    #ifdef WRSERIAL_38400
        [self _write:SET_BAUDRATE];
        [self _write:3];
		SetBaudRate(hRadio, 38400);
    #endif
    }

/*****************************************************************************\
|* Reset the device
\*****************************************************************************/
- (BOOL) _performReset
	{
	TRACE("Reset\n");

    if (_settings.radioInfo->hwInterface == RHI_SERIAL)
        {
        /*********************************************************************\
        |* initiates comms with serial devices (no mods required)
        \*********************************************************************/
        [self _write:0];
        [self _write:0];
        [self _write:0];
        [self _write:0];

        /*********************************************************************\
        |* increase baud rate
        \*********************************************************************/
        [self _setBaudRate];
        
        /*********************************************************************\
        |* establish existance of WiNRADiO
        \*********************************************************************/
		if (![self _detectRadio])
			{
			[self _delay:200];

            [self _write:0];
            [self _write:0];
            [self _write:0];
            [self _write:0];
    
            if (![self _detectRadio])
                return NO;
			}
		return YES;
        }
        
    return NO;
    }

     
/*****************************************************************************\
|* Detect presence
\*****************************************************************************/
- (BOOL) _detectRadio
    {
    uint8_t a, b;
 
    [self _write:GET_RADIO_READY];
    [self _read:&a];
    [self _read:&b];
    return (a==0x55) && (b==0xaa);
    }
    
/*****************************************************************************\
|* Write a byte to the radio
\*****************************************************************************/
- (BOOL) _write:(uint8_t)byte
	{
	return ([_device write:byte] == 1);
	}

/*****************************************************************************\
|* Read a byte from the radio
\*****************************************************************************/
- (BOOL) _read:(uint8_t *)byte
	{
	*byte = 0xFF;
	return [_device read:1 into:byte];
	}

/*****************************************************************************\
|* Write a buffer then read a buffer
\*****************************************************************************/
- (BOOL) _xferOutNum:(int)outNum outBuf:(uint8_t *)outBuf
               inNum:(int)inNum  inBuf:(uint8_t *)inBuf
    {
    while (outNum --)
        if (![self _write:*outBuf++])
            return NO;
    
    while (inNum --)
        if (![self _read:inBuf++])
            return NO;
    
    return YES;
    }

/*****************************************************************************\
|* Read whether we're powered up. Not useful for serial devices
\*****************************************************************************/
- (BOOL) _readPowered
	{
	if (_settings.isSerial)
		return YES;
		
	return NO; // until we have one
	}

/*****************************************************************************\
|* Read the current output volume.
\*****************************************************************************/
- (int) _readVolume
	{
	[self _write:GET_VOLUME];
	
	uint8_t byte;
	if ([self _read:&byte])
		return (int)byte;
		
	return -1;
	}

/*****************************************************************************\
|* Read the current settings.
\*****************************************************************************/
- (BOOL) _readSettings
	{
	uint8_t buf[16];
	uint8_t checksum = 0;
	
	/*************************************************************************\
	|* Read the current settings.
	\*************************************************************************/
	for (int i=0; i<16; i++)
		{
		[self _write:0x12];
		[self _write:0xb0 + i];
		[self _read:&(buf[i])];
		if (i < 15)
			checksum += buf[i];
		}

	/*************************************************************************\
	|* compare checksums to see if valid information
	\*************************************************************************/
	if (checksum != buf[15])
		{
		NSLog(@"Failed to read settings from radio [%@]", _settings.deviceName);
		return NO;
		}
		
	/*************************************************************************\
	|* Store settings : Frequency
	\*************************************************************************/
	_settings.freq 	= (uint32_t)(((long)buf[3]) << 24
							   | ((long)buf[2]) << 16
							   | ((long)buf[1]) << 8
							   | buf[0]);
				
	if (_settings.freq & 0x80000000l)	//  if MSB set, freq = low 31 bits x 10
		_settings.wantedFreq = 10.0 * (_settings.freq ^ RFQ_X10);
	else
		_settings.wantedFreq = _settings.freq;
	_settings.freqError = 0;
	_settings.actualFreq = _settings.wantedFreq;
	
	/*************************************************************************\
	|* Store settings : mode
	\*************************************************************************/
	_settings.curMode = buf[4];
	
	/*************************************************************************\
	|* Store settings : flags
	\*************************************************************************/
	_settings.curAttenuation 	= (buf[5] & 0x01) ? YES : NO;
	_settings.curMuted 			= buf[5] & 0x02;
	_settings.lastMuted 		= buf[5] & 0x04;
	_settings.curAGC	 		= buf[5] & 0x08;
	
	if (buf[5] & 0x40)
		_settings.refFreq = 25600000L;
	
	/*************************************************************************\
	|* Store settings : hardware version
	\*************************************************************************/
	_settings.radioInfo->hwVer	= (((uint16_t)buf[14]) << 8) | buf[13];

	/*************************************************************************\
	|* get full receiver settings according to hardware version
	\*************************************************************************/
	[self _initialiseRadioByHardware:NO];
	

	/*  fill in rest of the settings */
	if (buf[5] & 0x80)
		_settings.radioInfo->features |= RIF_USVERSION;
		
	/*  BFO or IF shift */
	BOOL earlyHW 	= _settings.radioInfo->hwVer <= RHV_1000b;
	BOOL cwMode		= _settings.curMode == RMD_CW;
	BOOL useIFshift	= _settings.radioInfo->features & RIF_CWIFSHIFT;
	
	if (earlyHW || (cwMode && !(useIFshift)))
		{
		_settings.curBfo 		= ((int)buf[7] << 8) | buf[6];
		_settings.curIfShift 	= 0;
		}
	else
		{
		_settings.curIfShift 	= ((int)buf[7] << 8) | buf[6];
		_settings.curBfo 		= 0;
		}

	/*************************************************************************\
	|* Store settings : IF gain
	\*************************************************************************/
	_settings.curIfGain 		= buf[8];

	return TRUE;
	}

/*****************************************************************************\
|* Set the BFO PLL
\*****************************************************************************/
- (BOOL) setBfoPllC:(uint8_t)c
                  R:(uint32_t)R
                  N:(uint32_t)N
             setPll:(uint8_t)setPll
             clrPll:(uint8_t)clrPll
    {
	BOOL isUS   = _settings.radioInfo->features & RIF_USVERSION;
	int bufidx = 0;
	
    uint8_t buf[16];

	/*************************************************************************\
	|* set PLL C register
	\*************************************************************************/
	if (isUS)
		buf[bufidx++] = 0x78;
	else
        {
		buf[bufidx++] = setPll;
		buf[bufidx++] = 0x6d;
        }

	buf[bufidx++] = c;

	/*************************************************************************\
	|* set PLL R register
	\*************************************************************************/
	if (isUS)
		buf[bufidx++] = 0x79;
	else
        {
		buf[bufidx++] = clrPll;
		buf[bufidx++] = setPll;
		buf[bufidx++] = 0x6e;
        }

	buf[bufidx++] = R & 0xff;
	buf[bufidx++] = R >> 8;

	/*************************************************************************\
	|* set PLL A register
	\*************************************************************************/
	if (isUS)
		buf[bufidx++] = 0x7a;
	else
        {
		buf[bufidx++] = clrPll;
		buf[bufidx++] = setPll;
		buf[bufidx++] = 0x6f;
        }

	buf[bufidx++] = N & 0xff;
	buf[bufidx++] = (N >> 8) & 0xff;
	buf[bufidx++] = N >> 16;

	if (!isUS)
		buf[bufidx++] = clrPll;

    return [self _xferOutNum:bufidx outBuf:buf inNum:0 inBuf:NULL];
    }

/*****************************************************************************\
|* Set the digital BFO on a 1500/1550
\*****************************************************************************/
- (BOOL) _setBfo1500:(int)bfo
    {
	uint32_t bN=0, bR=0;

	/*************************************************************************\
	|* calculate BFO's PLL parameters
	\*************************************************************************/
	double f    = 32.0 * (4.55e5 + bfo);
	double Cv   = 2e9;
    int refFreq = _settings.refFreq;
    
	for (uint32_t R = refFreq/5000; R >= refFreq/10000; R--)
        {
		uint32_t d  = (uint32_t)(f * R / refFreq + 0.5);
		uint32_t N  = d >> 6;
		uint32_t A  = d & 63;
		
        if (N > A)
            {
			double Ct = fabs((double)refFreq * d / R - f);
			if (Ct < Cv)
                {
				Cv = Ct;
				bN = d;
				bR = R;
				if (Cv < 0.5)
					break;
                }
            }
        }

	/*************************************************************************\
	|* And set them
	\*************************************************************************/
    int mode    = _settings.curMode;
    int cwSSB   = (mode == RMD_CW) || (mode == RMD_LSB) || (mode == RMD_USB);
    return [self setBfoPllC:(cwSSB) ? 0x40 : 0x42
                          R:bR | 0x4000
                          N:0x300000L + (bN & 63) + ((bN >> 6) << 8)
                     setPll:0x71
                     clrPll:0x70];
    }

/*****************************************************************************\
|* Figure out the MCU version
\*****************************************************************************/
- (void) _getMcuVersion
    {
	char * vs[80];
	int i = 0;

 	/*************************************************************************\
	|* Read the version string
	\*************************************************************************/
   [self _write:GET_MCU_VERSION];
	do
        [self _read:(uint8_t *)(&vs[i++])];
	while (vs[i-1] && (i <= 75));
	vs[i] = 0;

 	/*************************************************************************\
	|* Look for identifiers
	\*************************************************************************/
	if (strstr((const char *)vs, "Vers 2.0.1,")
     || strstr((const char *)vs, "25M-XTAL"))
        _settings.refFreq = 25600000L;

	if (strstr((char *)vs, "FCC"))
        _settings.radioInfo->features |= RIF_USVERSION;
    }

/*****************************************************************************\
|* Identify which radio is attached
\*****************************************************************************/
- (void) _identifyRadio
    {
    RadioInfo *ri = _settings.radioInfo;

 	/*************************************************************************\
	|* get MCU version (states US version and 25M xtal)
	\*************************************************************************/
    [self _getMcuVersion];

 	/*************************************************************************\
	|* get receiver version
	\*************************************************************************/
	uint8_t rv;
    [self _write:GET_RCVR_VERSION];
    [self _read:&rv];
    
	if ((rv > 237) || (rv < 10))
        {
		static uint8_t cmds[] = {0x56, 0x60, 0x6d, 0x2c, 0x6e, 0x00, 0x24, 0x6f,
                                 0x1a, 0x77, 0x72, 0x5b, 0x67};

        /*********************************************************************\
        |* set frequency, mode and attenuator
        \*********************************************************************/
        [self _xferOutNum:sizeof(cmds) outBuf:cmds inNum:0 inBuf:NULL];

		[self _delay:100];
        [self _write:GET_SIGNAL_STRENGTH];
        [self _read:&rv];

		if (rv < 182)
			ri->hwVer = RHV_1000b;		/*  1st generation 1000b */

        /*********************************************************************\
        |* restore settings
        \*********************************************************************/
        [self setMode:_settings.curMode];
        [self setFrequency:_settings.freq];
        [self setAttenuation:_settings.curAttenuation];
        }
        
	else if (rv > 190)
		ri->hwVer = RHV_1000b;
	
    else if (rv > 121)
		ri->hwVer = RHV_1500;
        
	else if (rv > 99)
		ri->hwVer = RHV_3000;
        
	else if (rv > 52)
		ri->hwVer = RHV_3100;
        
	else
		ri->hwVer = RHV_1550;


	if (ri->hwVer <= 0x10a)
		strcpy(ri->descr, "WR-1000");
	else
		{
        if ((ri->hwVer >= 0x200) && (ri->hwVer < 0x300))
            ri->hwVer += 0x100;
        else if ((ri->hwVer >= 0x300) && (ri->hwVer < 0x400))
            ri->hwVer -= 0x100;
        
        sprintf(ri->descr, "WR-%d%.2d0", ri->hwVer >> 8, ri->hwVer & 0xff);
		}
	if (ri->hwInterface)
		strcat(ri->descr, "e");
	else
		strcat(ri->descr, "i");
	
	if (ri->features & RIF_USVERSION)
		strcat(ri->descr, " (US version)");
    }
    
/*****************************************************************************\
|* Hardware-dependent settings.
\*****************************************************************************/
- (void) _initialiseRadioByHardware:(BOOL)fullInit
	{
	static int ModeList[] = {0, 1, 2, 3, 4, 5, 6, 7};
    RadioInfo *ri = _settings.radioInfo;

	/*************************************************************************\
	|* initialize RadioSettings to defaults (1000b)
	\*************************************************************************/
	_settings.ifxOverFreq = 513e6;

	ri->size            = sizeof(RadioInfo);
	ri->features        = 0;
	ri->apiVer          = 0x232;	    //  version 2.50
	if (fullInit)
		ri->hwVer       = RHV_1000b;	//  for starters
	ri->minFreq         = 500000L;
	ri->maxFreq         = 1300000000L;
	ri->freqRes         = 100;
	ri->numModes        = 4;
	ri->maxVolume       = 31;
	ri->maxBFO          = 3000;
	ri->maxFMScanRate   = 50;
	ri->maxAMScanRate   = 10;
	ri->numSources      = 1;
	ri->deviceNum       = 0;
	ri->maxIFShift      = 0;
	ri->dspSources      = 0;
	ri->waveFormats     = 0;
	ri->maxFreqkHz      = 1300000;
	ri->supportedModes  = (ModeTypes) &ModeList;

	if (fullInit)
        [self _identifyRadio];

	if (ri->hwVer >= RHV_1500)
        {
		ri->minFreq     = 150000L;
		ri->maxFreq     = 1500000000L;
		ri->maxFreqkHz  = 1500000L;
		ri->freqRes     = 1;
		ri->numModes    = 6;
		ri->maxBFO      = 0;
		ri->maxIFShift  = 3000;
		ri->features   |= RIF_LSBUSB | RIF_CWIFSHIFT;

		if (ri->hwVer == RHV_1500)
            {
            [self _write:CLEAR_SET_FBO];
            [self _write:CLEAR_SET_PLL];
            
			if (ri->features & RIF_USVERSION)
                {
                [self _write:CONFIG_SET_PLL];
                [self _write:0x00];
                }
            }
        }
#ifdef NEED_WORK
	if (((ri->hwVer > RHV_1500) && (ri->hwVer < RHV_3000)) || (ri->hwVer > RHV_3100))
        {
		/*  2000 series based receivers, set appropriate properties */
		rs->lpSetFreqProc = SetFreq2000;
		rs->lpSetModeProc = SetMode2000;
		rs->lpSetBfoProc = SetBfo2000;
		rs->lpSetAgcProc = SetAgc2000;
		rs->lpSetIfGainProc = SetIfGain2000;
		rs->lpGetSLevelProc = GetSLevel2000;

		rs->dwRefFreq = 25600000L;
		rs->ftIfXOverFreq = 808e6;

		WriteMcuByte(hRadio, 0x6b);

		if (ri->dwFeatures & RIF_USVERSION)
		{
			WriteMcuByte(hRadio, 0x7c);
			WriteMcuByte(hRadio, 0x12);
			WriteMcuByte(hRadio, 0x7b);
			WriteMcuByte(hRadio, 0x32);
		}

		if (ri->wHWVer > RHV_3150)
		{
			ri->dwFeatures |= RIF_AGC | RIF_IFGAIN;
			ri->iMaxIFGain = 100;
			ri->iNumModes = 8;
		}
		else
		{
			SetIfGain2000(hRadio, 100);
			SetAgc2000(hRadio, TRUE);
		}
	}

	if (fFullInit && (rs->dwRefFreq == 12800000L) && (ri->wHWVer > RHV_1000a))
	{
		/*  detect presence of 25MHz reference crystal (uses PLL lock detect) */
		rs->lpSetFreqProc(hRadio, 1100e6, NULL);
		Delay(100);
		if ((GetMcuStatus(hRadio) & 4) >> 2)
			rs->dwRefFreq = 25600000L;
		SetFrequency(hRadio, rs->dwFreq);
	}

	if (ri->wHWVer == RHV_1000a)
		rs->lpGetSLevelProc = GetSLevel1000a;
#endif
    }

- (BOOL) _setFreq1000:(double)freq actualFreq:(double *)actfreq
	{
#ifdef NEED_WORK
	static const double VcoOffsets[5] = {556.325e6, 249.125e6, 58.075e6, -249.125e6, -556.325e6};
	static const double FreqRanges[9] = {1.8e6, 30e6, 50e6, 118e6, 300e6, 513e6, 798e6, 1106e6, 21e9};
	static const double SmFilters[8] = {0.5e6, 0.95e6, 1.8e6, 3.5e6, 7.0e6, 14e6, 30e6, 118e6};

	static const BYTE l0data[2][9] = {
		{0x54, 0x54, 0x54, 0x58, 0x58, 0x98, 0xC0, 0x80, 0x40},
		{0x54, 0x54, 0x54, 0x54, 0x58, 0x98, 0xD0, 0x80, 0x40}};

	LPRADIOSETTINGS rs;
	DWORD Ntot;
	UINT R;
	double fvco, vcoofs;
	BYTE l0;
	int l0idx, range;
	BOOL PllOverride;
	int bufidx = 0;
	BYTE buf[32];

	if (!ValidateHandle(hRadio, &rs))
		return FALSE;

	PllOverride = (!(rs->riInfo.dwFeatures & RIF_USVERSION) &&
		((rs->riInfo.wHWVer == RHV_1500) || (rs->riInfo.wHWVer >= RHV_3100)));

	if (actfreq)
		*actfreq = freq;

	l0idx = (rs->riInfo.wHWVer < RHV_3000) ? 0 : 1;

	l0 = 0xf3;				/*  get current state of latch 0 */
	if (!McuTransfer(hRadio, 1, &l0, 1, &l0))
		return FALSE;

	for (range = 0; range < 9; range++)
		if (freq < FreqRanges[range])
			break;

	if (range > 4)
		vcoofs = VcoOffsets[range-4];
	else
		vcoofs = VcoOffsets[0];

	fvco = freq + vcoofs;

	/*  calculate PLL register values */

	if (rs->iCurMode == RMD_FMW)
	{
		R = rs->dwRefFreq / 20000;
		Ntot = (long)(fvco / 20e3 + 0.5);	/*  get closest freq to multiple of 20 kHz in FMW */
	} else
		GetVcoParams(hRadio, (long)(fvco + 0.5), rs->dwRefFreq,
								 rs->dwRefFreq / 20000, rs->dwRefFreq / 5000, &R, &Ntot);

	if (PllOverride)
		buf[bufidx++] = 0x58;	/*  activate -SETPLL line on non-US 1500s & 3100s */

	/*  set PLL C register */
	buf[bufidx++] = 0x6d;
	buf[bufidx++] = 0x2c;

	/*  calculate actual VCO frequency */
	fvco = (double)Ntot / R * rs->dwRefFreq - vcoofs;

	if (PllOverride)	/*  toggle -SETPLL line */
	{
		buf[bufidx++] = 0x59;
		buf[bufidx++] = 0x58;
	}

	/*  set PLL R register */
	R |= 0x4000;
	buf[bufidx++] = 0x6e;
	buf[bufidx++] = R & 0xff;
	buf[bufidx++] = R >> 8;

	if (PllOverride)	/*  toggle -SETPLL line */
	{
		buf[bufidx++] = 0x59;
		buf[bufidx++] = 0x58;
	}

	/*  set PLL A register */
	Ntot = 0x300000L + (Ntot & 63) + ((Ntot >> 6) << 8);
	buf[bufidx++] = 0x6f;
	buf[bufidx++] = Ntot & 0xff;
	buf[bufidx++] = (Ntot >> 8) & 0xff;
	buf[bufidx++] = Ntot >> 16;

	if (PllOverride)	/*  clear -SETPLL line */
		buf[bufidx++] = 0x59;

	if (rs->riInfo.dwFeatures & RIF_USVERSION)
		buf[bufidx++] = 0x68;	/*  initiate PLL programming if US version */

	/*  set mixer and band lines (latch 0) */
	buf[bufidx++] = 0xf0;
	buf[bufidx++] = (l0 & 0x23) | l0data[l0idx][range];

	if (!McuTransfer(hRadio, bufidx, buf, 0, NULL))
		return FALSE;

	if (rs->riInfo.dwFeatures & RIF_USVERSION)
	{
		/*  if US version, check to see if PLL/latch 0 combination was valid */
		l0 = 0x93;
		if (!McuTransfer(hRadio, 1, &l0, 1, &l0) || l0)
			return FALSE;		/*  invalid PLL params if l0 is non-zero */
	}

	/*  if Spectrum Monitor series, program HF filter board */
	if ((rs->riInfo.wHWVer >= RHV_3000) &&
		(rs->riInfo.wHWVer <= RHV_3100))
	{
		if (freq < 118e6)
		{
			for (range = 0; range < 8; range++)
				if (freq < SmFilters[range])
					break;

			if (range & 1)
				buf[0] = 0x54;
			else
				buf[0] = 0x55;

			if (range & 2)
				buf[1] = 0x52;
			else
				buf[1] = 0x53;

			if (range & 4)
				buf[2] = 0x77;
			else
				buf[2] = 0x76;
		}
		else
		{
			buf[0] = 0x77;

			if (freq >= 1106e6)
			{
				buf[1] = 0x53;
				buf[2] = 0x54;
			}
			else
				if (freq >= 798e6)
				{
					buf[1] = 0x52;
					buf[2] = 0x55;
				}
				else
				{
					buf[1] = 0x52;
					buf[2] = 0x54;
				}
		}
		if (!McuTransfer(hRadio, 3, buf, 0, NULL))
			return FALSE;
	}

	rs->ftActFreq = fvco;
	if (actfreq)
		*actfreq = fvco;

#endif
	return TRUE;
}

- (BOOL) _setMode1000:(int)mode
{
#ifdef NEED_WORK
	LPRADIOSETTINGS rs = RadioSettings[hRadio];

	if (!WriteMcuByte(hRadio, Modes[iMode]))
		return FALSE;

	/*  if was or will be in a mode that does frequency mangling, update the frequency */
	if ((iMode == RMD_CW) || (iMode == RMD_LSB) ||
		(iMode == RMD_USB) || (iMode == RMD_FMW) ||
		(rs->iCurMode == RMD_CW) || (rs->iCurMode == RMD_LSB) ||
		(rs->iCurMode == RMD_USB) || (rs->iCurMode == RMD_FMW))
	{
		int oMode = rs->iCurMode;
		rs->iCurMode = iMode;

		if (((oMode == RMD_CW) || (oMode == RMD_LSB) || (oMode == RMD_USB)) &&
			!((iMode == RMD_CW) || (iMode == RMD_LSB) || (iMode == RMD_USB)))
			rs->lpSetBfoProc(hRadio, 0);	/*  reset BFO if not in SSB anymore */

		SetFrequency(hRadio, rs->dwFreq);
	}

	/*  set narrow filter if in SSB mode */
	if (rs->riInfo.wHWVer >= RHV_1500)
		WriteMcuByte(hRadio, ((iMode == RMD_CW) || (iMode == RMD_LSB) ||
			(iMode == RMD_USB)) ? 0x6b : 0x6c);

	rs->iCurMode = iMode;

#endif
	return TRUE;
}

#pragma mark - Utility methods

- (long) _getTickCount
	{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec*1000 + tv.tv_usec/1000;
	}

- (void) _delay:(int)ms
	{
	usleep(ms * 1000);
	}
@end
